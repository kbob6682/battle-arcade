class_name TugGame
extends RefCounted
## One player's Tug of War side in play: the travelling piece, its moves,
## landing, column clears, the middle line moving, and the speed-up. Plain
## logic driven by tick(), so the player's game and the bots run exactly the
## same rules, and tests can step it with fixed times.
##
## The line: clearing n columns moves the line n steps into the opponent's
## side (this side grows, columns_cleared tells the game to send it). When the
## opponent clears, push_line() shrinks this side, pushing the stack back; a
## block pushed off the back, or a new piece with no room, tops out.

signal changed
signal piece_spawned
## Columns at these depths are about to clear (depths before clearing, for
## effects). The side grows by count afterwards.
signal columns_cleared(count: int, depths: Array[int])
## This side's width changed (the line moved).
signal line_moved(width: int)
signal topped_out

enum Phase { NOT_STARTED, FALLING, CLEARING, TOPPED }

## Pieces appear turned once, so they're tall rather than deep.
const SPAWN_ROTATION: int = 1
## Top row of a new piece's box, so a tall piece is roughly centred.
const SPAWN_ROW: int = 3
## Seconds per step towards the line. Steps up every SPEEDUP_EVERY_SEC by the
## same factor, reaching the sudden-death speed after SPEEDUP_STEPS (3:00):
## 0.7, 0.47, 0.32, 0.21, then 0.14.
const BASE_STEP_SEC: float = 0.7
const SPEEDUP_EVERY_SEC: float = 45.0
const SPEEDUP_STEPS: int = 4
const SUDDEN_DEATH_SEC: float = SPEEDUP_EVERY_SEC * SPEEDUP_STEPS
const SUDDEN_DEATH_STEP_SEC: float = 0.14
const SOFT_DROP_SEC: float = 0.035
## Pauses so players can see what happened.
const LAND_PAUSE_SEC: float = 0.08
const CLEAR_PAUSE_SEC: float = 0.3
## Where a turned piece may be nudged if it doesn't fit: up, down, towards
## the line (off the back edge), two up, two down, then back from the line.
const KICKS: Array[Vector2i] = [
	Vector2i.ZERO, Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-2, 0),
	Vector2i(0, -2), Vector2i(0, 2), Vector2i(1, 0),
]

var board: TugBoard = TugBoard.new()
var phase: Phase = Phase.NOT_STARTED
var piece_type: int = 0
var rotation: int = 0
## The piece box's corner (see TugBoard.piece_cells).
var pos: Vector2i = Vector2i.ZERO
var next_type: int = 0
## Held down: the piece travels fast.
var soft_drop: bool = false
## Seconds since start; drives the speed-up.
var elapsed: float = 0.0

## Seeded with the shared match seed and used only for the piece order, so
## both players (and a bot) get the same pieces.
var _pieces_rng: RandomNumberGenerator
var _bag: Array[int] = []
var _step_timer: float = 0.0
var _pause_timer: float = 0.0


func start(pieces_rng: RandomNumberGenerator) -> void:
	_pieces_rng = pieces_rng
	next_type = _take_from_bag()
	_spawn()


func tick(delta: float) -> void:
	if phase == Phase.NOT_STARTED or phase == Phase.TOPPED:
		return
	elapsed += delta
	match phase:
		Phase.FALLING:
			_step_timer += delta
			var interval: float = minf(SOFT_DROP_SEC, step_interval()) if soft_drop else step_interval()
			if _step_timer >= interval:
				_step_timer = 0.0
				if not _try_shift(Vector2i(-1, 0)):
					_lock()
		Phase.CLEARING:
			_pause_timer -= delta
			if _pause_timer <= 0.0:
				_spawn()


func step_interval() -> float:
	var level: int = mini(int(elapsed / SPEEDUP_EVERY_SEC), SPEEDUP_STEPS)
	return BASE_STEP_SEC * pow(SUDDEN_DEATH_STEP_SEC / BASE_STEP_SEC, float(level) / SPEEDUP_STEPS)


func is_sudden_death() -> bool:
	return elapsed >= SUDDEN_DEATH_SEC


func is_topped() -> bool:
	return phase == Phase.TOPPED


func piece_cells() -> Array[Vector2i]:
	return TugBoard.piece_cells(piece_type, rotation, pos)


## Where the piece would land with a hard drop (for the ghost outline).
func landing_cells() -> Array[Vector2i]:
	var landing: Vector2i = pos
	while board.fits(TugBoard.piece_cells(piece_type, rotation, landing + Vector2i(-1, 0))):
		landing.x -= 1
	return TugBoard.piece_cells(piece_type, rotation, landing)


## Moves the piece up (-1) or down (1).
func move(dr: int) -> bool:
	return phase == Phase.FALLING and _try_shift(Vector2i(0, dr))


## dir is 1 for clockwise, -1 for anticlockwise. A turned piece that doesn't
## fit is nudged (KICKS).
func rotate(dir: int) -> bool:
	if phase != Phase.FALLING:
		return false
	var new_rotation: int = posmod(rotation + dir, 4)
	for kick: Vector2i in KICKS:
		if board.fits(TugBoard.piece_cells(piece_type, new_rotation, pos + kick)):
			rotation = new_rotation
			pos += kick
			changed.emit()
			return true
	return false


func hard_drop() -> void:
	if phase != Phase.FALLING:
		return
	while _try_shift(Vector2i(-1, 0)):
		pass
	_lock()


## The opponent cleared n columns: the line moves n steps into this side.
func push_line(n: int) -> void:
	if n <= 0 or phase == Phase.TOPPED or phase == Phase.NOT_STARTED:
		return
	var ok: bool = board.shrink(n)
	line_moved.emit(board.width)
	if ok and phase == Phase.FALLING:
		# The piece moves with the line; if it's now past the back edge, it
		# slides towards the line until it fits.
		while not board.fits(piece_cells()):
			var off_back: bool = false
			for cell: Vector2i in piece_cells():
				if cell.x >= board.width:
					off_back = true
			if not off_back:
				ok = false
				break
			pos.x -= 1
	if not ok:
		_top_out()
		return
	changed.emit()


## The board with the travelling piece drawn in, for the view and snapshots.
func cells_with_piece() -> PackedInt32Array:
	var values: PackedInt32Array = board.cells.duplicate()
	if phase == Phase.FALLING:
		for cell: Vector2i in piece_cells():
			if board.in_bounds(cell.x, cell.y):
				values[cell.x * TugBoard.ROWS + cell.y] = piece_type
	return values


func _try_shift(by: Vector2i) -> bool:
	if not board.fits(TugBoard.piece_cells(piece_type, rotation, pos + by)):
		return false
	pos += by
	changed.emit()
	return true


func _lock() -> void:
	for cell: Vector2i in piece_cells():
		board.set_cell(cell.x, cell.y, piece_type)
	phase = Phase.CLEARING
	_pause_timer = LAND_PAUSE_SEC
	var full: Array[int] = board.full_columns()
	if not full.is_empty():
		columns_cleared.emit(full.size(), full)
		board.clear_columns(full)
		board.grow(full.size())
		line_moved.emit(board.width)
		_pause_timer = CLEAR_PAUSE_SEC
	changed.emit()


func _spawn() -> void:
	piece_type = next_type
	next_type = _take_from_bag()
	rotation = SPAWN_ROTATION
	_step_timer = 0.0
	# The piece's furthest-back cell starts at the back edge.
	var min_x: int = 99
	for offset: Vector2i in TugBoard.piece_offsets(piece_type, rotation):
		min_x = mini(min_x, offset.x)
	pos = Vector2i(board.width - 1 + min_x, SPAWN_ROW)
	if not board.fits(piece_cells()):
		_top_out()
		return
	phase = Phase.FALLING
	changed.emit()
	piece_spawned.emit()


func _top_out() -> void:
	phase = Phase.TOPPED
	changed.emit()
	topped_out.emit()


## Shuffled bags of all seven pieces, so no piece is missing for long.
func _take_from_bag() -> int:
	if _bag.is_empty():
		for type: int in range(1, TugBoard.PIECE_TYPES + 1):
			_bag.append(type)
		for i: int in range(_bag.size() - 1, 0, -1):
			var j: int = _pieces_rng.randi_range(0, i)
			var held: int = _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = held
	return _bag.pop_back()
