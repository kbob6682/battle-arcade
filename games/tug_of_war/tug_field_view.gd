class_name TugFieldView
extends Control
## Draws the whole Tug of War field in code: this player's side on the left
## (back edge at the left, travelling right), the glowing middle line, and the
## opponent's side on the right from their snapshots, mirrored. Also the ghost
## of where the piece will land, and flashes on cleared columns. Each piece
## type has its own colour and a small marker, for colour-blind players.

const PIECE_COLOURS: Array[Color] = [
	Color(0.3, 0.85, 0.95), # I
	Color(0.98, 0.85, 0.25), # O
	Color(0.72, 0.42, 0.95), # T
	Color(0.35, 0.82, 0.4), # S
	Color(0.92, 0.3, 0.3), # Z
	Color(0.3, 0.5, 0.95), # J
	Color(0.98, 0.6, 0.2), # L
]
const MY_BACKGROUND: Color = Color(0.07, 0.09, 0.16)
const THEIR_BACKGROUND: Color = Color(0.14, 0.07, 0.09)
const GRID_LINE: Color = Color(1, 1, 1, 0.04)
const LINE_COLOUR: Color = Color(1.0, 0.92, 0.45)
const GHOST_COLOUR: Color = Color(1, 1, 1, 0.35)
const FLASH_SEC: float = 0.35
const SHAKE_SEC: float = 0.25

var _my_width: int = TugBoard.START_WIDTH
## Depth-major cells (see TugBoard).
var _my_cells: PackedInt32Array = PackedInt32Array()
var _their_cells: PackedInt32Array = PackedInt32Array()
var _their_width: int = 0
var _ghost: Array[Vector2i] = []
## Cleared columns: [screen column, age].
var _flashes: Array[Array] = []
var _shake: float = 0.0
var _shake_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _time: float = 0.0


## This player's side, with the travelling piece drawn in, and its ghost.
func show_mine(width: int, cells: PackedInt32Array, ghost: Array[Vector2i]) -> void:
	_my_width = width
	_my_cells = cells
	_ghost = ghost
	queue_redraw()


## The opponent's side from their last snapshot.
func show_theirs(width: int, cells: PackedInt32Array) -> void:
	_their_width = width
	_their_cells = cells
	queue_redraw()


## Flash this player's columns at these depths (just before they clear).
func flash_mine(depths: Array[int]) -> void:
	for d: int in depths:
		_flashes.append([_my_width - 1 - d, 0.0])


func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


func cell_size() -> float:
	return minf(size.x / TugBoard.TOTAL_WIDTH, size.y / TugBoard.ROWS)


## Centre of the middle line, for effects.
func line_centre() -> Vector2:
	return _origin() + Vector2(_my_width, TugBoard.ROWS / 2.0) * cell_size()


func _origin() -> Vector2:
	return (size - Vector2(TugBoard.TOTAL_WIDTH, TugBoard.ROWS) * cell_size()) / 2.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	for flash: Array in _flashes:
		flash[1] += delta
	_flashes = _flashes.filter(func(flash: Array) -> bool: return flash[1] < FLASH_SEC)
	if _shake > 0.0:
		_shake = move_toward(_shake, 0.0, _shake * delta / SHAKE_SEC + delta)
	# The line glows, so keep redrawing.
	queue_redraw()


func _draw() -> void:
	var cell: float = cell_size()
	var origin: Vector2 = _origin()
	if _shake > 0.0:
		origin += Vector2(_shake_rng.randf_range(-_shake, _shake), _shake_rng.randf_range(-_shake, _shake))
	var rows: int = TugBoard.ROWS
	draw_rect(Rect2(origin, Vector2(_my_width, rows) * cell), MY_BACKGROUND)
	draw_rect(Rect2(origin + Vector2(_my_width * cell, 0), Vector2(TugBoard.TOTAL_WIDTH - _my_width, rows) * cell), THEIR_BACKGROUND)
	for x: int in range(1, TugBoard.TOTAL_WIDTH):
		draw_line(origin + Vector2(x * cell, 0), origin + Vector2(x * cell, rows * cell), GRID_LINE)
	# Mine: depth d is drawn at screen column width - 1 - d.
	for i: int in mini(_my_cells.size(), _my_width * rows):
		var value: int = _my_cells[i]
		if value != TugBoard.EMPTY:
			@warning_ignore("integer_division")
			_draw_block(value, _cell_rect(origin, _my_width - 1 - i / rows, i % rows))
	for ghost_cell: Vector2i in _ghost:
		draw_rect(_cell_rect(origin, _my_width - 1 - ghost_cell.x, ghost_cell.y).grow(-cell * 0.1), GHOST_COLOUR, false, maxf(cell * 0.06, 1.5))
	# Theirs, mirrored: depth d at screen column my width + d. If a snapshot
	# lags behind the line, only what fits on their side is drawn.
	var their_room: int = TugBoard.TOTAL_WIDTH - _my_width
	for i: int in mini(_their_cells.size(), _their_width * rows):
		@warning_ignore("integer_division")
		var d: int = i / rows
		if d < their_room and _their_cells[i] != TugBoard.EMPTY:
			_draw_block(_their_cells[i], _cell_rect(origin, _my_width + d, i % rows))
	for flash: Array in _flashes:
		var t: float = flash[1] / FLASH_SEC
		draw_rect(Rect2(origin + Vector2(flash[0] * cell, 0), Vector2(cell, rows * cell)), Color(1, 1, 1, 0.85 * (1.0 - t)))
	_draw_line(origin, cell)


## The middle line: a bright bar with a soft, pulsing glow.
func _draw_line(origin: Vector2, cell: float) -> void:
	var x: float = origin.x + _my_width * cell
	var height: float = TugBoard.ROWS * cell
	var pulse: float = 0.5 + 0.5 * sin(_time * 4.0)
	for k: int in 4:
		var half: float = cell * (0.12 + 0.12 * k)
		var glow: Color = LINE_COLOUR
		glow.a = (0.22 - 0.05 * k) * (0.7 + 0.3 * pulse)
		draw_rect(Rect2(x - half, origin.y, half * 2.0, height), glow)
	draw_rect(Rect2(x - cell * 0.06, origin.y, cell * 0.12, height), LINE_COLOUR)


func _cell_rect(origin: Vector2, column: int, row: int) -> Rect2:
	var cell: float = cell_size()
	return Rect2(origin + Vector2(column, row) * cell, Vector2(cell, cell))


func _draw_block(type: int, rect: Rect2) -> void:
	draw_block(self, type, rect)


## Shared with TugPieceView so blocks look the same everywhere.
static func draw_block(canvas: CanvasItem, type: int, rect: Rect2) -> void:
	var inner: Rect2 = rect.grow(-rect.size.x * 0.05)
	var colour: Color = PIECE_COLOURS[clampi(type, 1, PIECE_COLOURS.size()) - 1]
	canvas.draw_rect(inner, colour)
	canvas.draw_rect(inner, colour.darkened(0.35), false, maxf(rect.size.x * 0.06, 1.0))
	# A small marker per piece type.
	var c: Vector2 = rect.get_center()
	var r: float = rect.size.x * 0.16
	var mark: Color = colour.darkened(0.45)
	match type % 4:
		0:
			canvas.draw_circle(c, r, mark)
		1:
			canvas.draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), mark)
		2:
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 1.3), c + Vector2(r * 1.3, 0), c + Vector2(0, r * 1.3), c + Vector2(-r * 1.3, 0)]), mark)
		_:
			canvas.draw_line(c - Vector2(r, 0), c + Vector2(r, 0), mark, maxf(r * 0.6, 1.0))
	if type > 4:
		# Types 5 to 7 reuse markers 1 to 3, so they also get a corner dot.
		canvas.draw_circle(rect.position + rect.size * 0.22, r * 0.45, mark)
