class_name GemBattleBot
extends BotOpponent
## Gem Battle bot: plays a real board with the same gems as the player, in
## either mode. DropPlanner picks where each pair goes; SwapPlanner picks which
## gems to swap. The difficulty sets how long it thinks, whether it looks
## ahead, and how often it slips up. It sends and receives the same messages as
## a remote player (attacks, board snapshots, topping out).

var _game: GemModeGame = null
var _drop_settings: DropPlanner.Settings = null
var _drop_search: DropPlanner.Search = null
var _swap_settings: SwapPlanner.Settings = null
var _swap_search: SwapPlanner.Search = null
## Swap mode: deciding on the next swap (timer running).
var _swap_thinking: bool = false
var _playing: bool = false
var _think_timer: float = 0.0
var _start_msec: int = 0
var _board_dirty: bool = true
var _snapshot_timer: float = 0.0


func start_match(match_seed: int, mode: String) -> void:
	var shared_rng := RandomNumberGenerator.new()
	shared_rng.seed = match_seed
	if mode == GemBattle.SWAP_MODE:
		_swap_settings = SwapPlanner.settings_for(difficulty)
		var swap_game := SwapGame.new()
		# A new row changes the board, so work the swap out again (same timer).
		swap_game.rows_risen.connect(func(_rows: int) -> void: _swap_search = null)
		_game = swap_game
	else:
		_drop_settings = DropPlanner.settings_for(difficulty)
		var drop_game := DropGame.new()
		drop_game.piece_spawned.connect(_on_piece_spawned)
		_game = drop_game
	_game.changed.connect(func() -> void: _board_dirty = true)
	_game.incoming_changed.connect(func(_amount: int) -> void: _board_dirty = true)
	_game.attack_sent.connect(func(amount: int) -> void: reply(GemBattle.Kind.ATTACK, {"n": amount}))
	_game.topped_out.connect(_on_topped_out)
	_playing = true
	_start_msec = Time.get_ticks_msec()
	_game.start(shared_rng, rng)


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
		_snapshot_timer = GemBattle.SNAPSHOT_INTERVAL_SEC
		_board_dirty = false
		_send_snapshot()
	if _game is SwapGame:
		_play_swap(delta)
	else:
		_play_drop(delta)


func _play_drop(delta: float) -> void:
	var drop: DropGame = _game as DropGame
	if drop.phase != DropGame.Phase.FALLING:
		return
	if _drop_search != null:
		_drop_search.step()
	_think_timer -= delta
	if _think_timer <= 0.0:
		_drop_plan()


## Start deciding straight away (one step per frame); act after "thinking".
## The think time is capped so the pair doesn't land on its own first.
func _on_piece_spawned() -> void:
	var drop: DropGame = _game as DropGame
	_drop_search = DropPlanner.Search.new(drop.board, drop.piece_colours, drop.next_colours, _drop_settings, rng)
	var think: float = _drop_settings.think_sec * rng.randf_range(0.8, 1.2)
	_think_timer = minf(think, drop.fall_interval() * 2.0)


func _drop_plan() -> void:
	var drop: DropGame = _game as DropGame
	while not _drop_search.step():
		pass
	var plan: DropPlanner.Placement = _drop_search.best
	if plan != null:
		for i: int in DropGame.OFFSETS.size():
			if drop.rotation == plan.rotation or not drop.rotate(1):
				break
		var dir: int = signi(plan.column - drop.pivot.x)
		while drop.pivot.x != plan.column and drop.move(dir):
			pass
	drop.hard_drop()


## Swap mode: once the board is still, think for a while (searching one step
## per frame), then make the best swap. With no swap available, it waits for
## the next row. Think time is capped below the rise time, so even Easy keeps
## up in sudden death.
func _play_swap(delta: float) -> void:
	var swap_game: SwapGame = _game as SwapGame
	if not swap_game.can_swap():
		return
	if _swap_search == null:
		_swap_search = SwapPlanner.Search.new(swap_game.board, _swap_settings, rng)
	if not _swap_thinking:
		_swap_thinking = true
		var think: float = _swap_settings.think_sec * rng.randf_range(0.8, 1.2)
		_think_timer = minf(think, swap_game.rise_interval() * 0.6)
	_swap_search.step()
	_think_timer -= delta
	if _think_timer > 0.0:
		return
	while not _swap_search.step():
		pass
	var move: SwapPlanner.Move = _swap_search.best
	if move == null:
		return
	_swap_thinking = false
	_swap_search = null
	swap_game.try_swap(move.a, move.b)


func _send_snapshot() -> void:
	reply(GemBattle.Kind.BOARD, {"b": GemBoard.encode_cells(_game.cells_for_view()), "i": _game.incoming})


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
