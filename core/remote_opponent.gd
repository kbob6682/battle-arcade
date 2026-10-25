class_name RemoteOpponent
extends Opponent
## The player on the other computer, reached through the Net autoload.


func _ready() -> void:
	Net.message_received.connect(_on_net_message)
	Net.disconnected.connect(_on_net_disconnected)


func send_game(kind: int, data: Dictionary = {}) -> void:
	Net.send_message(Messages.Type.GAME, {"n": match_number, "k": kind, "d": data})


func _on_net_message(type: int, payload: Dictionary) -> void:
	if type != Messages.Type.GAME:
		return
	var number: Variant = payload.get("n")
	var kind: Variant = payload.get("k")
	var data: Variant = payload.get("d")
	if typeof(number) != TYPE_INT or typeof(kind) != TYPE_INT or typeof(data) != TYPE_DICTIONARY:
		return
	if number != match_number:
		return
	_deliver(kind, data)


func _on_net_disconnected(_reason: String) -> void:
	left.emit()
