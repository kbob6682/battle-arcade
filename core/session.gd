extends Node
## App-wide match session (autoload "Session"): who we're playing, which game
## and mode, and the lobby -> countdown -> match -> results loop. Screen
## changes happen here so the flow lives in one place. The host decides the
## game and starts each match; the guest follows the host's messages.

signal lobby_changed
signal rematch_changed

enum Kind { NONE, ONLINE, BOT }

const TITLE_SCENE: String = "res://ui/title/title_screen.tscn"
const LOBBY_SCENE: String = "res://ui/lobby/lobby.tscn"
const MATCH_SCENE: String = "res://ui/match/match.tscn"
## Time to read "Connected to X!" before the lobby opens.
const LOBBY_DELAY_SEC: float = 1.0

var kind: Kind = Kind.NONE
var is_host: bool = false
var opponent: Opponent = null
var game_id: String = ""
var game_mode: String = ""
var bot_difficulty: BotOpponent.Difficulty = BotOpponent.Difficulty.MEDIUM
var local_ready: bool = false
var opponent_ready: bool = false
var local_rematch: bool = false
var opponent_rematch: bool = false
var match_seed: int = 0
var match_number: int = 0
var last_outcome: int = -1

var _end_message: String = ""
var _session_id: int = 0


func _ready() -> void:
	Net.connected.connect(_on_net_connected)
	Net.disconnected.connect(_on_net_disconnected)
	Net.message_received.connect(_on_net_message)


func current_game() -> GameInfo:
	return GameRegistry.find(game_id)


func opponent_name() -> String:
	if kind == Kind.BOT:
		return "%s Bot" % BotOpponent.difficulty_name(bot_difficulty)
	if opponent != null and opponent.info != null:
		return opponent.info.player_name
	return "?"


## Returns and clears the message to show on the title screen (e.g. "The other player left.").
func take_end_message() -> String:
	var text: String = _end_message
	_end_message = ""
	return text


# --- Starting a session -----------------------------------------------------

func begin_bot() -> void:
	_clear()
	kind = Kind.BOT
	is_host = true
	_pick_default()
	_go(LOBBY_SCENE)


func _on_net_connected(info: PlayerInfo) -> void:
	_clear()
	kind = Kind.ONLINE
	is_host = Net.is_host
	var remote := RemoteOpponent.new()
	remote.info = info
	_set_opponent(remote)
	if is_host:
		_pick_default()
	var id: int = _session_id
	get_tree().create_timer(LOBBY_DELAY_SEC).timeout.connect(func() -> void:
		if id == _session_id and kind == Kind.ONLINE:
			_go(LOBBY_SCENE))


# --- Lobby ------------------------------------------------------------------

## Host (or bot mode) chooses the game and mode. Clears both ready flags.
func pick(id: String, mode: String) -> void:
	if not is_host or not _valid_pick(id, mode):
		return
	game_id = id
	game_mode = mode
	local_ready = false
	opponent_ready = false
	if kind == Kind.ONLINE:
		Net.send_message(Messages.Type.PICK, {"game": game_id, "mode": game_mode})
	lobby_changed.emit()


func set_bot_difficulty(value: BotOpponent.Difficulty) -> void:
	bot_difficulty = value
	lobby_changed.emit()


func set_ready(value: bool) -> void:
	if current_game() == null:
		return
	local_ready = value
	if kind == Kind.ONLINE:
		Net.send_message(Messages.Type.READY, {"ready": value, "game": game_id, "mode": game_mode})
	lobby_changed.emit()
	_try_start()


func _try_start() -> void:
	if not is_host or not local_ready:
		return
	if kind == Kind.BOT or opponent_ready:
		_start_match()


# --- Match ------------------------------------------------------------------

func _start_match() -> void:
	match_number += 1
	match_seed = randi()
	if kind == Kind.ONLINE:
		Net.send_message(Messages.Type.START, {"seed": match_seed, "n": match_number, "game": game_id, "mode": game_mode})
	_begin_match()


func _begin_match() -> void:
	_reset_flags()
	last_outcome = -1
	if kind == Kind.BOT:
		var bot: BotOpponent = current_game().create_bot(bot_difficulty)
		var bot_info := PlayerInfo.new()
		bot_info.player_name = opponent_name().replace(" ", "-")
		bot_info.colour_index = (Net.local_player.colour_index + 4) % PlayerInfo.COLOURS.size()
		bot.info = bot_info
		_set_opponent(bot)
	opponent.begin_match(match_number)
	_go(MATCH_SCENE)


## Called by the match screen when the game ends. (Later: report to the Worker.)
func record_result(outcome: int) -> void:
	last_outcome = outcome
	if opponent is BotOpponent:
		(opponent as BotOpponent).stop_match()


func request_rematch() -> void:
	if local_rematch:
		return
	local_rematch = true
	if kind == Kind.ONLINE:
		Net.send_message(Messages.Type.REMATCH)
	rematch_changed.emit()
	if kind == Kind.BOT or (is_host and opponent_rematch):
		_start_match()


func to_lobby() -> void:
	if kind == Kind.ONLINE:
		Net.send_message(Messages.Type.TO_LOBBY)
	_enter_lobby()


func leave() -> void:
	var was_online: bool = kind == Kind.ONLINE
	_clear()
	if was_online:
		Net.leave()
	_go(TITLE_SCENE)


func _enter_lobby() -> void:
	_reset_flags()
	if opponent is BotOpponent:
		(opponent as BotOpponent).stop_match()
	_go(LOBBY_SCENE)


# --- Network ----------------------------------------------------------------

func _on_net_disconnected(reason: String) -> void:
	if kind != Kind.ONLINE:
		return
	_clear()
	_end_message = Net.describe(reason)
	_go(TITLE_SCENE)


func _on_net_message(type: int, payload: Dictionary) -> void:
	if kind != Kind.ONLINE:
		return
	match type:
		Messages.Type.PICK:
			var id: Variant = payload.get("game")
			var mode: Variant = payload.get("mode")
			if is_host or typeof(id) != TYPE_STRING or typeof(mode) != TYPE_STRING or not _valid_pick(id, mode):
				return
			game_id = id
			game_mode = mode
			local_ready = false
			opponent_ready = false
			lobby_changed.emit()
		Messages.Type.READY:
			var ready_value: Variant = payload.get("ready")
			if typeof(ready_value) != TYPE_BOOL:
				return
			# A READY sent before the latest pick reached the other side doesn't count.
			if payload.get("game") != game_id or payload.get("mode") != game_mode:
				return
			opponent_ready = ready_value
			lobby_changed.emit()
			_try_start()
		Messages.Type.START:
			var seed_value: Variant = payload.get("seed")
			var number: Variant = payload.get("n")
			var id: Variant = payload.get("game")
			var mode: Variant = payload.get("mode")
			if is_host or typeof(seed_value) != TYPE_INT or typeof(number) != TYPE_INT:
				return
			if typeof(id) != TYPE_STRING or typeof(mode) != TYPE_STRING or not _valid_pick(id, mode):
				return
			game_id = id
			game_mode = mode
			match_seed = seed_value
			match_number = number
			_begin_match()
		Messages.Type.REMATCH:
			opponent_rematch = true
			rematch_changed.emit()
			if is_host and local_rematch:
				_start_match()
		Messages.Type.TO_LOBBY:
			_enter_lobby()


# --- Helpers ----------------------------------------------------------------

func _pick_default() -> void:
	var games: Array[GameInfo] = GameRegistry.visible_games()
	if games.is_empty():
		return
	pick(games[0].id, games[0].modes[0])


func _valid_pick(id: String, mode: String) -> bool:
	var game: GameInfo = GameRegistry.find(id)
	return game != null and game.modes.has(mode)


func _reset_flags() -> void:
	local_ready = false
	opponent_ready = false
	local_rematch = false
	opponent_rematch = false


func _set_opponent(new_opponent: Opponent) -> void:
	if opponent != null:
		opponent.queue_free()
	opponent = new_opponent
	if opponent != null:
		add_child(opponent)


func _clear() -> void:
	_session_id += 1
	kind = Kind.NONE
	is_host = false
	_set_opponent(null)
	game_id = ""
	game_mode = ""
	_reset_flags()
	last_outcome = -1


func _go(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
