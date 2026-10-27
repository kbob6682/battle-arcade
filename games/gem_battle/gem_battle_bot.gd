class_name GemBattleBot
extends BotOpponent
## Placeholder Gem Battle bot: plays a real Drop board with the same pairs as
## the player, but puts each pair in a random place, so it soon tops out.
## It sends and receives the same messages as a remote player (attacks, board
## snapshots, topping out). Proper Easy/Medium/Hard play comes in Step 4.

## How long the bot "thinks" before dropping each pair.
const THINK_SEC: float = 0.8

var _game: DropGame = null
var _playing: bool = false
var _think_timer: float = 0.0
var _start_msec: int = 0
var _board_dirty: bool = true
var _snapshot_timer: float = 0.0


func start_match(match_seed: int, _mode: String) -> void:
	var pieces_rng := RandomNumberGenerator.new()
	pieces_rng.seed = match_seed
	_game = DropGame.new()
	_game.piece_spawned.connect(func() -> void: _think_timer = THINK_SEC)
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
		reply(GemBattle.Kind.BOARD, {"b": GemBoard.encode_cells(_game.cells_with_piece()), "i": _game.incoming})
	if _game.phase != DropGame.Phase.FALLING:
		return
	_think_timer -= delta
	if _think_timer <= 0.0:
		_place_randomly()


func _place_randomly() -> void:
	for i: int in rng.randi_range(0, 3):
		_game.rotate(1)
	var dir: int = -1 if rng.randf() < 0.5 else 1
	for i: int in rng.randi_range(0, GemBoard.WIDTH):
		_game.move(dir)
	_game.hard_drop()


func _on_topped_out() -> void:
	_playing = false
	# Send the final board so the player sees how the bot lost.
	reply(GemBattle.Kind.BOARD, {"b": GemBoard.encode_cells(_game.cells_with_piece()), "i": _game.incoming})
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
