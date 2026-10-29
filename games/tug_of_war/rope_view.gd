class_name RopeView
extends Control
## Draws Rope mode in code: ten lane ropes across the field with a knot each,
## your cannon on the left edge and the opponent's on the right, shots flying
## towards the middle, the reload bar, and flags on won lanes.

const MY_BACKGROUND: Color = Color(0.07, 0.09, 0.16)
const THEIR_BACKGROUND: Color = Color(0.14, 0.07, 0.09)
const ROPE_COLOUR: Color = Color(0.78, 0.66, 0.45)
const MIDDLE_COLOUR: Color = Color(1.0, 0.92, 0.45, 0.6)
const FLY_SEC: float = 0.25
## Knots are drawn at most this many cells from the middle.
const MAX_DRAWN: int = 8

var my_colour: Color = Color(0.4, 0.7, 1.0)
var their_colour: Color = Color(1.0, 0.45, 0.4)
## How far through reloading, 0 to 1; 1 is ready.
var reload: float = 1.0

var _knots: PackedInt32Array = PackedInt32Array()
## My cannon: piece type, rotation and top lane. Theirs from their snapshots
## (type 0 hides it).
var _mine: Vector3i = Vector3i.ZERO
var _theirs: Vector3i = Vector3i.ZERO
## Shots in the air: [pulls per lane, mine (bool), age].
var _shots: Array[Array] = []
var _time: float = 0.0


func show_knots(knots: PackedInt32Array) -> void:
	_knots = knots
	queue_redraw()


func show_my_cannon(type: int, turned: int, top: int) -> void:
	_mine = Vector3i(type, turned, top)
	queue_redraw()


func show_their_cannon(type: int, turned: int, top: int) -> void:
	_theirs = Vector3i(type, turned, top)
	queue_redraw()


## A shot leaves a cannon and flies to the middle.
func shoot(pulls: PackedInt32Array, mine: bool) -> void:
	_shots.append([pulls, mine, 0.0])


func cell_size() -> float:
	return minf(size.x / TugBoard.TOTAL_WIDTH, size.y / TugBoard.ROWS)


## The lane under a point in this control, or -1.
func lane_at(local: Vector2) -> int:
	var cell: float = cell_size()
	if cell <= 0.0:
		return -1
	var lane: int = floori((local.y - _origin().y) / cell)
	return lane if lane >= 0 and lane < RopeGame.LANES else -1


func middle() -> Vector2:
	return _origin() + Vector2(TugBoard.TOTAL_WIDTH / 2.0, TugBoard.ROWS / 2.0) * cell_size()


func _origin() -> Vector2:
	return (size - Vector2(TugBoard.TOTAL_WIDTH, TugBoard.ROWS) * cell_size()) / 2.0


func _process(delta: float) -> void:
	_time += delta
	for shot: Array in _shots:
		shot[2] += delta
	_shots = _shots.filter(func(shot: Array) -> bool: return shot[2] < FLY_SEC)
	queue_redraw()


func _draw() -> void:
	var cell: float = cell_size()
	var origin: Vector2 = _origin()
	var half: float = TugBoard.TOTAL_WIDTH / 2.0
	var lanes: int = RopeGame.LANES
	draw_rect(Rect2(origin, Vector2(half, lanes) * cell), MY_BACKGROUND)
	draw_rect(Rect2(origin + Vector2(half * cell, 0), Vector2(half, lanes) * cell), THEIR_BACKGROUND)
	# Win zones: a knot pulled this far is a won lane.
	var win_x: float = RopeGame.WIN_PULL * cell
	var centre_x: float = origin.x + half * cell
	for lane: int in mini(_knots.size(), lanes):
		var knot: int = _knots[lane]
		var y: float = origin.y + (lane + 0.5) * cell
		if absi(knot) >= RopeGame.WIN_PULL:
			var winner: Color = my_colour if knot > 0 else their_colour
			winner.a = 0.18
			draw_rect(Rect2(origin.x, y - cell * 0.5, TugBoard.TOTAL_WIDTH * cell, cell), winner)
		draw_line(Vector2(origin.x + cell, y), Vector2(origin.x + (TugBoard.TOTAL_WIDTH - 1) * cell, y), ROPE_COLOUR, maxf(cell * 0.08, 2.0))
		# Positive pulls the knot left, towards me.
		var shown: int = clampi(knot, -MAX_DRAWN, MAX_DRAWN)
		var knot_at := Vector2(centre_x - shown * cell, y)
		var colour: Color = Color.WHITE if knot == 0 else (my_colour if knot > 0 else their_colour)
		draw_circle(knot_at, cell * 0.32, colour)
		draw_circle(knot_at, cell * 0.32, colour.darkened(0.5), false, maxf(cell * 0.06, 1.5))
		if absi(knot) >= RopeGame.WIN_PULL:
			_draw_flag(knot_at + Vector2(0, -cell * 0.3), cell, colour)
	# The middle mark and the win lines.
	draw_line(Vector2(centre_x, origin.y), Vector2(centre_x, origin.y + lanes * cell), MIDDLE_COLOUR, maxf(cell * 0.06, 2.0))
	for side: float in [-1.0, 1.0]:
		var x: float = centre_x + side * win_x
		draw_dashed_line(Vector2(x, origin.y), Vector2(x, origin.y + lanes * cell), Color(1, 1, 1, 0.18), 1.5, cell * 0.25)
	_draw_cannon(origin, cell, _mine, true)
	_draw_cannon(origin, cell, _theirs, false)
	for shot: Array in _shots:
		var t: float = shot[2] / FLY_SEC
		var pulls: PackedInt32Array = shot[0]
		var from_x: float = origin.x + cell * 0.5 if shot[1] else origin.x + (TugBoard.TOTAL_WIDTH - 0.5) * cell
		var x: float = lerpf(from_x, centre_x, t)
		for lane: int in pulls.size():
			for k: int in pulls[lane]:
				var at := Vector2(x - (k * cell * 0.3 if shot[1] else -k * cell * 0.3), origin.y + (lane + 0.5) * cell)
				draw_circle(at, cell * 0.18, Color(1, 1, 1, 0.9 - 0.5 * t))
	# Reload bar beside my cannon.
	var bar := Rect2(origin + Vector2(-cell * 0.35, 0), Vector2(cell * 0.2, lanes * cell))
	draw_rect(bar, Color(1, 1, 1, 0.08))
	var ready: float = clampf(reload, 0.0, 1.0)
	draw_rect(Rect2(bar.position + Vector2(0, bar.size.y * (1.0 - ready)), Vector2(bar.size.x, bar.size.y * ready)), Color(0.3, 0.85, 0.4) if ready >= 1.0 else Color(0.6, 0.6, 0.65))


## The loaded piece at a back edge, x towards the middle (mirrored for theirs).
func _draw_cannon(origin: Vector2, cell: float, cannon: Vector3i, mine: bool) -> void:
	if cannon.x < 1 or cannon.x > TugBoard.PIECE_TYPES:
		return
	for offset: Vector2i in TugBoard.piece_offsets(cannon.x, cannon.y):
		var column: int = offset.x if mine else TugBoard.TOTAL_WIDTH - 1 - offset.x
		var rect := Rect2(origin + Vector2(column, cannon.z + offset.y) * cell, Vector2(cell, cell))
		TugFieldView.draw_block(self, cannon.x, rect)


func _draw_flag(base: Vector2, cell: float, colour: Color) -> void:
	var top: Vector2 = base + Vector2(0, -cell * 0.45)
	draw_line(base, top, Color.WHITE, maxf(cell * 0.05, 1.0))
	draw_colored_polygon(PackedVector2Array([top, top + Vector2(cell * 0.32, cell * 0.1), top + Vector2(0, cell * 0.2)]), colour)
