class_name RopePlanner
extends RefCounted
## Decides where a Rope mode bot aims: it tries every rotation and lane for
## the loaded piece and scores the knots it would leave. Lanes about to flip
## either way matter most; pulling a lane that's already won is mostly wasted.
## Plain logic, so it can be tested headlessly.


## How a bot level plays.
class Settings:
	## Seconds to "think" after reloading before it fires.
	var think_sec: float = 1.0
	## Chance of a random shot instead.
	var mistake_chance: float = 0.0

	func _init(think: float, mistakes: float) -> void:
		think_sec = think
		mistake_chance = mistakes


class Shot:
	var rotation: int = 0
	var row: int = 0
	var score: float = 0.0


## A lane leaning your way is worth this much; each step of pull up to
## WIN_PULL adds a little more (a safer lead).
const LANE_WEIGHT: float = 10.0
const STEP_WEIGHT: float = 1.5


static func settings_for(difficulty: BotOpponent.Difficulty) -> Settings:
	match difficulty:
		BotOpponent.Difficulty.EASY:
			return Settings.new(1.4, 0.4)
		BotOpponent.Difficulty.HARD:
			return Settings.new(0.15, 0.0)
	return Settings.new(0.6, 0.12)


## Every way to fire the piece.
static func shots(type: int) -> Array[Shot]:
	var result: Array[Shot] = []
	for rotation: int in 4:
		for row: int in range(-3, RopeGame.LANES):
			if RopeGame.fits(type, rotation, row):
				var shot := Shot.new()
				shot.rotation = rotation
				shot.row = row
				result.append(shot)
	return result


## The shot to fire for these knots (positive = the bot's way).
static func choose(knots: PackedInt32Array, type: int, settings: Settings, rng: RandomNumberGenerator) -> Shot:
	var options: Array[Shot] = shots(type)
	if options.is_empty():
		return null
	if rng.randf() < settings.mistake_chance:
		return options[rng.randi_range(0, options.size() - 1)]
	var best: Shot = null
	for option: Shot in options:
		var pulls: PackedInt32Array = RopeGame.pulls_for(type, option.rotation, option.row)
		option.score = 0.0
		for lane: int in RopeGame.LANES:
			option.score += lane_value(knots[lane] + pulls[lane]) - lane_value(knots[lane])
		# Small random tie-break so it doesn't always pick the top lane.
		option.score += rng.randf() * 0.01
		if best == null or option.score > best.score:
			best = option
	return best


static func lane_value(knot: int) -> float:
	return signf(knot) * LANE_WEIGHT + clampi(knot, -RopeGame.WIN_PULL, RopeGame.WIN_PULL) * STEP_WEIGHT
