class_name TugOfWarBot
extends BotOpponent
## Tug of War bot: plays a real side with the same pieces as the player.
## TugPlanner picks where each piece goes; the difficulty sets how long it
## thinks, whether it looks ahead, and how often it slips up. It sends and
## receives the same messages as a remote player (clears, snapshots, topping
## out), so the line moves the same way for both.

var _game: TugGame = null
var _settings: TugPlanner.Settings = null
var _search: TugPlanner.Search = null
var _playing: bool = false
var _think_timer: float = 0.0
var _start_msec: int = 0
var _board_dirty: bool = true
var _snapshot_timer: float = 0.0


func start_match(match_seed: int, _mode: String) -> void:
	var pieces_rng := RandomNumberGenerator.new()
	pieces_rng.seed = match_seed
	_settings = TugPlanner.settings_for(difficulty)
	_game = TugGame.new()
	_game.piece_spawned.connect(_on_piece_spawned)
	_game.changed.connect(func() -> void: _board_dirty = true)
	# A push changes the side, so think again (same timer).
	_game.line_moved.connect(func(_width: int) -> void: _replan())
	_game.columns_cleared.connect(func(count: int, _depths: Array[int]) -> void: reply(TugOfWar.Kind.CLEAR, {"n": count}))
	_game.topped_out.connect(_on_topped_out)
	_playing = true
	_start_msec = Time.get_ticks_msec()
	_game.start(pieces_rng)


func stop_match() -> void:
	_playing = false


func _process(delta: float) -> void:
	if not _playing:
		return
	_game.tick(delta)
	# Topping out sends the last snapshot and TOPPED; nothing may follow it.
	if not _playing:
		return
	_snapshot_timer -= delta
	if _board_dirty and _snapshot_timer <= 0.0:
		_snapshot_timer = TugOfWar.SNAPSHOT_INTERVAL_SEC
		_board_dirty = false
		_send_snapshot()
	if _game.phase != TugGame.Phase.FALLING:
		return
	if _search != null:
		_search.step()
	_think_timer -= delta
	if _think_timer <= 0.0:
		_play_plan()


## Start deciding straight away (one step per frame); act after "thinking".
## The think time is capped so the piece doesn't land on its own first.
func _on_piece_spawned() -> void:
	_replan()
	var think: float = _settings.think_sec * rng.randf_range(0.8, 1.2)
	_think_timer = minf(think, _game.step_interval() * 4.0)


func _replan() -> void:
	if _game.phase == TugGame.Phase.FALLING:
		_search = TugPlanner.Search.new(_game.board, _game.piece_type, _game.next_type, _settings, rng)


func _play_plan() -> void:
	if _search == null:
		_replan()
	while not _search.step():
		pass
	var plan: TugPlanner.Placement = _search.best
	_search = null
	if plan != null:
		for i: int in 4:
			if _game.rotation == plan.rotation or not _game.rotate(1):
				break
		var dir: int = signi(plan.row - _game.pos.y)
		while _game.pos.y != plan.row and _game.move(dir):
			pass
	_game.hard_drop()


func _send_snapshot() -> void:
	reply(TugOfWar.Kind.BOARD, {"b": TugBoard.encode_cells(_game.cells_with_piece()), "w": _game.board.width})


func _on_topped_out() -> void:
	_playing = false
	# Send the final side so the player sees how the bot lost.
	_send_snapshot()
	reply(TugOfWar.Kind.TOPPED, {"t": Time.get_ticks_msec() - _start_msec})


func _on_player_message(kind: int, data: Dictionary) -> void:
	match kind:
		TugOfWar.Kind.CLEAR:
			var n: Variant = data.get("n")
			if _playing and typeof(n) == TYPE_INT and n >= 1 and n <= TugOfWar.MAX_CLEAR:
				_game.push_line(n)
		TugOfWar.Kind.TOPPED:
			if _playing:
				stop_match()
				reply(TugOfWar.Kind.TOPPED_ACK)
		TugOfWar.Kind.TOPPED_ACK:
			stop_match()
