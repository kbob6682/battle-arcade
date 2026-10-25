extends "res://tests/test_case.gd"


func test_same_seed_gives_same_targets() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 42
	b.seed = 42
	var targets_a: Array[Vector2] = TestRace.make_targets(a, TestRace.TARGET_COUNT)
	check_eq(targets_a, TestRace.make_targets(b, TestRace.TARGET_COUNT), "same seed, same targets")
	var c := RandomNumberGenerator.new()
	c.seed = 43
	check(targets_a != TestRace.make_targets(c, TestRace.TARGET_COUNT), "different seed, different targets")
	for t: Vector2 in targets_a:
		check(t.x >= 0.0 and t.x <= 1.0 and t.y >= 0.0 and t.y <= 1.0, "target %s inside the area" % t)


func test_both_sides_agree_on_the_winner() -> void:
	for times: Array in [[1000, 2000], [2000, 1000], [1500, 1500]]:
		var host_view: MiniGame.Outcome = TestRace.race_winner(times[0], times[1], true)
		var guest_view: MiniGame.Outcome = TestRace.race_winner(times[1], times[0], false)
		check(host_view != guest_view, "exactly one winner for host %d / guest %d" % [times[0], times[1]])
	check_eq(TestRace.race_winner(1000, 2000, false), MiniGame.Outcome.WIN, "faster wins")
	check_eq(TestRace.race_winner(1500, 1500, true), MiniGame.Outcome.WIN, "host wins an exact tie")
