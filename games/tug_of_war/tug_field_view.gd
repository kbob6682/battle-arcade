class_name TugFieldView
extends Control
## Draws the whole Tug of War field in code: this player's side, the glowing
## middle line, and the opponent's side from their snapshots, mirrored. Also
## the ghost of where the piece will land, flashes on cleared lines, and the
## cannon's fuse. Each piece type has its own colour and a small marker, for
## colour-blind players.
##
## Sideways (Cannon): your side on the left, pieces travel right. Upright
## (Classic, `upright`): your side on top, pieces fall down. Either way a
## side's depth d (0 at the line) and row r (TugBoard) map to a screen cell
## by screen_cell().

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

## Classic: your side on top, the line across the middle.
var upright: bool = false:
	set(value):
		upright = value
		queue_redraw()
## Cannon: how much of the fuse is left (0 to 1); below 0 hides the bar.
var fuse: float = -1.0

## The field's size: cells across a line, and both sides together.
var rows: int = TugBoard.ROWS
var total_width: int = TugBoard.TOTAL_WIDTH

var _my_width: int = TugBoard.START_WIDTH
## Depth-major cells (see TugBoard).
var _my_cells: PackedInt32Array = PackedInt32Array()
var _their_cells: PackedInt32Array = PackedInt32Array()
var _their_width: int = 0
var _ghost: Array[Vector2i] = []
## Cleared lines: [lines from the far edge of my side, age].
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


## Flash this player's lines at these depths (just before they clear).
func flash_mine(depths: Array[int]) -> void:
	for d: int in depths:
		_flashes.append([_my_width - 1 - d, 0.0])


## Where a cell is drawn: grid column and row on screen. mine says which side.
func screen_cell(mine: bool, d: int, r: int) -> Vector2i:
	var along: int = _my_width - 1 - d if mine else _my_width + d
	return Vector2i(r, along) if upright else Vector2i(along, r)


## Grid size on screen: columns and rows.
func grid_size() -> Vector2i:
	return Vector2i(rows, total_width) if upright else Vector2i(total_width, rows)


## The row (TugBoard r) under a point in this control, for aiming with the
## mouse. -1 if outside the field.
func row_at(local: Vector2) -> int:
	var cell: float = cell_size()
	if cell <= 0.0:
		return -1
	var at: Vector2 = (local - _origin()) / cell
	var r: int = floori(at.x if upright else at.y)
	return r if r >= 0 and r < rows else -1

func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


func cell_size() -> float:
	var grid: Vector2i = grid_size()
	return minf(size.x / grid.x, size.y / grid.y)


## Centre of the middle line, for effects.
func line_centre() -> Vector2:
	var along: Vector2 = Vector2(rows / 2.0, _my_width) if upright else Vector2(_my_width, rows / 2.0)
	return _origin() + along * cell_size()


func _origin() -> Vector2:
	return (size - Vector2(grid_size()) * cell_size()) / 2.0


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
	var grid: Vector2i = grid_size()
	# Backgrounds: my side runs from the far edge to the line.
	var my_extent: Vector2 = Vector2(rows, _my_width) if upright else Vector2(_my_width, rows)
	var their_offset: Vector2 = Vector2(0, _my_width) if upright else Vector2(_my_width, 0)
	draw_rect(Rect2(origin, my_extent * cell), MY_BACKGROUND)
	draw_rect(Rect2(origin + their_offset * cell, (Vector2(grid) - their_offset) * cell), THEIR_BACKGROUND)
	for x: int in range(1, grid.x):
		draw_line(origin + Vector2(x * cell, 0), origin + Vector2(x * cell, grid.y * cell), GRID_LINE)
	for i: int in mini(_my_cells.size(), _my_width * rows):
		var value: int = _my_cells[i]
		if value != TugBoard.EMPTY:
			@warning_ignore("integer_division")
			_draw_block(value, _cell_rect(origin, screen_cell(true, i / rows, i % rows)))
	for ghost_cell: Vector2i in _ghost:
		draw_rect(_cell_rect(origin, screen_cell(true, ghost_cell.x, ghost_cell.y)).grow(-cell * 0.1), GHOST_COLOUR, false, maxf(cell * 0.06, 1.5))
	# Theirs, mirrored. If a snapshot lags behind the line, only what fits on
	# their side is drawn.
	var their_room: int = total_width - _my_width
	for i: int in mini(_their_cells.size(), _their_width * rows):
		@warning_ignore("integer_division")
		var d: int = i / rows
		if d < their_room and _their_cells[i] != TugBoard.EMPTY:
			_draw_block(_their_cells[i], _cell_rect(origin, screen_cell(false, d, i % rows)))
	for flash: Array in _flashes:
		var t: float = flash[1] / FLASH_SEC
		var colour := Color(1, 1, 1, 0.85 * (1.0 - t))
		if upright:
			draw_rect(Rect2(origin + Vector2(0, flash[0] * cell), Vector2(rows * cell, cell)), colour)
		else:
			draw_rect(Rect2(origin + Vector2(flash[0] * cell, 0), Vector2(cell, rows * cell)), colour)
	_draw_line(origin, cell)
	if fuse >= 0.0:
		# The fuse burns down beside the back edge, from green to red.
		var bar := Rect2(origin + Vector2(-cell * 0.35, 0), Vector2(cell * 0.2, rows * cell))
		draw_rect(bar, Color(1, 1, 1, 0.08))
		var left: float = clampf(fuse, 0.0, 1.0)
		var burning := Rect2(bar.position + Vector2(0, bar.size.y * (1.0 - left)), Vector2(bar.size.x, bar.size.y * left))
		draw_rect(burning, Color(1.0 - left, 0.4 + 0.5 * left, 0.25))


## The middle line: a bright bar with a soft, pulsing glow.
func _draw_line(origin: Vector2, cell: float) -> void:
	var length: float = rows * cell
	var at: float = _my_width * cell
	var pulse: float = 0.5 + 0.5 * sin(_time * 4.0)
	for k: int in 4:
		var half: float = cell * (0.12 + 0.12 * k)
		var glow: Color = LINE_COLOUR
		glow.a = (0.22 - 0.05 * k) * (0.7 + 0.3 * pulse)
		draw_rect(_line_rect(origin, at, half, length), glow)
	draw_rect(_line_rect(origin, at, cell * 0.06, length), LINE_COLOUR)


func _line_rect(origin: Vector2, at: float, half: float, length: float) -> Rect2:
	if upright:
		return Rect2(origin.x, origin.y + at - half, length, half * 2.0)
	return Rect2(origin.x + at - half, origin.y, half * 2.0, length)


func _cell_rect(origin: Vector2, at: Vector2i) -> Rect2:
	var cell: float = cell_size()
	return Rect2(origin + Vector2(at) * cell, Vector2(cell, cell))


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
