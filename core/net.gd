extends Node
## App-wide connection service (autoload "Net"). Hosts or joins a room through
## the signalling Worker, sets up the peer-to-peer WebRTC link, then carries
## game messages (see Messages) over the reliable channel.

signal state_changed(state: State)
signal room_code_ready(code: String)
## The link is up and the opponent's HELLO arrived.
signal connected(opponent: PlayerInfo)
## Hosting or joining failed before the link came up. reason is a key for describe().
signal connection_failed(reason: String)
## An established link went away. reason is a key for describe().
signal disconnected(reason: String)
signal message_received(type: Messages.Type, payload: Dictionary)
## The other player went quiet (WARN) or was heard from again (OK). See LinkWatch.
signal link_status_changed(status: LinkWatch.Status)
signal ping_result(rtt_msec: int)
## Human-readable connection events, for the on-screen log.
signal log_line(text: String)

enum State { IDLE, CREATING, WAITING, JOINING, CONNECTING, CONNECTED }

const CONNECT_TIMEOUT_SEC: float = 15.0
const HEARTBEAT_INTERVAL_SEC: float = 1.0
const HOST_ID: int = 1
const GUEST_ID: int = 2
const ICE_SERVERS: Array = [
	{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]},
]
const REASONS: Dictionary = {
	"server_unreachable": "Couldn't reach the game server.",
	"connection_lost": "Lost the connection to the game server.",
	"no_such_room": "Room not found. Check the code.",
	"room_full": "That room is full or its game has already started.",
	"expired": "The room expired. Host a new game.",
	"bad_token": "Couldn't join as host.",
	"bad_version": "Game versions don't match. Refresh the page.",
	"bad_message": "Connection error (bad message).",
	"too_many_messages": "Connection error (too many messages).",
	"timeout": "Couldn't connect to the other player (timed out).",
	"ice_failed": "Couldn't connect to the other player (network blocked).",
	"opponent_left": "The other player left.",
	"link_lost": "Lost the connection to the other player.",
}

var state: State = State.IDLE
var is_host: bool = false
var room_code: String = ""
## Set by the title screen before hosting or joining.
var local_player: PlayerInfo = PlayerInfo.new()
var opponent: PlayerInfo = null

var _scene_mp: SceneMultiplayer
var _signalling: SignallingClient
var _rtc_peer: WebRTCMultiplayerPeer = null
var _connection: WebRTCPeerConnection = null
var _timeout: Timer
var _last_rtc_state: int = -1
var _watch: LinkWatch = LinkWatch.new()
var link_status: LinkWatch.Status = LinkWatch.Status.OK
var _since_heartbeat_sec: float = 0.0


func _ready() -> void:
	_scene_mp = multiplayer as SceneMultiplayer
	_scene_mp.peer_connected.connect(_on_peer_connected)
	_scene_mp.peer_disconnected.connect(_on_peer_disconnected)
	_scene_mp.peer_packet.connect(_on_peer_packet)

	_signalling = SignallingClient.new()
	_signalling.base_url = signalling_url()
	add_child(_signalling)
	_signalling.room_created.connect(_on_room_created)
	_signalling.joined.connect(_on_joined)
	_signalling.peer_joined.connect(_on_signal_peer_joined)
	_signalling.peer_left.connect(_on_signal_peer_left)
	_signalling.offer_received.connect(_on_offer_received)
	_signalling.answer_received.connect(_on_answer_received)
	_signalling.ice_received.connect(_on_ice_received)
	_signalling.server_error.connect(func(reason: String) -> void: _log("Server: " + reason))
	_signalling.debug.connect(_log)
	_signalling.closed.connect(_on_signalling_closed)

	_timeout = Timer.new()
	_timeout.one_shot = true
	add_child(_timeout)
	_timeout.timeout.connect(_on_timeout)


static func describe(reason: String) -> String:
	return REASONS.get(reason, "Connection error (%s)." % reason)


## The signalling Worker's base URL. Uses get_setting_with_override so feature
## tag overrides apply (signalling_url.release points at the deployed Worker);
## plain get_setting ignores them.
static func signalling_url() -> String:
	var url: Variant = ProjectSettings.get_setting_with_override("battle_arcade/signalling_url")
	return "http://127.0.0.1:8787" if url == null else str(url)


func host_game() -> void:
	_reset()
	is_host = true
	_set_state(State.CREATING)
	_log("Creating room at " + _signalling.base_url)
	_signalling.create_room()


func join_game(code: String) -> void:
	_reset()
	is_host = false
	room_code = code.strip_edges().to_upper()
	_set_state(State.JOINING)
	_log("Joining room " + room_code)
	_signalling.join_room(room_code)


func leave() -> void:
	_reset()


func send_message(type: Messages.Type, payload: Dictionary = {}) -> void:
	if state != State.CONNECTED:
		return
	_scene_mp.send_bytes(Messages.encode(type, payload), 0, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func ping() -> void:
	send_message(Messages.Type.PING, {"t": Time.get_ticks_msec()})


func _process(delta: float) -> void:
	# The scene tree polls the multiplayer peer (delivering packets) before
	# _process runs, so anything that arrived this frame has already counted.
	if state == State.CONNECTED:
		_tick_heartbeat(delta)
	_watch_rtc_state()


## Sends a heartbeat each second and checks how long the other side has been quiet.
func _tick_heartbeat(delta: float) -> void:
	_since_heartbeat_sec += delta
	if _since_heartbeat_sec >= HEARTBEAT_INTERVAL_SEC:
		_since_heartbeat_sec = 0.0
		send_message(Messages.Type.HEARTBEAT)
	var status: LinkWatch.Status = _watch.status(Time.get_ticks_msec())
	if status == LinkWatch.Status.LOST:
		_log("Nothing heard from the other player; giving up")
		_reset()
		disconnected.emit("link_lost")
		return
	_set_link_status(status)


func _watch_rtc_state() -> void:
	# Only logs changes, and fails a connection attempt if ICE fails.
	if _connection == null:
		return
	var rtc_state: int = _connection.get_connection_state()
	if rtc_state == _last_rtc_state:
		return
	_last_rtc_state = rtc_state
	_log("WebRTC: " + _rtc_state_name(rtc_state))
	if rtc_state == WebRTCPeerConnection.STATE_FAILED and state == State.CONNECTING:
		_fail("ice_failed")


# --- Signalling -------------------------------------------------------------

func _on_room_created(code: String) -> void:
	room_code = code
	_log("Room code " + code)
	room_code_ready.emit(code)


func _on_joined(role: String) -> void:
	_log("Joined room as " + role)
	if is_host:
		_set_state(State.WAITING)
	else:
		_start_rtc()


func _on_signal_peer_joined() -> void:
	_log("Other player is in the room")
	if is_host and state == State.WAITING:
		_start_rtc()


func _on_signal_peer_left() -> void:
	_log("Other player left the room")
	if state == State.CONNECTING:
		_fail("opponent_left")


func _on_offer_received(sdp: String) -> void:
	if _connection != null and not is_host:
		_log("Got offer")
		_connection.set_remote_description("offer", sdp)


func _on_answer_received(sdp: String) -> void:
	if _connection != null and is_host:
		_log("Got answer")
		_connection.set_remote_description("answer", sdp)


func _on_ice_received(media: String, index: int, candidate: String) -> void:
	if _connection != null:
		_connection.add_ice_candidate(media, index, candidate)


func _on_signalling_closed(reason: String) -> void:
	if state != State.IDLE and state != State.CONNECTED:
		_fail(reason)


# --- WebRTC -----------------------------------------------------------------

func _start_rtc() -> void:
	_set_state(State.CONNECTING)
	_timeout.start(CONNECT_TIMEOUT_SEC)
	_rtc_peer = WebRTCMultiplayerPeer.new()
	if is_host:
		_rtc_peer.create_server()
	else:
		_rtc_peer.create_client(GUEST_ID)
	_connection = WebRTCPeerConnection.new()
	if _connection.initialize({"iceServers": ICE_SERVERS}) != OK:
		_fail("ice_failed")
		return
	_connection.session_description_created.connect(_on_session_description_created)
	_connection.ice_candidate_created.connect(_on_ice_candidate_created)
	# add_peer creates the data channels, so it must come before the offer.
	_rtc_peer.add_peer(_connection, GUEST_ID if is_host else HOST_ID)
	multiplayer.multiplayer_peer = _rtc_peer
	if is_host:
		_connection.create_offer()


func _on_session_description_created(type: String, sdp: String) -> void:
	_connection.set_local_description(type, sdp)
	if type == "offer":
		_log("Sending offer")
		_signalling.send_offer(sdp)
	else:
		_log("Sending answer")
		_signalling.send_answer(sdp)


func _on_ice_candidate_created(media: String, index: int, candidate: String) -> void:
	_signalling.send_ice(media, index, candidate)


func _on_peer_connected(_id: int) -> void:
	_log("Peer-to-peer link is up")
	# The connect timeout keeps running until the opponent's HELLO arrives.
	_signalling.close()
	_watch.heard(Time.get_ticks_msec())
	_since_heartbeat_sec = 0.0
	_set_state(State.CONNECTED)
	send_message(Messages.Type.HELLO, local_player.to_dict())


func _on_peer_disconnected(_id: int) -> void:
	if state == State.CONNECTED:
		_log("Peer-to-peer link closed")
		_reset()
		disconnected.emit("opponent_left")


func _on_peer_packet(_id: int, packet: PackedByteArray) -> void:
	_watch.heard(Time.get_ticks_msec())
	_set_link_status(LinkWatch.Status.OK)
	var msg: Dictionary = Messages.decode(packet)
	if msg.has("error"):
		_log("Dropped packet: " + str(msg["error"]))
		if msg["error"] == "bad_version":
			_reset()
			disconnected.emit("bad_version")
		return
	var payload: Dictionary = msg["payload"]
	match msg["type"]:
		Messages.Type.HELLO:
			if opponent != null:
				return
			var info: PlayerInfo = PlayerInfo.from_dict(payload)
			if info == null:
				_log("Bad HELLO from opponent")
				return
			_timeout.stop()
			opponent = info
			_log("Opponent is " + info.player_name)
			connected.emit(info)
		Messages.Type.PING:
			send_message(Messages.Type.PONG, payload)
		Messages.Type.HEARTBEAT:
			pass
		Messages.Type.PONG:
			if typeof(payload.get("t")) == TYPE_INT:
				ping_result.emit(Time.get_ticks_msec() - int(payload["t"]))
		_:
			message_received.emit(msg["type"], payload)


func _on_timeout() -> void:
	# CONNECTED without an opponent means the link came up but HELLO never arrived.
	if state == State.CONNECTING or (state == State.CONNECTED and opponent == null):
		_fail("timeout")


# --- Helpers ----------------------------------------------------------------

func _fail(reason: String) -> void:
	_log("Failed: " + reason)
	_reset()
	connection_failed.emit(reason)


func _reset() -> void:
	# Go idle first: closing the peer can emit peer_disconnected, which must
	# not see the old CONNECTED state and reset again.
	_set_state(State.IDLE)
	_timeout.stop()
	_signalling.close()
	var old_peer: WebRTCMultiplayerPeer = _rtc_peer
	_rtc_peer = null
	_connection = null
	_last_rtc_state = -1
	_set_link_status(LinkWatch.Status.OK)
	opponent = null
	room_code = ""
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if old_peer != null:
		old_peer.close()


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)


func _set_link_status(status: LinkWatch.Status) -> void:
	if status == link_status:
		return
	link_status = status
	_log("Link: " + ("waiting for the other player" if status == LinkWatch.Status.WARN else "ok"))
	link_status_changed.emit(status)


func _log(text: String) -> void:
	print("[Net] ", text)
	log_line.emit(text)


static func _rtc_state_name(rtc_state: int) -> String:
	match rtc_state:
		WebRTCPeerConnection.STATE_NEW: return "new"
		WebRTCPeerConnection.STATE_CONNECTING: return "connecting"
		WebRTCPeerConnection.STATE_CONNECTED: return "connected"
		WebRTCPeerConnection.STATE_DISCONNECTED: return "disconnected"
		WebRTCPeerConnection.STATE_FAILED: return "failed"
		WebRTCPeerConnection.STATE_CLOSED: return "closed"
	return str(rtc_state)
