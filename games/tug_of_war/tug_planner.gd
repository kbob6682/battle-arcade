class_name TugPlanner
extends RefCounted
## Decides where a Tug of War bot puts each piece. It tries every rotation and
## row on a copy of its side (column clears included), scores each result, and
## picks the best. Hard also tries the next piece on top of its best few
## options. Plain logic, so it can be tested headlessly.


## How a bot level plays.
class Settings:
	## Seconds to "think" before moving each piece (capped when pieces move fast).
	var think_sec: float = 1.0
	## Also try the next piece (Hard).
	var lookahead: bool = false
	## Chance of a slip-up: one of the MISTAKE_POOL best places at random
	## instead of the best (a random place anywhere wrecks the side too fast).
	var mistake_chance: float = 0.0

	func _init(think: float, look: bool, mistakes: float) -> void:
		think_sec = think
		lookahead = look
		mistake_chance = mistakes


## Where to put a piece: its rotation and the row of its box's top.
class Placement:
	var rotation: int = 0
	var row: int = 0
	## The side after the piece landed and any columns cleared.
	var board: TugBoard = null
	var cleared: int = 0
	var score: float = 0.0


## Score weights. Clearing columns (which moves the line) matters most; gaps
## behind blocks are bad, so are deep and bumpy stacks, and very bad near the
## back edge where new pieces appear.
const CLEAR_WEIGHT: float = 9.0
const HOLE_WEIGHT: float = 3.5
const DEPTH_WEIGHT: float = 0.45
const BUMP_WEIGHT: float = 0.25
## Stacks within this many columns of the back edge are in danger.
const DANGER_MARGIN: int = 4
const DANGER_WEIGHT: float = 30.0
const TOPPED_SCORE: float = -1000000.0
## How much the next piece's clears count, compared with this one's.
const LOOKAHEAD_DISCOUNT: float = 0.9
## Hard tries the next piece only on top of this many of its best options.
const LOOKAHEAD_WIDTH: int = 6
## A slip-up picks from this many of the best places.
const MISTAKE_POOL: int = 6


static func settings_for(difficulty: BotOpponent.Difficulty) -> Settings:
	match difficulty:
		BotOpponent.Difficulty.EASY:
			return Settings.new(1.6, false, 0.3)
		BotOpponent.Difficulty.HARD:
			return Settings.new(0.35, true, 0.0)
	return Settings.new(0.85, false, 0.07)


## A decision that can be spread over several frames: step() tries the next
## piece on one more option per frame. best is usable at any time (null if
## nothing fits); done says it's final.
class Search:
	var done: bool = false
	var best: Placement = null
	var _options: Array[Placement] = []
	var _next_type: int = 0
	var _index: int = 0
	var _best_score: float = -INF

	func _init(board: TugBoard, type: int, next_type: int, settings: Settings, rng: RandomNumberGenerator) -> void:
		var options: Array[Placement] = TugPlanner.placements(board, type)
		done = true
		if options.is_empty():
			return
		var slip: bool = rng.randf() < settings.mistake_chance
		for option: Placement in options:
			option.score = TugPlanner.evaluate(option)
		options.sort_custom(func(a: Placement, b: Placement) -> bool: return a.score > b.score)
		best = options[0]
		if slip:
			best = options[rng.randi_range(0, mini(TugPlanner.MISTAKE_POOL, options.size()) - 1)]
			return
		if settings.lookahead:
			_options = options.slice(0, TugPlanner.LOOKAHEAD_WIDTH)
			_next_type = next_type
			done = false

	## Tries the next piece on top of one more option. Returns true when finished.
	func step() -> bool:
		if done:
			return true
		var option: Placement = _options[_index]
		_index += 1
		var follow_up_score: float = TugPlanner.TOPPED_SCORE
		for follow_up: Placement in TugPlanner.placements(option.board, _next_type):
			follow_up_score = maxf(follow_up_score, TugPlanner.evaluate(follow_up))
		var total: float = option.cleared * TugPlanner.CLEAR_WEIGHT + follow_up_score * TugPlanner.LOOKAHEAD_DISCOUNT
		if total > _best_score:
			_best_score = total
			best = option
		done = _index >= _options.size()
		return done


## The placement to play, worked out all at once, or null if nothing fits.
static func choose(board: TugBoard, type: int, next_type: int, settings: Settings, rng: RandomNumberGenerator) -> Placement:
	var search := Search.new(board, type, next_type, settings, rng)
	while not search.step():
		pass
	return search.best


## Every rotation and row where the piece fits at the back edge, each played
## out on a copy of the side.
static func placements(board: TugBoard, type: int) -> Array[Placement]:
	var result: Array[Placement] = []
	for rotation: int in 4:
		var offsets: Array[Vector2i] = TugBoard.piece_offsets(type, rotation)
		var min_x: int = 99
		for offset: Vector2i in offsets:
			min_x = mini(min_x, offset.x)
		for row: int in range(-3, board.rows):
			var pos := Vector2i(board.width - 1 + min_x, row)
			if not board.fits(TugBoard.piece_cells(type, rotation, pos)):
				continue
			while board.fits(TugBoard.piece_cells(type, rotation, pos + Vector2i(-1, 0))):
				pos.x -= 1
			var placement := Placement.new()
			placement.rotation = rotation
			placement.row = row
			placement.board = board.copy()
			for cell: Vector2i in TugBoard.piece_cells(type, rotation, pos):
				placement.board.set_cell(cell.x, cell.y, type)
			var full: Array[int] = placement.board.full_columns()
			placement.cleared = full.size()
			if not full.is_empty():
				placement.board.clear_columns(full)
				placement.board.grow(full.size())
			result.append(placement)
	return result


static func evaluate(placement: Placement) -> float:
	var b: TugBoard = placement.board
	# The next piece appears in the middle rows at the back edge.
	var spawn_row: int = TugGame.spawn_row_for(b.rows)
	for r: int in range(spawn_row, spawn_row + 4):
		for d: int in range(maxi(b.width - 2, 0), b.width):
			if b.get_cell(d, r) != TugBoard.EMPTY:
				return TOPPED_SCORE
	var score: float = placement.cleared * CLEAR_WEIGHT
	var previous: int = -1
	for r: int in b.rows:
		var depth: int = b.row_depth(r)
		score -= depth * DEPTH_WEIGHT
		for d: int in depth:
			if b.get_cell(d, r) == TugBoard.EMPTY:
				score -= HOLE_WEIGHT
		if previous >= 0:
			score -= absi(depth - previous) * BUMP_WEIGHT
		previous = depth
		if depth > b.width - DANGER_MARGIN:
			score -= (depth - (b.width - DANGER_MARGIN)) * DANGER_WEIGHT
	return score
