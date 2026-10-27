class_name GemBattleBot
extends BotOpponent
## Gem Battle bot: plays a real Drop board with the same pairs as the player.
## DropPlanner picks where each pair goes; the difficulty sets how long it
## thinks, whether it looks ahead, and how often it slips up. It sends and
## receives the same messages as a remote player (attacks, board snapshots,
## topping out).

var _game: DropGame = null
var _settings: DropPlanner.Settings = null
var _search: DropPlanner.Search = null
var _playing: bool = false
var _think_timer: float = 0.0
var _start_msec: int = 0
var _board_dirty: bool = true
var _snapshot_timer: float = 0.0


func start_match(match_seed: int, _mode: String) -> void:
	var pieces_rng := RandomNumberGenerator.new()
	pieces_rng.seed = match_seed
	_settings = DropPlanner.settings_for(difficulty)
	_game = DropGame.new()
	_game.piece_spawned.connect(_on_piece_spawned)
	_game.changed.connect(func() -> void: _board_dirty = true)
	_game.incoming_changed.connect(func(_amount: int) -> void: _board_dirty = true)
	_game.attack_sent.connect(func(amount: int) -> void: reply(GemBattle.Kind.ATTACK, {"n": amount}))
	_game.topped_out.connect(_on_topped_out)
	_playing = true
	_start_msec = Time.get_ticks_msec()
	_game.start(pieces_rng, rng)


func stop_match() -> void:
	_playing = false


func _process(delta: float) -> void:
	if not _playing:
		return
	_game.tick(delta)
	_snapshot_timer -= delta
	if _board_dirty and _snapshot_timer <= 0.0:
		_snapshot_timer = GemBattle.SNAPSHOT_INTERVAL_SEC
		_board_dirty = false
		_send_snapshot()
	if _game.phase != DropGame.Phase.FALLING:
		return
	if _search != null:
		_search.step()
	_think_timer -= delta
	if _think_timer <= 0.0:
		_play_plan()


## Start deciding straight away (one step per frame); act after "thinking".
## The think time is capped so the pair doesn't land on its own first.
func _on_piece_spawned() -> void:
	_search = DropPlanner.Search.new(_game.board, _game.piece_colours, _game.next_colours, _settings, rng)
	var think: float = _settings.think_sec * rng.randf_range(0.8, 1.2)
	_think_timer = minf(think, _game.fall_interval() * 2.0)


func _play_plan() -> void:
	while not _search.step():
		pass
	var plan: DropPlanner.Placement = _search.best
	if plan != null:
		for i: int in DropGame.OFFSETS.size():
			if _game.rotation == plan.rotation or not _game.rotate(1):
				break
		var dir: int = signi(plan.column - _game.pivot.x)
		while _game.pivot.x != plan.column and _game.move(dir):
			pass
	_game.hard_drop()


func _send_snapshot() -> void:
	reply(GemBattle.Kind.BOARD, {"b": GemBoard.encode_cells(_game.cells_with_piece()), "i": _game.incoming})


func _on_topped_out() -> void:
	_playing = false
	# Send the final board so the player sees how the bot lost.
	_send_snapshot()
	reply(GemBattle.Kind.TOPPED, {"t": Time.get_ticks_msec() - _start_msec})


func _on_player_message(kind: int, data: Dictionary) -> void:
	match kind:
		GemBattle.Kind.ATTACK:
			var amount: Variant = data.get("n")
			if _playing and typeof(amount) == TYPE_INT:
				_game.add_incoming(clampi(amount, 0, GemBoard.MAX_ATTACK))
		GemBattle.Kind.TOPPED:
			if _playing:
				stop_match()
				reply(GemBattle.Kind.TOPPED_ACK)
		GemBattle.Kind.TOPPED_ACK:
			stop_match()
