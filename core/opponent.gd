class_name Opponent
extends Node
## The other side of a match: a remote player or a local bot. Mini games talk
## to it only through send_game() and the game_message signal, so a game works
## the same against either.

signal game_message(kind: int, data: Dictionary)
## The opponent went away (remote player disconnected).
signal left

const MAX_QUEUED: int = 256

var info: PlayerInfo = null
## Which match the messages belong to; stale messages from an earlier match are dropped.
var match_number: int = 0

var _attached: bool = false
var _queue: Array[Array] = []


## Sends a game-defined message to the opponent. Overridden by each kind of opponent.
func send_game(_kind: int, _data: Dictionary = {}) -> void:
	pass


func is_bot() -> bool:
	return false


## A new match is starting: forget anything from the last one, and hold
## incoming messages until the new game attaches (the other side's game may
## start a moment earlier and send first).
func begin_match(number: int) -> void:
	match_number = number
	_attached = false
	_queue.clear()


## Called by MiniGame once it's listening. Delivers anything held so far.
func attach() -> void:
	_attached = true
	var pending: Array[Array] = _queue
	_queue = []
	for item: Array in pending:
		game_message.emit(item[0], item[1])


func _deliver(kind: int, data: Dictionary) -> void:
	if _attached:
		game_message.emit(kind, data)
	elif _queue.size() < MAX_QUEUED:
		_queue.append([kind, data])
