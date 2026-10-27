class_name DropPlanner
extends RefCounted
## Decides where a Drop mode bot puts each pair. It tries every column and
## rotation on a copy of the board (chains included), scores each result,
## and picks the best. Hard also tries the known next pair on top of its best
## few options, so it can set up chains on purpose. Plain logic, so it can be
## tested headlessly.


## How a bot level plays.
class Settings:
	## Seconds to "think" before moving each pair (capped when pieces fall fast).
	var think_sec: float = 1.0
	## Also try the next pair (Hard).
	var lookahead: bool = false
	## Chance of putting a pair somewhere random instead.
	var mistake_chance: float = 0.0

	func _init(think: float, look: bool, mistakes: float) -> void:
		think_sec = think
		lookahead = look
		mistake_chance = mistakes


## Where to put a pair: the pivot's column and the rotation (DropGame.OFFSETS).
class Placement:
	var column: int = 0
	var rotation: int = 0
	## The board after the pair landed and any chain finished.
	var board: GemBoard = null
	var chain: int = 0
	var attack: int = 0
	var score: float = 0.0


## Score weights. Junk sent matters most; then gems of a colour touching
## (half-made matches); tall stacks are bad, and very bad near the spawn.
const ATTACK_WEIGHT: float = 10.0
const TOUCHING_WEIGHT: float = 1.5
const HEIGHT_WEIGHT: float = 0.08
const DANGER_HEIGHT: int = GemBoard.HEIGHT - 4
const DANGER_WEIGHT: float = 40.0
const TOPPED_SCORE: float = -1000000.0
## How much a junk sent with the next pair counts, compared with this one.
const LOOKAHEAD_DISCOUNT: float = 0.9
## Hard tries the next pair only on top of this many of its best options.
const LOOKAHEAD_WIDTH: int = 6


static func settings_for(difficulty: BotOpponent.Difficulty) -> Settings:
	match difficulty:
		BotOpponent.Difficulty.EASY:
			return Settings.new(2.0, false, 0.3)
		BotOpponent.Difficulty.HARD:
			return Settings.new(0.4, true, 0.0)
	return Settings.new(1.0, false, 0.08)


## A decision that can be spread over several frames: the look-ahead is the
## slow part (about 50 ms in one go), so step() does one option per frame and
## the game never stutters. best is usable at any time; done says it's final.
class Search:
	var done: bool = false
	## null only if no placement fits at all.
	var best: Placement = null
	var _options: Array[Placement] = []
	var _next_colours: Array[int] = []
	var _index: int = 0
	var _best_score: float = -INF

	func _init(board: GemBoard, colours: Array[int], next_colours: Array[int], settings: Settings, rng: RandomNumberGenerator) -> void:
		var options: Array[Placement] = DropPlanner.placements(board, colours)
		done = true
		if options.is_empty():
			return
		if rng.randf() < settings.mistake_chance:
			best = options[rng.randi_range(0, options.size() - 1)]
			return
		for option: Placement in options:
			option.score = DropPlanner.evaluate(option)
		options.sort_custom(func(a: Placement, b: Placement) -> bool: return a.score > b.score)
		best = options[0]
		if settings.lookahead:
			_options = options.slice(0, DropPlanner.LOOKAHEAD_WIDTH)
			_next_colours = next_colours
			done = false

	## Tries the next pair on top of one more option. Returns true when finished.
	func step() -> bool:
		if done:
			return true
		var option: Placement = _options[_index]
		_index += 1
		var follow_up_score: float = DropPlanner.TOPPED_SCORE
		for follow_up: Placement in DropPlanner.placements(option.board, _next_colours):
			follow_up_score = maxf(follow_up_score, DropPlanner.evaluate(follow_up))
		var total: float = option.attack * DropPlanner.ATTACK_WEIGHT + follow_up_score * DropPlanner.LOOKAHEAD_DISCOUNT
		if total > _best_score:
			_best_score = total
			best = option
		done = _index >= _options.size()
		return done


## The placement to play, worked out all at once, or null if nothing fits.
static func choose(board: GemBoard, colours: Array[int], next_colours: Array[int], settings: Settings, rng: RandomNumberGenerator) -> Placement:
	var search := Search.new(board, colours, next_colours, settings, rng)
	while not search.step():
		pass
	return search.best


## Every place the pair fits, each played out on a copy of the board.
static func placements(board: GemBoard, colours: Array[int]) -> Array[Placement]:
	var result: Array[Placement] = []
	for rotation: int in DropGame.OFFSETS.size():
		for column: int in GemBoard.WIDTH:
			var placement: Placement = place(board, colours, column, rotation)
			if placement != null:
				result.append(placement)
	return result


## Plays one placement out: drops the pair from the top, then runs the chain.
## Returns null if it can't go there.
static func place(board: GemBoard, colours: Array[int], column: int, rotation: int) -> Placement:
	var pivot := Vector2i(column, DropGame.SPAWN.y)
	var cells: Array[Vector2i] = [pivot, pivot + DropGame.OFFSETS[rotation]]
	for cell: Vector2i in cells:
		if not GemBoard.in_bounds(cell.x, cell.y) or board.get_cell(cell.x, cell.y) != GemBoard.EMPTY:
			return null
	var placement := Placement.new()
	placement.column = column
	placement.rotation = rotation
	placement.board = board.copy()
	for i: int in cells.size():
		placement.board.set_cell(cells[i].x, cells[i].y, colours[i])
	var extra: int = 0
	while true:
		var groups: Array[PackedInt32Array] = placement.board.resolve_step()
		if groups.is_empty():
			break
		placement.chain += 1
		extra += GemBoard.extra_gems(groups)
	placement.attack = GemBoard.attack_for(placement.chain, extra)
	return placement


static func evaluate(placement: Placement) -> float:
	var b: GemBoard = placement.board
	# The next pair needs its spawn cells free, or this placement loses.
	for i: int in 2:
		if b.get_cell(DropGame.SPAWN.x, DropGame.SPAWN.y - i) != GemBoard.EMPTY:
			return TOPPED_SCORE
	var score: float = placement.attack * ATTACK_WEIGHT
	var touching: int = 0
	for y: int in GemBoard.HEIGHT:
		for x: int in GemBoard.WIDTH:
			var value: int = b.get_cell(x, y)
			if not GemBoard.is_gem(value):
				continue
			if x + 1 < GemBoard.WIDTH and b.get_cell(x + 1, y) == value:
				touching += 1
			if y + 1 < GemBoard.HEIGHT and b.get_cell(x, y + 1) == value:
				touching += 1
	score += touching * TOUCHING_WEIGHT
	for x: int in GemBoard.WIDTH:
		var height: int = b.column_height(x)
		score -= height * height * HEIGHT_WEIGHT
		if height > DANGER_HEIGHT:
			score -= (height - DANGER_HEIGHT) * DANGER_WEIGHT * (2.0 if x == DropGame.SPAWN.x else 1.0)
	return score
