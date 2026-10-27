class_name SignallingClient
extends Node
## Talks to the signalling Worker: creates a room, then relays WebRTC
## offer/answer/ICE over a WebSocket. Protocol: docs/signalling.md.

signal room_created(code: String)
signal joined(role: String)
signal peer_joined
signal peer_left
signal offer_received(sdp: String)
signal answer_received(sdp: String)
signal ice_received(media: String, index: int, candidate: String)
signal server_error(reason: String)
## The socket closed. reason is the Worker's close reason (e.g. "room_full"),
## "server_unreachable" if it never opened, or "connection_lost".
signal closed(reason: String)
## Extra detail for the connection log.
signal debug(text: String)

const PROTOCOL_VERSION: int = 1
## Keepalive (docs/signalling.md): ping this often while the socket is open...
const KEEPALIVE_INTERVAL_SEC: float = 5.0
## ...and give up if nothing comes back this long after a ping. Timed from the
## ping, not the last message, so a tab that was hidden (game paused, no
## pings sent) isn't counted as a dead link when it comes back.
const KEEPALIVE_TIMEOUT_SEC: float = 10.0
## Must match PING_FRAME in worker/src/protocol.ts exactly: the Worker answers it
## with an auto-response, which only matches identical text.
const PING_FRAME: String = "{\"v\":1,\"t\":\"ping\"}"

var base_url: String = ""

var _http: HTTPRequest
var _ws: WebSocketPeer = null
var _was_open: bool = false
var _closing: bool = false
var _since_ping_sec: float = 0.0
## Seconds since the oldest unanswered ping, or -1 if none is outstanding.
var _waiting_for_reply_sec: float = -1.0


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_create_completed)


func create_room() -> void:
	var err: Error = _http.request(base_url + "/rooms", [], HTTPClient.METHOD_POST, "")
	if err != OK:
		closed.emit("server_unreachable")


func join_room(code: String) -> void:
	_open(code, "")


func send_offer(sdp: String) -> void:
	_send({"t": "offer", "sdp": sdp})


func send_answer(sdp: String) -> void:
	_send({"t": "answer", "sdp": sdp})


func send_ice(media: String, index: int, candidate: String) -> void:
	_send({"t": "ice", "media": media, "index": index, "name": candidate})


## Closes the socket without emitting closed. Used once WebRTC is up, or on leave.
func close() -> void:
	_http.cancel_request()
	if _ws != null:
		_closing = true
		_ws.close(1000, "done")


func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			_was_open = true
			while _ws.get_available_packet_count() > 0:
				_waiting_for_reply_sec = -1.0
				_handle(_ws.get_packet().get_string_from_utf8())
			_tick_keepalive(delta)
		WebSocketPeer.STATE_CLOSED:
			var reason: String = _ws.get_close_reason()
			if not _closing:
				debug.emit("Signalling socket closed: code %d, reason '%s'" % [_ws.get_close_code(), reason])
			_ws = null
			if _closing:
				return
			if reason.is_empty():
				reason = "connection_lost" if _was_open else "server_unreachable"
			closed.emit(reason)


func _tick_keepalive(delta: float) -> void:
	if _waiting_for_reply_sec >= 0.0:
		_waiting_for_reply_sec += delta
		if _waiting_for_reply_sec >= KEEPALIVE_TIMEOUT_SEC:
			debug.emit("No reply from the game server for %d s" % int(KEEPALIVE_TIMEOUT_SEC))
			_drop("connection_lost")
			return
	_since_ping_sec += delta
	if _since_ping_sec >= KEEPALIVE_INTERVAL_SEC:
		_since_ping_sec = 0.0
		_ws.send_text(PING_FRAME)
		if _waiting_for_reply_sec < 0.0:
			_waiting_for_reply_sec = 0.0


## Abandons a socket that has stopped answering and reports it as closed.
## close() can't be used: on a dead network the close handshake never finishes.
func _drop(reason: String) -> void:
	_ws.close()
	_ws = null
	closed.emit(reason)


func _on_create_completed(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or status != 201:
		debug.emit("Create room failed: HTTPRequest result %d, HTTP status %d" % [result, status])
		closed.emit("server_unreachable")
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("code")) != TYPE_STRING or typeof(data.get("token")) != TYPE_STRING:
		closed.emit("server_unreachable")
		return
	room_created.emit(data["code"])
	_open(data["code"], data["token"])


func _open(code: String, token: String) -> void:
	var ws_base: String = base_url
	if ws_base.begins_with("https://"):
		ws_base = "wss://" + ws_base.substr(8)
	elif ws_base.begins_with("http://"):
		ws_base = "ws://" + ws_base.substr(7)
	var url: String = "%s/rooms/%s/ws" % [ws_base, code.uri_encode()]
	if not token.is_empty():
		url += "?token=" + token
	_ws = WebSocketPeer.new()
	_was_open = false
	_closing = false
	_since_ping_sec = 0.0
	_waiting_for_reply_sec = -1.0
	if _ws.connect_to_url(url) != OK:
		_ws = null
		closed.emit("server_unreachable")


func _send(msg: Dictionary) -> void:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	msg["v"] = PROTOCOL_VERSION
	_ws.send_text(JSON.stringify(msg))


func _handle(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = data
	# JSON numbers arrive as floats.
	if msg.get("v") != float(PROTOCOL_VERSION):
		return
	match msg.get("t"):
		"joined":
			joined.emit(str(msg.get("role", "")))
		"peer_joined":
			peer_joined.emit()
		"peer_left":
			peer_left.emit()
		"offer":
			offer_received.emit(str(msg.get("sdp", "")))
		"answer":
			answer_received.emit(str(msg.get("sdp", "")))
		"ice":
			ice_received.emit(str(msg.get("media", "")), int(msg.get("index", 0)), str(msg.get("name", "")))
		"error":
			server_error.emit(str(msg.get("reason", "")))
