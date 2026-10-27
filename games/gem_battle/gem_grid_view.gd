class_name GemGridView
extends Control
## Draws a grid of gems in code: the main board, the next-pair preview, and
## (later) the opponent's mini board. Each colour has its own shape so
## colour-blind players can tell them apart. Placeholder art for now.

const GEM_COLOURS: Array[Color] = [
	Color(0.92, 0.26, 0.26), # 1 red circle
	Color(0.25, 0.55, 0.95), # 2 blue square
	Color(0.3, 0.8, 0.35), # 3 green diamond
	Color(0.98, 0.8, 0.2), # 4 yellow triangle
	Color(0.7, 0.4, 0.92), # 5 purple star
]
const JUNK_COLOUR: Color = Color(0.5, 0.5, 0.53)
const BACKGROUND: Color = Color(0.07, 0.08, 0.12)
const GRID_LINE: Color = Color(1, 1, 1, 0.04)
const SHAKE_SEC: float = 0.25

@export var columns: int = GemBoard.WIDTH
@export var rows: int = GemBoard.HEIGHT
@export var draw_background: bool = true

var _cells: PackedInt32Array = PackedInt32Array()
## Current shake strength in pixels; dies away over SHAKE_SEC.
var _shake: float = 0.0
var _shake_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func show_cells(cells: PackedInt32Array) -> void:
	_cells = cells
	queue_redraw()


## Briefly shakes the drawn board (chains, junk landing).
func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


## Size of one cell in pixels, and where a cell's centre is (for effects).
func cell_size() -> float:
	return minf(size.x / columns, size.y / rows)


func cell_centre(index: int) -> Vector2:
	@warning_ignore("integer_division")
	return _origin() + (Vector2(index % columns, index / columns) + Vector2(0.5, 0.5)) * cell_size()


func _origin() -> Vector2:
	return (size - Vector2(columns, rows) * cell_size()) / 2.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = move_toward(_shake, 0.0, _shake * delta / SHAKE_SEC + delta)
		queue_redraw()


func _draw() -> void:
	var cell: float = cell_size()
	var origin: Vector2 = _origin()
	if _shake > 0.0:
		origin += Vector2(_shake_rng.randf_range(-_shake, _shake), _shake_rng.randf_range(-_shake, _shake))
	if draw_background:
		draw_rect(Rect2(origin, Vector2(columns, rows) * cell), BACKGROUND)
		for x: int in range(1, columns):
			draw_line(origin + Vector2(x * cell, 0), origin + Vector2(x * cell, rows * cell), GRID_LINE)
	for i: int in mini(_cells.size(), columns * rows):
		var value: int = _cells[i]
		if value == GemBoard.EMPTY:
			continue
		@warning_ignore("integer_division")
		var rect := Rect2(origin + Vector2(i % columns, i / columns) * cell, Vector2(cell, cell))
		_draw_gem(value, rect.grow(-cell * 0.08))


func _draw_gem(value: int, rect: Rect2) -> void:
	var c: Vector2 = rect.get_center()
	var r: float = rect.size.x / 2.0
	if value == GemBoard.JUNK:
		draw_rect(rect, JUNK_COLOUR)
		draw_rect(rect, JUNK_COLOUR.darkened(0.4), false, maxf(r * 0.12, 1.0))
		return
	var colour: Color = GEM_COLOURS[value - 1]
	match value:
		1:
			draw_circle(c, r, colour)
		2:
			draw_rect(rect.grow(-r * 0.08), colour)
		3:
			_polygon([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)], colour)
		4:
			_polygon([c + Vector2(0, -r), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8)], colour)
		_:
			var points: PackedVector2Array = PackedVector2Array()
			for k: int in 10:
				var radius: float = r if k % 2 == 0 else r * 0.45
				points.append(c + Vector2.from_angle(-PI / 2.0 + k * PI / 5.0) * radius)
			draw_colored_polygon(points, colour)
	# A small highlight so gems read as shiny rather than flat.
	draw_circle(c + Vector2(-r, -r) * 0.3, r * 0.15, Color(1, 1, 1, 0.5))


func _polygon(points: Array[Vector2], colour: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), colour)
