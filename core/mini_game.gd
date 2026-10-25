class_name MiniGame
extends Node
## Base for every mini game's root node. The match screen calls start_game();
## the game plays against `opponent` (remote player or bot, same messages) and
## calls finish() once with this player's outcome.

signal finished(outcome: Outcome, stats: Dictionary)

enum Outcome { WIN, LOSE, DRAW }

var opponent: Opponent = null
var local_player: PlayerInfo = null
var mode: String = ""
var is_host: bool = false
## Seeded with the shared match seed: use it for anything both players must
## agree on (piece order, target positions). Use a separate RNG for the rest.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _finished: bool = false


func start_game(match_seed: int, match_opponent: Opponent, match_mode: String, host: bool, player: PlayerInfo) -> void:
	rng.seed = match_seed
	opponent = match_opponent
	mode = match_mode
	is_host = host
	local_player = player
	opponent.game_message.connect(_on_opponent_message)
	_start()
	opponent.attach()


func _exit_tree() -> void:
	if opponent != null and opponent.game_message.is_connected(_on_opponent_message):
		opponent.game_message.disconnect(_on_opponent_message)


## Sends a game-defined message to the opponent.
func send(kind: int, data: Dictionary = {}) -> void:
	if opponent != null:
		opponent.send_game(kind, data)


## Ends the game for this player. Only the first call counts.
func finish(outcome: Outcome, stats: Dictionary = {}) -> void:
	if _finished:
		return
	_finished = true
	finished.emit(outcome, stats)


func is_finished() -> bool:
	return _finished


## Override: set up and start playing. rng is already seeded.
func _start() -> void:
	pass


## Override: handle a message from the opponent's game.
func _on_opponent_message(_kind: int, _data: Dictionary) -> void:
	pass
