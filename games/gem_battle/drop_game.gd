class_name DropGame
extends RefCounted
## Drop mode for one board: the falling pair, its moves, landing, chains,
## attacks and incoming junk, and the speed-up. Plain logic driven by tick(),
## so the player's game and the bots run exactly the same rules, and tests can
## step it with fixed times.
##
## Junk: attacks from the opponent wait in `incoming`. When a pair lands, its
## chain first cancels incoming junk (blocking) and sends the rest as an
## attack; then up to MAX_JUNK_PER_LANDING of whatever is still incoming drops.
##
## The pair is a pivot gem plus a second gem on one side of it. Rotating moves
## the second gem round the pivot, nudging the pair off walls and stacks.

signal changed
signal piece_spawned
## A chain step cleared some gems. chain counts from 1.
signal chain_step(chain: int, cleared: int)
## The chain that started when the last pair landed is over.
signal chain_finished(chain: int)
## Junk to send to the opponent, after blocking.
signal attack_sent(amount: int)
signal incoming_changed(amount: int)
signal topped_out

enum Phase { NOT_STARTED, FALLING, RESOLVING, TOPPED }

## Where the second gem sits for each rotation: up, right, down, left.
const OFFSETS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## The pivot appears here, with the second gem above it.
const SPAWN: Vector2i = Vector2i(2, 1)
## Starting fall speed (seconds per row), and how it speeds up over time.
const BASE_FALL_SEC: float = 0.8
const SPEEDUP_EVERY_SEC: float = 30.0
const SPEEDUP_FACTOR: float = 0.85
const MIN_FALL_SEC: float = 0.08
const SOFT_DROP_SEC: float = 0.04
## Sudden death: after this long everything falls at least this fast.
const SUDDEN_DEATH_SEC: float = 180.0
const SUDDEN_DEATH_FALL_SEC: float = 0.15
## Most junk that drops after one landing (3 rows); the rest waits.
const MAX_JUNK_PER_LANDING: int = 18
## Pauses so players can see what happened: after landing, and between chain steps.
const LAND_PAUSE_SEC: float = 0.1
const CHAIN_STEP_SEC: float = 0.4
const JUNK_PAUSE_SEC: float = 0.3

var board: GemBoard = GemBoard.new()
var phase: Phase = Phase.NOT_STARTED
var pivot: Vector2i = SPAWN
var rotation: int = 0
## [pivot colour, second gem colour].
var piece_colours: Array[int] = [0, 0]
var next_colours: Array[int] = [0, 0]
## Held down: the pair falls fast.
var soft_drop: bool = false
## Seconds since start; drives the speed-up.
var elapsed: float = 0.0
## Junk the opponent has sent that hasn't dropped yet.
var incoming: int = 0

## Seeded with the shared match seed and used only for the pair sequence, so
## both players (and a bot) get the same pairs.
var _pieces_rng: RandomNumberGenerator
## Where junk lands. This player's own; it doesn't need to match the other side.
var _junk_rng: RandomNumberGenerator
var _fall_timer: float = 0.0
var _step_timer: float = 0.0
var _chain: int = 0
var _junk_dropped: bool = false


func start(pieces_rng: RandomNumberGenerator, junk_rng: RandomNumberGenerator = null) -> void:
	_pieces_rng = pieces_rng
	if junk_rng == null:
		junk_rng = RandomNumberGenerator.new()
		junk_rng.randomize()
	_junk_rng = junk_rng
	next_colours = _random_pair()
	_spawn()


func tick(delta: float) -> void:
	if phase == Phase.NOT_STARTED or phase == Phase.TOPPED:
		return
	elapsed += delta
	match phase:
		Phase.FALLING:
			_fall_timer += delta
			var interval: float = minf(SOFT_DROP_SEC, fall_interval()) if soft_drop else fall_interval()
			if _fall_timer >= interval:
				_fall_timer = 0.0
				if not _try_shift(Vector2i(0, 1)):
					_lock()
		Phase.RESOLVING:
			_step_timer -= delta
			if _step_timer <= 0.0:
				_resolve_next()


func fall_interval() -> float:
	var level: int = int(elapsed / SPEEDUP_EVERY_SEC)
	var interval: float = maxf(BASE_FALL_SEC * pow(SPEEDUP_FACTOR, level), MIN_FALL_SEC)
	if is_sudden_death():
		interval = minf(interval, SUDDEN_DEATH_FALL_SEC)
	return interval


func is_sudden_death() -> bool:
	return elapsed >= SUDDEN_DEATH_SEC


## The opponent attacked. The junk drops after this player's next landing.
func add_incoming(amount: int) -> void:
	if amount <= 0 or phase == Phase.TOPPED:
		return
	incoming += amount
	incoming_changed.emit(incoming)


## The pair's two cells: [pivot, second gem].
func piece_cells() -> Array[Vector2i]:
	return [pivot, pivot + OFFSETS[rotation]]


func move(dx: int) -> bool:
	return phase == Phase.FALLING and _try_shift(Vector2i(dx, 0))


## dir is 1 for clockwise, -1 for anticlockwise. If the turned pair doesn't
## fit, it's nudged one step away from whatever is in the way.
func rotate(dir: int) -> bool:
	if phase != Phase.FALLING:
		return false
	var new_rotation: int = posmod(rotation + dir, OFFSETS.size())
	var offset: Vector2i = OFFSETS[new_rotation]
	for candidate: Vector2i in [pivot, pivot - offset]:
		if _is_free(candidate) and _is_free(candidate + offset):
			pivot = candidate
			rotation = new_rotation
			changed.emit()
			return true
	return false


func hard_drop() -> void:
	if phase != Phase.FALLING:
		return
	while _try_shift(Vector2i(0, 1)):
		pass
	_lock()


## The board with the falling pair drawn in, for the view and snapshots.
func cells_with_piece() -> PackedInt32Array:
	var cells: PackedInt32Array = board.cells.duplicate()
	if phase == Phase.FALLING:
		var where: Array[Vector2i] = piece_cells()
		for i: int in where.size():
			cells[where[i].y * GemBoard.WIDTH + where[i].x] = piece_colours[i]
	return cells


func _try_shift(by: Vector2i) -> bool:
	for cell: Vector2i in piece_cells():
		if not _is_free(cell + by):
			return false
	pivot += by
	changed.emit()
	return true


func _is_free(cell: Vector2i) -> bool:
	return GemBoard.in_bounds(cell.x, cell.y) and board.get_cell(cell.x, cell.y) == GemBoard.EMPTY


func _lock() -> void:
	var where: Array[Vector2i] = piece_cells()
	for i: int in where.size():
		board.set_cell(where[i].x, where[i].y, piece_colours[i])
	# Each gem falls on its own into the lowest gap.
	board.apply_gravity()
	phase = Phase.RESOLVING
	_chain = 0
	_junk_dropped = false
	_step_timer = LAND_PAUSE_SEC
	changed.emit()


func _resolve_next() -> void:
	var cleared: int = board.resolve_step()
	if cleared > 0:
		_chain += 1
		_step_timer = CHAIN_STEP_SEC
		changed.emit()
		chain_step.emit(_chain, cleared)
		return
	if _chain > 0:
		_finish_chain()
	if incoming > 0 and not _junk_dropped:
		_drop_incoming()
		return
	_spawn()


func _finish_chain() -> void:
	var chain: int = _chain
	_chain = 0
	var result: Vector2i = GemBoard.cancel_incoming(incoming, GemBoard.attack_for_chain(chain))
	if result.x != incoming:
		incoming = result.x
		incoming_changed.emit(incoming)
	chain_finished.emit(chain)
	if result.y > 0:
		attack_sent.emit(result.y)


func _drop_incoming() -> void:
	_junk_dropped = true
	var amount: int = mini(incoming, MAX_JUNK_PER_LANDING)
	incoming -= amount
	board.drop_junk(amount, _junk_rng)
	_step_timer = JUNK_PAUSE_SEC
	changed.emit()
	incoming_changed.emit(incoming)


func _spawn() -> void:
	piece_colours = next_colours
	next_colours = _random_pair()
	pivot = SPAWN
	rotation = 0
	_fall_timer = 0.0
	for cell: Vector2i in piece_cells():
		if not _is_free(cell):
			phase = Phase.TOPPED
			changed.emit()
			topped_out.emit()
			return
	phase = Phase.FALLING
	changed.emit()
	piece_spawned.emit()


func _random_pair() -> Array[int]:
	return [_pieces_rng.randi_range(1, GemBoard.COLOURS), _pieces_rng.randi_range(1, GemBoard.COLOURS)]
