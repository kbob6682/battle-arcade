class_name SwapPlanner
extends RefCounted
## Decides which gems a Swap mode bot swaps. It tries every swap that makes a
## match on a copy of the board (chains included), scores each result, and
## picks the best. Hard also tries a second swap on top of its best few
## options, so it favours swaps that leave a good follow-up. Plain logic, so
## it can be tested headlessly.


## How a bot level plays.
class Settings:
	## Seconds to "think" before each swap (capped when rows rise fast).
	var think_sec: float = 1.0
	## Also try a second swap (Hard).
	var lookahead: bool = false
	## Chance of making a random matching swap instead.
	var mistake_chance: float = 0.0

	func _init(think: float, look: bool, mistakes: float) -> void:
		think_sec = think
		lookahead = look
		mistake_chance = mistakes


## One swap, a and b being neighbouring cells, and what it led to.
class Move:
	var a: Vector2i = Vector2i.ZERO
	var b: Vector2i = Vector2i.ZERO
	## The board after the swap and any chain finished.
	var board: GemBoard = null
	var chain: int = 0
	var attack: int = 0
	var gems_cleared: int = 0
	var junk_broken: int = 0
	var score: float = 0.0


## Score weights. Junk sent matters most, then breaking stone, then clearing
## gems and leaving gems of a colour touching (half-made matches). Tall
## columns are bad, and very bad near the top.
const ATTACK_WEIGHT: float = 10.0
const JUNK_WEIGHT: float = 3.0
const GEMS_WEIGHT: float = 0.6
const TOUCHING_WEIGHT: float = 0.4
const HEIGHT_WEIGHT: float = 0.08
const DANGER_HEIGHT: int = GemBoard.HEIGHT - 3
const DANGER_WEIGHT: float = 40.0
## How much the best follow-up swap counts, compared with this one.
const LOOKAHEAD_DISCOUNT: float = 0.8
## Hard tries a second swap only on top of this many of its best options.
const LOOKAHEAD_WIDTH: int = 6
## The two directions to try from each cell; together they cover every pair.
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN]


static func settings_for(difficulty: BotOpponent.Difficulty) -> Settings:
	match difficulty:
		BotOpponent.Difficulty.EASY:
			return Settings.new(2.5, false, 0.35)
		BotOpponent.Difficulty.HARD:
			return Settings.new(0.6, true, 0.0)
	return Settings.new(1.3, false, 0.1)


## A decision that can be spread over several frames, like DropPlanner.Search:
## step() tries one option's follow-ups per frame. best is usable at any time
## (null if no swap makes a match); done says it's final.
class Search:
	var done: bool = false
	var best: Move = null
	var _options: Array[Move] = []
	var _index: int = 0
	var _best_score: float = -INF

	func _init(board: GemBoard, settings: Settings, rng: RandomNumberGenerator) -> void:
		var options: Array[Move] = SwapPlanner.moves(board)
		done = true
		if options.is_empty():
			return
		if rng.randf() < settings.mistake_chance:
			best = options[rng.randi_range(0, options.size() - 1)]
			return
		for option: Move in options:
			option.score = SwapPlanner.evaluate(option)
		options.sort_custom(func(x: Move, y: Move) -> bool: return x.score > y.score)
		best = options[0]
		if settings.lookahead:
			_options = options.slice(0, SwapPlanner.LOOKAHEAD_WIDTH)
			done = false

	## Tries every second swap after one more option. Returns true when finished.
	func step() -> bool:
		if done:
			return true
		var option: Move = _options[_index]
		_index += 1
		# Only what the follow-up gains counts; no follow-up at all gains nothing.
		var follow_up_score: float = 0.0
		for follow_up: Move in SwapPlanner.moves(option.board):
			follow_up_score = maxf(follow_up_score, SwapPlanner.gains(follow_up))
		var total: float = option.score + follow_up_score * SwapPlanner.LOOKAHEAD_DISCOUNT
		if total > _best_score:
			_best_score = total
			best = option
		done = _index >= _options.size()
		return done


## The swap to make, worked out all at once, or null if none makes a match.
static func choose(board: GemBoard, settings: Settings, rng: RandomNumberGenerator) -> Move:
	var search := Search.new(board, settings, rng)
	while not search.step():
		pass
	return search.best


## Every swap that makes a match, each played out on a copy of the board.
static func moves(board: GemBoard) -> Array[Move]:
	var result: Array[Move] = []
	for y: int in GemBoard.HEIGHT:
		for x: int in GemBoard.WIDTH:
			var a := Vector2i(x, y)
			for dir: Vector2i in DIRECTIONS:
				if SwapGame.is_matching_swap(board, a, a + dir):
					result.append(play(board, a, a + dir))
	return result


## Plays one swap out, chain included. Expects a matching swap.
static func play(board: GemBoard, a: Vector2i, b: Vector2i) -> Move:
	var move := Move.new()
	move.a = a
	move.b = b
	move.board = board.copy()
	var held: int = move.board.get_cell(a.x, a.y)
	move.board.set_cell(a.x, a.y, move.board.get_cell(b.x, b.y))
	move.board.set_cell(b.x, b.y, held)
	var junk_before: int = _count(move.board, GemBoard.JUNK)
	var extra: int = 0
	while true:
		var groups: Array[PackedInt32Array] = move.board.resolve_step()
		if groups.is_empty():
			break
		move.chain += 1
		extra += GemBoard.extra_gems(groups)
		for group: PackedInt32Array in groups:
			move.gems_cleared += group.size()
	move.junk_broken = junk_before - _count(move.board, GemBoard.JUNK)
	move.attack = SwapGame.attack_for(move.chain, extra)
	return move


static func evaluate(move: Move) -> float:
	return gains(move) + board_value(move.board)


## What the swap itself achieved: junk sent, stone broken, gems cleared.
static func gains(move: Move) -> float:
	return move.attack * ATTACK_WEIGHT + move.junk_broken * JUNK_WEIGHT + move.gems_cleared * GEMS_WEIGHT


## How good a board is to play on: touching gems up, height down.
static func board_value(b: GemBoard) -> float:
	var score: float = 0.0
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
			score -= (height - DANGER_HEIGHT) * DANGER_WEIGHT
	return score


static func _count(board: GemBoard, value: int) -> int:
	return board.cells.count(value)
