class_name RopeGame
extends RefCounted
## Rope mode for one player: ten lanes, each a rope with a knot. Both players
## fire pieces from a cannon on their back edge; every block that lands in a
## lane pulls that lane's knot one step towards the shooter. A flat piece
## pulls one lane hard, a tall one spreads over several. After MATCH_SEC the
## player with more lanes leaning their way wins (then total pull, then a draw).
##
## Agreement: knots are just sums of pulls, so the order shots arrive in
## doesn't matter. Each player fires until their own clock runs out, then
## says they're done; once both are done, both have seen every shot and
## work out the same result (see result_for).
##
## knots[lane] is from this player's side: positive leans towards me.

signal changed
## I fired: pulls per lane, for the message to the opponent.
signal fired(pulls: PackedInt32Array)
## My clock ran out; no more shots from me.
signal time_up

enum Phase { NOT_STARTED, AIMING, RELOADING, DONE }

const LANES: int = TugBoard.ROWS
## A knot this far towards a player wins the lane (it shows a flag).
const WIN_PULL: int = 5
const MATCH_SEC: float = 120.0
## Seconds between shots, quicker every 30 s: 1.2, 1.0, 0.85, then 0.7 for
## the final 30 s.
const BASE_RELOAD_SEC: float = 1.2
const FINAL_RELOAD_SEC: float = 0.7
const SPEEDUP_EVERY_SEC: float = 30.0
const SPEEDUP_STEPS: int = 3
const FINAL_SEC: float = SPEEDUP_EVERY_SEC * SPEEDUP_STEPS

var phase: Phase = Phase.NOT_STARTED
var knots: PackedInt32Array = PackedInt32Array()
var piece_type: int = 0
var rotation: int = TugGame.SPAWN_ROTATION
## The top lane of the piece's box.
var row: int = TugGame.SPAWN_ROW
var next_type: int = 0
var elapsed: float = 0.0

## Shared match seed: the piece order, the same for both players.
var _pieces_rng: RandomNumberGenerator
var _bag: Array[int] = []
var _reload_timer: float = 0.0


## Who won from one player's side, given the final knots (positive = mine).
static func result_for(final_knots: PackedInt32Array) -> MiniGame.Outcome:
	var mine: int = 0
	var theirs: int = 0
	var total: int = 0
	for knot: int in final_knots:
		total += knot
		if knot > 0:
			mine += 1
		elif knot < 0:
			theirs += 1
	if mine != theirs:
		return MiniGame.Outcome.WIN if mine > theirs else MiniGame.Outcome.LOSE
	if total != 0:
		return MiniGame.Outcome.WIN if total > 0 else MiniGame.Outcome.LOSE
	return MiniGame.Outcome.DRAW


## Pulls per lane for a piece aimed with its box's top at row.
static func pulls_for(type: int, turned: int, top: int) -> PackedInt32Array:
	var pulls: PackedInt32Array = PackedInt32Array()
	pulls.resize(LANES)
	for offset: Vector2i in TugBoard.piece_offsets(type, turned):
		var lane: int = top + offset.y
		if lane >= 0 and lane < LANES:
			pulls[lane] += 1
	return pulls


## Whether every block of the piece is in a lane.
static func fits(type: int, turned: int, top: int) -> bool:
	for offset: Vector2i in TugBoard.piece_offsets(type, turned):
		var lane: int = top + offset.y
		if lane < 0 or lane >= LANES:
			return false
	return true


func start(pieces_rng: RandomNumberGenerator) -> void:
	_pieces_rng = pieces_rng
	knots.resize(LANES)
	next_type = _take_from_bag()
	_load()


func tick(delta: float) -> void:
	if phase == Phase.NOT_STARTED or phase == Phase.DONE:
		return
	elapsed += delta
	if elapsed >= MATCH_SEC:
		phase = Phase.DONE
		changed.emit()
		time_up.emit()
		return
	if phase == Phase.RELOADING:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_load()


func reload_interval() -> float:
	var level: int = mini(int(elapsed / SPEEDUP_EVERY_SEC), SPEEDUP_STEPS)
	return BASE_RELOAD_SEC * pow(FINAL_RELOAD_SEC / BASE_RELOAD_SEC, float(level) / SPEEDUP_STEPS)


func is_final_stretch() -> bool:
	return elapsed >= FINAL_SEC


func time_left() -> float:
	return maxf(MATCH_SEC - elapsed, 0.0)


func is_done() -> bool:
	return phase == Phase.DONE


## Lanes leaning towards me and towards them.
func lanes_mine() -> int:
	return _count(func(knot: int) -> bool: return knot > 0)


func lanes_theirs() -> int:
	return _count(func(knot: int) -> bool: return knot < 0)


## Moves the aim up (-1) or down (1). Works while reloading too.
func move(dr: int) -> bool:
	if phase == Phase.DONE or not fits(piece_type, rotation, row + dr):
		return false
	row += dr
	changed.emit()
	return true


func aim_at(lane: int) -> void:
	var dir: int = signi(lane - row)
	while row != lane and move(dir):
		pass


## Turns the piece; nudged up or down if it would stick out of the lanes.
func rotate(dir: int) -> bool:
	if phase == Phase.DONE:
		return false
	var turned: int = posmod(rotation + dir, 4)
	for nudge: int in [0, -1, 1, -2, 2, -3, 3]:
		if fits(piece_type, turned, row + nudge):
			rotation = turned
			row += nudge
			changed.emit()
			return true
	return false


func fire() -> bool:
	if phase != Phase.AIMING:
		return false
	var pulls: PackedInt32Array = pulls_for(piece_type, rotation, row)
	for lane: int in LANES:
		knots[lane] += pulls[lane]
	phase = Phase.RELOADING
	_reload_timer = reload_interval()
	changed.emit()
	fired.emit(pulls)
	return true


## The opponent's shot: pulls towards them.
func apply_their_pulls(pulls: PackedInt32Array) -> void:
	for lane: int in mini(pulls.size(), LANES):
		knots[lane] -= pulls[lane]
	changed.emit()


## Reloading: how far through, 0 to 1 (1 when ready).
func reload_progress() -> float:
	if phase != Phase.RELOADING:
		return 1.0
	return clampf(1.0 - _reload_timer / reload_interval(), 0.0, 1.0)


func _load() -> void:
	piece_type = next_type
	next_type = _take_from_bag()
	rotation = TugGame.SPAWN_ROTATION
	# Keep the aim where it was, nudged if this piece would stick out.
	for nudge: int in [0, -1, 1, -2, 2, -3, 3]:
		if fits(piece_type, rotation, row + nudge):
			row += nudge
			break
	phase = Phase.AIMING
	changed.emit()


func _count(test: Callable) -> int:
	var count: int = 0
	for knot: int in knots:
		if test.call(knot):
			count += 1
	return count


## Shuffled bags of all seven pieces (same order as the other modes).
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
