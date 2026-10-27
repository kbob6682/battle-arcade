class_name GemBattleBot
extends BotOpponent
## Placeholder Gem Battle bot (Step 2): plays a real Drop board with the same
## pairs as the player, but puts each pair in a random place, so it soon tops
## out. Proper Easy/Medium/Hard play comes in Step 4.

## How long the bot "thinks" before dropping each pair.
const THINK_SEC: float = 0.8

var _game: DropGame = null
var _playing: bool = false
var _think_timer: float = 0.0


func start_match(match_seed: int, _mode: String) -> void:
	var pieces_rng := RandomNumberGenerator.new()
	pieces_rng.seed = match_seed
	_game = DropGame.new()
	_game.piece_spawned.connect(func() -> void: _think_timer = THINK_SEC)
	_game.topped_out.connect(_on_topped_out)
	_playing = true
	_game.start(pieces_rng)


func stop_match() -> void:
	_playing = false


func _process(delta: float) -> void:
	if not _playing:
		return
	_game.tick(delta)
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
	reply(GemBattle.Kind.TOPPED)


func _on_player_message(kind: int, _data: Dictionary) -> void:
	if kind == GemBattle.Kind.TOPPED:
		stop_match()
