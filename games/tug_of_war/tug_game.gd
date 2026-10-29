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
##
## Two ways of placing pieces, same rules otherwise:
## - Travelling (Classic): the piece steps towards the line on a timer and is
##   steered on the way.
## - Cannon: the piece waits at the back edge to be aimed and turned, then
##   fire() shoots it to the line. A fuse fires it automatically.

signal changed
signal piece_spawned
## Columns at these depths are about to clear (depths before clearing, for
## effects). The side grows by count afterwards.
signal columns_cleared(count: int, depths: Array[int])
## This side's width changed (the line moved).
signal line_moved(width: int)
signal topped_out

## FALLING means the piece is in play (travelling, or loaded in the cannon);
## FLYING is a fired cannon piece on its way to the line.
enum Phase { NOT_STARTED, FALLING, FLYING, CLEARING, TOPPED }

## Pieces appear turned once, so they're tall rather than deep.
const SPAWN_ROTATION: int = 1
## Top row of a new piece's box on Classic's field (and Rope's lanes), so a
## tall piece is roughly centred. See spawn_row_for.
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
## Cannon: seconds before the fuse fires the piece, stepping down every
## SPEEDUP_EVERY_SEC like the travel speed: 10.0, 7.7, 5.9, 4.6, then 3.5
## from sudden death on.
const BASE_FUSE_SEC: float = 10.0
const SUDDEN_DEATH_FUSE_SEC: float = 3.5
## Cannon: a fired piece moves one step this often, and the next piece loads
## after this long.
const FLY_STEP_SEC: float = 0.02
const RELOAD_SEC: float = 0.25
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
## Held down: the piece travels fast (Classic).
var soft_drop: bool = false
## Cannon mode, on its bigger field: set before start().
var cannon: bool = false
## Seconds since start; drives the speed-up.
var elapsed: float = 0.0

## Seeded with the shared match seed and used only for the piece order, so
## both players (and a bot) get the same pieces.
var _pieces_rng: RandomNumberGenerator
var _bag: Array[int] = []
var _step_timer: float = 0.0
var _pause_timer: float = 0.0
## Cannon: seconds the current piece has been loaded.
var _fuse_timer: float = 0.0


## Top row of a new piece's box on a field this many rows tall.
static func spawn_row_for(rows: int) -> int:
	@warning_ignore("integer_division")
	return rows / 2 - 2


func start(pieces_rng: RandomNumberGenerator) -> void:
	_pieces_rng = pieces_rng
	if cannon:
		board = TugBoard.cannon_board()
	next_type = _take_from_bag()
	_spawn()


func tick(delta: float) -> void:
	if phase == Phase.NOT_STARTED or phase == Phase.TOPPED:
		return
	elapsed += delta
	match phase:
		Phase.FALLING when cannon:
			_fuse_timer += delta
			if _fuse_timer >= fuse_interval():
				fire()
		Phase.FLYING:
			_step_timer += delta
			while _step_timer >= FLY_STEP_SEC and phase == Phase.FLYING:
				_step_timer -= FLY_STEP_SEC
				if not _try_shift(Vector2i(-1, 0)):
					_lock()
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


func fuse_interval() -> float:
	var level: int = mini(int(elapsed / SPEEDUP_EVERY_SEC), SPEEDUP_STEPS)
	return BASE_FUSE_SEC * pow(SUDDEN_DEATH_FUSE_SEC / BASE_FUSE_SEC, float(level) / SPEEDUP_STEPS)


## Cannon: how much of the fuse is left, 1 (just loaded) to 0.
func fuse_left() -> float:
	if not cannon or phase != Phase.FALLING:
		return 0.0
	return clampf(1.0 - _fuse_timer / fuse_interval(), 0.0, 1.0)


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


## Classic: drops straight to the line. Cannon: fires.
func hard_drop() -> void:
	if phase != Phase.FALLING:
		return
	if cannon:
		fire()
		return
	while _try_shift(Vector2i(-1, 0)):
		pass
	_lock()


## Cannon: shoots the loaded piece at the line.
func fire() -> void:
	if phase != Phase.FALLING:
		return
	phase = Phase.FLYING
	_step_timer = 0.0
	changed.emit()


## Moves the piece towards row (for aiming with the mouse) until it gets
## there or something is in the way.
func aim_at(row: int) -> void:
	var dir: int = signi(row - pos.y)
	while pos.y != row and move(dir):
		pass


## The opponent cleared n columns: the line moves n steps into this side.
func push_line(n: int) -> void:
	if n <= 0 or phase == Phase.TOPPED or phase == Phase.NOT_STARTED:
		return
	var ok: bool = board.shrink(n)
	line_moved.emit(board.width)
	if ok and (phase == Phase.FALLING or phase == Phase.FLYING):
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
	if phase == Phase.FALLING or phase == Phase.FLYING:
		for cell: Vector2i in piece_cells():
			if board.in_bounds(cell.x, cell.y):
				values[cell.x * board.rows + cell.y] = piece_type
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
	_pause_timer = RELOAD_SEC if cannon else LAND_PAUSE_SEC
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
	_fuse_timer = 0.0
	# The piece's furthest-back cell starts at the back edge.
	var min_x: int = 99
	for offset: Vector2i in TugBoard.piece_offsets(piece_type, rotation):
		min_x = mini(min_x, offset.x)
	pos = Vector2i(board.width - 1 + min_x, spawn_row_for(board.rows))
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
