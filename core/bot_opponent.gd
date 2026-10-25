class_name BotOpponent
extends Opponent
## Base for each mini game's bot. A bot plays its side through the same
## messages a remote player would send, delivered a frame later like network
## traffic, so the game can't tell the difference.

enum Difficulty { EASY, MEDIUM, HARD }

const DIFFICULTY_NAMES: Array[String] = ["Easy", "Medium", "Hard"]

var difficulty: Difficulty = Difficulty.MEDIUM
## The bot's own randomness (reaction times, mistakes). Separate from the
## shared match seed, which the bot also receives in start_match().
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


static func difficulty_name(value: int) -> String:
	return DIFFICULTY_NAMES[value]


func is_bot() -> bool:
	return true


## The player's game sent the bot a message.
func send_game(kind: int, data: Dictionary = {}) -> void:
	_on_player_message.call_deferred(kind, data.duplicate(true))


## The bot sends a message to the player's game.
func reply(kind: int, data: Dictionary = {}) -> void:
	_deliver.call_deferred(kind, data.duplicate(true))


## Called when the countdown ends and the player's game starts.
func start_match(_match_seed: int, _mode: String) -> void:
	pass


## Called when the match is over or abandoned. Stop timers here.
func stop_match() -> void:
	pass


func _on_player_message(_kind: int, _data: Dictionary) -> void:
	pass
