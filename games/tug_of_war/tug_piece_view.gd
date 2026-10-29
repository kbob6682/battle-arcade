class_name TugPieceView
extends Control
## Draws one Tug of War piece, centred, turned the way it appears on the
## field. For the next-piece preview. upright matches Classic's upright field
## (the piece is drawn with its axes swapped, as the field does).

var upright: bool = false
var _type: int = 0


func show_piece(type: int) -> void:
	_type = type
	queue_redraw()


func _draw() -> void:
	if _type < 1 or _type > TugBoard.PIECE_TYPES:
		return
	var offsets: Array[Vector2i] = TugBoard.piece_offsets(_type, TugGame.SPAWN_ROTATION)
	var low := Vector2i(99, 99)
	var high := Vector2i(-99, -99)
	if upright:
		var swapped: Array[Vector2i] = []
		for offset: Vector2i in offsets:
			swapped.append(Vector2i(offset.y, offset.x))
		offsets = swapped
	for offset: Vector2i in offsets:
		low = low.min(offset)
		high = high.max(offset)
	var span: Vector2 = Vector2(high - low + Vector2i.ONE)
	var cell: float = minf(size.x / 4.0, size.y / 4.0)
	var origin: Vector2 = (size - span * cell) / 2.0
	for offset: Vector2i in offsets:
		TugFieldView.draw_block(self, _type, Rect2(origin + Vector2(offset - low) * cell, Vector2(cell, cell)))
