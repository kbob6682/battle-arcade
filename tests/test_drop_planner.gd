extends "res://tests/test_case.gd"
## Drop mode bot decisions.


func board(bottom_rows: Array[String]) -> GemBoard:
	var rows: Array[String] = []
	for i: int in GemBoard.HEIGHT - bottom_rows.size():
		rows.append("......")
	rows.append_array(bottom_rows)
	return GemBoard.decode("".join(rows).replace(".", "0"))


func no_mistakes(difficulty: BotOpponent.Difficulty) -> DropPlanner.Settings:
	var settings: DropPlanner.Settings = DropPlanner.settings_for(difficulty)
	settings.mistake_chance = 0.0
	return settings


func seeded(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng


func test_every_level_takes_an_obvious_match() -> void:
	var b: GemBoard = board(["1.....", "1....."])
	for level: int in BotOpponent.Difficulty.values():
		var choice: DropPlanner.Placement = DropPlanner.choose(b, [1, 3] as Array[int], [4, 5] as Array[int], no_mistakes(level), seeded(1))
		check(choice != null and choice.chain >= 1, "level %d clears" % level)


func test_prefers_a_two_chain_over_a_single_clear() -> void:
	# A 1 in column 2 clears the row of 1s, dropping the top 2 onto the 2s: a
	# 2-chain. A 1 in column 5 is only a single clear.
	var b: GemBoard = board(["2.....", "11...1", "223..1"])
	check_eq(DropPlanner.place(b, [1, 4] as Array[int], 2, 0).chain, 2, "column 2 chains")
	check_eq(DropPlanner.place(b, [1, 4] as Array[int], 5, 0).chain, 1, "column 5 is a single clear")
	for level: int in BotOpponent.Difficulty.values():
		var choice: DropPlanner.Placement = DropPlanner.choose(b, [1, 4] as Array[int], [5, 5] as Array[int], no_mistakes(level), seeded(2))
		check_eq(choice.chain, 2, "level %d picks the chain" % level)


func test_placements_that_dont_fit_are_skipped() -> void:
	var b := GemBoard.new()
	for y: int in GemBoard.HEIGHT:
		b.set_cell(0, y, 1 + y % 2)
	for placement: DropPlanner.Placement in DropPlanner.placements(b, [3, 4] as Array[int]):
		check(placement.column != 0 and placement.column + DropGame.OFFSETS[placement.rotation].x != 0, "nothing in the full column")


func test_medium_and_hard_survive_without_junk() -> void:
	for level: int in [BotOpponent.Difficulty.MEDIUM, BotOpponent.Difficulty.HARD]:
		var settings: DropPlanner.Settings = DropPlanner.settings_for(level)
		var pieces: RandomNumberGenerator = seeded(10 + level)
		var rng: RandomNumberGenerator = seeded(20 + level)
		var b := GemBoard.new()
		var next: Array[int] = [pieces.randi_range(1, 5), pieces.randi_range(1, 5)]
		var survived: int = 0
		for i: int in 200:
			var colours: Array[int] = next
			next = [pieces.randi_range(1, 5), pieces.randi_range(1, 5)]
			var choice: DropPlanner.Placement = DropPlanner.choose(b, colours, next, settings, rng)
			if choice == null or DropPlanner.evaluate(choice) == DropPlanner.TOPPED_SCORE:
				break
			b = choice.board
			survived += 1
		check_eq(survived, 200, "level %d survives 200 pairs" % level)


func test_hard_spreads_its_thinking_over_frames() -> void:
	var b: GemBoard = board(["12.34.", "21.43.", "12534.", "345123", "123451", "512345"])
	var started: int = Time.get_ticks_usec()
	var search := DropPlanner.Search.new(b, [1, 2] as Array[int], [3, 4] as Array[int], no_mistakes(BotOpponent.Difficulty.HARD), seeded(3))
	var slowest: float = (Time.get_ticks_usec() - started) / 1000.0
	var steps: int = 0
	while not search.done:
		started = Time.get_ticks_usec()
		search.step()
		slowest = maxf(slowest, (Time.get_ticks_usec() - started) / 1000.0)
		steps += 1
	print("          Hard: %d steps, slowest %.1f ms" % [steps, slowest])
	check(steps <= DropPlanner.LOOKAHEAD_WIDTH, "finishes within %d frames" % DropPlanner.LOOKAHEAD_WIDTH)
	check(slowest < 16.0, "each frame's share is under 16 ms (slowest %.1f)" % slowest)
	check(search.best != null, "has a decision")
