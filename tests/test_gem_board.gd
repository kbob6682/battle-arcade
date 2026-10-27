extends "res://tests/test_case.gd"
## Gem Battle board rules. Boards are written as rows from the top, but only
## the bottom rows are given: missing rows above are empty. "." is empty,
## "1"-"5" are gems, "6" is junk.


func board(bottom_rows: Array[String]) -> GemBoard:
	var rows: Array[String] = []
	for i: int in GemBoard.HEIGHT - bottom_rows.size():
		rows.append("......")
	rows.append_array(bottom_rows)
	return GemBoard.decode("".join(rows).replace(".", "0"))


func rows_of(b: GemBoard, count: int) -> Array[String]:
	var text: String = b.encode().replace("0", ".")
	var result: Array[String] = []
	for y: int in range(GemBoard.HEIGHT - count, GemBoard.HEIGHT):
		result.append(text.substr(y * GemBoard.WIDTH, GemBoard.WIDTH))
	return result


func test_gravity_fills_gaps() -> void:
	var b: GemBoard = board(["1.....", "......", "2..3..", "......"])
	check(b.apply_gravity(), "something moved")
	check_eq(rows_of(b, 2), ["1.....", "2..3.."] as Array[String], "fell to the bottom, order kept")
	check(not b.apply_gravity(), "settled board doesn't move")


func test_three_in_a_row_clears_but_two_dont() -> void:
	var b: GemBoard = board(["11.22."])
	check_eq(b.find_groups().size(), 0, "two of a kind isn't a group")
	b = board(["111.22"])
	check_eq(b.resolve(), 1, "a 3-match is a 1-step chain")
	check_eq(rows_of(b, 1), ["....22"] as Array[String], "only the match cleared")


func test_groups_connect_round_corners_not_diagonally() -> void:
	check_eq(board(["1.....", "11...."]).find_groups().size(), 1, "L shape is a group")
	check_eq(board([".1....", "1.1..."]).find_groups().size(), 0, "diagonals don't connect")
	var groups: Array[PackedInt32Array] = board(["2.....", "2.....", "21111."]).find_groups()
	check_eq(groups.size(), 2, "two separate groups")


func test_junk_breaks_only_when_a_match_touches_it() -> void:
	var b: GemBoard = board(["6....6", "111.66"])
	b.resolve()
	check_eq(rows_of(b, 2), [".....6", "....66"] as Array[String], "touching junk broke, the rest stayed")
	check_eq(board(["666..."]).find_groups().size(), 0, "junk never matches")


func test_falling_gems_make_a_chain() -> void:
	# Clearing the 1s drops the top 2 next to the bottom pair: a second step.
	var b: GemBoard = board(["2.....", "111...", "223..."])
	check_eq(b.resolve(), 2, "2-step chain")
	check_eq(rows_of(b, 1), ["..3..."] as Array[String], "both steps cleared")


func test_attack_sizes_double_and_cap() -> void:
	var expected: Array[int] = [0, 2, 4, 8, 16, 24, 24]
	for chain: int in expected.size():
		check_eq(GemBoard.attack_for(chain, 0), expected[chain], "chain %d" % chain)
	check_eq(GemBoard.attack_for(1, 2), 4, "a 5-match sends 2 extra")
	check_eq(GemBoard.attack_for(4, 20), 24, "bonus still capped")


func test_bigger_groups_count_extra_gems() -> void:
	var b: GemBoard = board(["11111.", "2222.."])
	check_eq(GemBoard.extra_gems(b.find_groups()), 3, "a 5-group (2 extra) and a 4-group (1 extra)")


func test_attack_cancels_incoming_junk_first() -> void:
	check_eq(GemBoard.cancel_incoming(5, 3), Vector2i(2, 0), "all of it blocked")
	check_eq(GemBoard.cancel_incoming(2, 5), Vector2i(0, 3), "blocked, rest sent")
	check_eq(GemBoard.cancel_incoming(0, 4), Vector2i(0, 4), "nothing incoming")


func test_junk_lands_on_the_stacks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var b := GemBoard.new()
	check_eq(b.drop_junk(GemBoard.WIDTH, rng), 0, "a full row fits")
	check_eq(rows_of(b, 1), ["666666"] as Array[String], "one in every column")
	b = board(["1....."])
	check_eq(b.drop_junk(8, rng), 0, "8 fit")
	var junk_per_column: Array[int] = []
	for x: int in GemBoard.WIDTH:
		var junk: int = 0
		for y: int in GemBoard.HEIGHT:
			if b.get_cell(x, y) == GemBoard.JUNK:
				junk += 1
		junk_per_column.append(junk)
	junk_per_column.sort()
	check_eq(junk_per_column, [1, 1, 1, 1, 2, 2] as Array[int], "a row plus 2 in different columns")
	check_eq(b.get_cell(0, GemBoard.HEIGHT - 1), 1, "the gem stayed at the bottom")
	check(not b.apply_gravity(), "junk landed on top of the stacks, no gaps")


func test_junk_that_doesnt_fit_is_reported() -> void:
	var b := GemBoard.new()
	for y: int in GemBoard.HEIGHT:
		b.set_cell(0, y, 1 + y % 2)
	var rng := RandomNumberGenerator.new()
	check_eq(b.drop_junk(GemBoard.WIDTH, rng), 1, "the full column overflows")


func test_snapshots_round_trip_and_reject_bad_input() -> void:
	var b: GemBoard = board(["2.....", "111.6."])
	check_eq(GemBoard.decode(b.encode()).cells, b.cells, "round trip")
	check(GemBoard.decode("123") == null, "wrong length")
	check(GemBoard.decode("7".repeat(GemBoard.WIDTH * GemBoard.HEIGHT)) == null, "bad cell value")
	check(GemBoard.decode("a".repeat(GemBoard.WIDTH * GemBoard.HEIGHT)) == null, "not digits")
