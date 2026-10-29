extends "res://tests/test_case.gd"
## Swap mode rules and bots, stepped with fixed times.


func started(seed_value: int = 42) -> SwapGame:
	var shared_rng := RandomNumberGenerator.new()
	shared_rng.seed = seed_value
	var junk_rng := RandomNumberGenerator.new()
	junk_rng.seed = 1
	var game := SwapGame.new()
	game.start(shared_rng, junk_rng)
	return game


## A started game whose board is replaced: rows lists the bottom rows, top
## first, as strings of cell values ("0" empty, "1"-"5" gems, "6" junk).
func with_board(rows: Array[String]) -> SwapGame:
	var game: SwapGame = started()
	game.board = GemBoard.new()
	for r: int in rows.size():
		var y: int = GemBoard.HEIGHT - rows.size() + r
		for x: int in GemBoard.WIDTH:
			game.board.set_cell(x, y, rows[r].unicode_at(x) - 48)
	return game


## Ticks until the board is still again (or topped out).
func settle(game: SwapGame) -> void:
	for i: int in 200:
		if game.phase != SwapGame.Phase.RESOLVING:
			return
		game.tick(0.05)


func row(game: SwapGame, y: int) -> PackedInt32Array:
	return game.board.cells.slice(y * GemBoard.WIDTH, (y + 1) * GemBoard.WIDTH)


func test_same_seed_gives_same_start_and_rows() -> void:
	var a: SwapGame = started(7)
	var b: SwapGame = started(7)
	check_eq(a.board.cells, b.board.cells, "start board")
	for i: int in 5:
		check_eq(a.next_row, b.next_row, "row %d" % i)
		a.tick(a.rise_interval() + 0.01)
		b.tick(b.rise_interval() + 0.01)
		settle(a)
		settle(b)
	check(a.board.cells != started(8).board.cells, "a different seed gives a different board")


func test_start_board_is_half_full_with_no_matches() -> void:
	for seed_value: int in 20:
		var game: SwapGame = started(seed_value)
		check(game.board.find_groups().is_empty(), "no ready-made matches (seed %d)" % seed_value)
		for x: int in GemBoard.WIDTH:
			check_eq(game.board.column_height(x), SwapGame.START_ROWS, "column %d height" % x)
		check_eq(game.phase, SwapGame.Phase.READY, "ready to swap")


func test_only_swaps_that_make_a_match_work() -> void:
	var game: SwapGame = with_board(["116112"])
	var rejected: Array[int] = [0]
	game.swap_rejected.connect(func(_a: Vector2i, _b: Vector2i) -> void: rejected[0] += 1)
	var y: int = GemBoard.HEIGHT - 1
	check(not game.try_swap(Vector2i(4, y), Vector2i(5, y)), "no match: rejected")
	check_eq(row(game, y), PackedInt32Array([1, 1, 6, 1, 1, 2]), "nothing moved")
	check(not game.try_swap(Vector2i(1, y), Vector2i(2, y)), "stone can't move")
	check(not game.try_swap(Vector2i(3, y), Vector2i(4, y)), "same colour")
	check(not game.try_swap(Vector2i(0, y), Vector2i(3, y)), "not neighbours")
	check(not game.try_swap(Vector2i(5, y), Vector2i(6, y)), "off the board")
	check_eq(rejected[0], 5, "every refusal reported")


func test_a_match_clears_but_a_plain_three_sends_nothing() -> void:
	var game: SwapGame = with_board(["121345"])
	var sent: Array[int] = []
	var chains: Array[int] = []
	game.attack_sent.connect(func(amount: int) -> void: sent.append(amount))
	game.chain_finished.connect(func(chain: int) -> void: chains.append(chain))
	var y: int = GemBoard.HEIGHT - 1
	game.board.set_cell(1, y - 1, 1)
	# Row 11: 1 2 1 3 4 5, with a 1 above the 2. Swapping that 1 down makes 1 1 1.
	check(game.try_swap(Vector2i(1, y - 1), Vector2i(1, y)), "swap accepted")
	check(not game.can_swap(), "no swapping while it clears")
	settle(game)
	check_eq(row(game, y), PackedInt32Array([0, 2, 0, 3, 4, 5]), "the three 1s cleared and the 2 fell")
	check_eq(chains, [1] as Array[int], "one chain step")
	check(sent.is_empty(), "a plain 3-match sends no junk")


func test_bigger_groups_and_chains_attack() -> void:
	check_eq(SwapGame.attack_for(0, 0), 0, "nothing cleared")
	check_eq(SwapGame.attack_for(1, 0), 0, "plain 3")
	check_eq(SwapGame.attack_for(1, 1), 1, "4-match")
	check_eq(SwapGame.attack_for(1, 2), 2, "5-match")
	check_eq(SwapGame.attack_for(2, 0), 4, "2-chain")
	check_eq(SwapGame.attack_for(3, 1), 9, "3-chain plus one extra")
	check_eq(SwapGame.attack_for(9, 0), GemBoard.MAX_ATTACK, "capped")


func test_a_four_match_blocks_incoming_junk_first() -> void:
	var game: SwapGame = with_board(["112134"])
	game.add_incoming(5)
	var sent: Array[int] = []
	game.attack_sent.connect(func(amount: int) -> void: sent.append(amount))
	var y: int = GemBoard.HEIGHT - 1
	game.board.set_cell(2, y - 1, 1)
	check(game.try_swap(Vector2i(2, y - 1), Vector2i(2, y)), "swap accepted")
	settle(game)
	check_eq(game.incoming, 4, "the 1 junk from a 4-match cancelled 1 incoming")
	check(sent.is_empty(), "nothing left over to send")


func test_rows_rise_from_the_bottom() -> void:
	var game: SwapGame = with_board(["000000"])
	var expected: PackedInt32Array = game.next_row
	game.tick(game.rise_interval() - 0.1)
	check_eq(row(game, GemBoard.HEIGHT - 1), PackedInt32Array([0, 0, 0, 0, 0, 0]), "not yet")
	check(game.rise_progress() > 0.9, "the bar is nearly full")
	game.tick(0.2)
	check_eq(row(game, GemBoard.HEIGHT - 1), expected, "the previewed row pushed in")
	check_eq(game.next_row.size(), GemBoard.WIDTH, "a new row is previewed")


func test_junk_pushes_in_stone_rows_above_the_new_row() -> void:
	var game: SwapGame = with_board(["000000"])
	var expected: PackedInt32Array = game.next_row
	var landed: Array[int] = []
	game.junk_dropped.connect(func(amount: int) -> void: landed.append(amount))
	game.add_incoming(12)
	game.tick(game.rise_interval() + 0.01)
	var stone: PackedInt32Array = PackedInt32Array([6, 6, 6, 6, 6, 6])
	check_eq(row(game, GemBoard.HEIGHT - 3), stone, "stone row")
	check_eq(row(game, GemBoard.HEIGHT - 2), stone, "second stone row")
	check_eq(row(game, GemBoard.HEIGHT - 1), expected, "the normal row below the stone")
	check_eq(game.incoming, 0, "all junk landed")
	check_eq(landed, [12] as Array[int], "reported")


func test_at_most_three_junk_rows_at_once() -> void:
	var game: SwapGame = with_board(["000000"])
	game.add_incoming(GemBoard.MAX_ATTACK)
	game.tick(game.rise_interval() + 0.01)
	check_eq(game.board.cells.count(GemBoard.JUNK), SwapGame.MAX_JUNK_ROWS * GemBoard.WIDTH, "three rows of stone")
	check_eq(game.incoming, GemBoard.MAX_ATTACK - SwapGame.MAX_JUNK_ROWS * GemBoard.WIDTH, "the rest waits")


func test_a_partial_junk_row_mixes_stone_and_gems() -> void:
	var game: SwapGame = with_board(["000000"])
	game.add_incoming(4)
	game.tick(game.rise_interval() + 0.01)
	var partial: PackedInt32Array = row(game, GemBoard.HEIGHT - 2)
	check_eq(partial.count(GemBoard.JUNK), 4, "four stones")
	for value: int in partial:
		check(value == GemBoard.JUNK or GemBoard.is_gem(value), "stone or gem")


func test_a_row_lining_up_clears_without_attacking() -> void:
	var game: SwapGame = with_board(["000000", "000000"])
	var colour: int = game.next_row[0]
	game.board.set_cell(0, GemBoard.HEIGHT - 1, colour)
	game.board.set_cell(0, GemBoard.HEIGHT - 2, colour)
	var sent: Array[int] = []
	var chains: Array[int] = []
	game.attack_sent.connect(func(amount: int) -> void: sent.append(amount))
	game.chain_finished.connect(func(chain: int) -> void: chains.append(chain))
	game.tick(game.rise_interval() + 0.01)
	settle(game)
	check_eq(game.board.get_cell(0, GemBoard.HEIGHT - 1), GemBoard.EMPTY, "the three in column 0 cleared")
	check_eq(chains.size(), 1, "it was a chain")
	check(sent.is_empty(), "but sent no junk")


func test_tops_out_when_a_row_pushes_a_gem_off_the_top() -> void:
	var game: SwapGame = with_board(["000000"])
	game.board.set_cell(3, 0, 2)
	var topped: Array[bool] = [false]
	game.topped_out.connect(func() -> void: topped[0] = true)
	check(game.is_in_danger() == false, "row 1 is clear")
	game.tick(game.rise_interval() + 0.01)
	check(topped[0], "topped out")
	check(game.is_topped(), "and stays topped")
	check(not game.try_swap(Vector2i(0, 11), Vector2i(1, 11)), "no more swaps")


func test_rising_speeds_up_until_sudden_death() -> void:
	var game: SwapGame = with_board([])
	check(is_equal_approx(game.rise_interval(), SwapGame.BASE_RISE_SEC), "starts slow")
	game.elapsed = SwapGame.SPEEDUP_EVERY_SEC
	check(game.rise_interval() < SwapGame.BASE_RISE_SEC, "faster after 45 s")
	game.elapsed = SwapGame.SUDDEN_DEATH_SEC + 100.0
	check(game.is_sudden_death(), "sudden death")
	check(is_equal_approx(game.rise_interval(), SwapGame.SUDDEN_DEATH_RISE_SEC), "never faster than sudden death")


func test_board_helpers() -> void:
	var b := GemBoard.new()
	b.set_cell(0, 11, 1)
	b.set_cell(1, 11, 1)
	check(not b.has_group_at(Vector2i(0, 11)), "two isn't a group")
	b.set_cell(1, 10, 1)
	check(b.has_group_at(Vector2i(0, 11)), "an L of three is")
	check(not b.has_group_at(Vector2i(5, 5)), "empty cell")
	check(b.push_row(PackedInt32Array([2, 2, 3, 3, 4, 4])), "pushed")
	check_eq(b.get_cell(0, 10), 1, "everything moved up")
	check_eq(b.get_cell(1, 9), 1, "everything moved up (2)")
	check_eq(b.get_cell(5, 11), 4, "new row at the bottom")
	b.set_cell(2, 0, 5)
	var before: PackedInt32Array = b.cells.duplicate()
	check(not b.push_row(PackedInt32Array([1, 2, 3, 4, 5, 1])), "full to the top")
	check_eq(b.cells, before, "nothing changed")


func test_planner_only_suggests_matching_swaps() -> void:
	var game: SwapGame = started(5)
	var moves: Array[SwapPlanner.Move] = SwapPlanner.moves(game.board)
	check(not moves.is_empty(), "a fresh board has moves")
	for move: SwapPlanner.Move in moves:
		check(SwapGame.is_matching_swap(game.board, move.a, move.b), "matching swap")
		check(move.chain >= 1, "it clears something")
	var settings: SwapPlanner.Settings = SwapPlanner.settings_for(BotOpponent.Difficulty.HARD)
	var choice: SwapPlanner.Move = SwapPlanner.choose(game.board, settings, RandomNumberGenerator.new())
	check(choice != null and SwapGame.is_matching_swap(game.board, choice.a, choice.b), "Hard picks a matching swap")
	var stuck: SwapGame = with_board(["123451", "234512"])
	check(SwapPlanner.choose(stuck.board, settings, RandomNumberGenerator.new()) == null, "no moves: nothing to pick")


func test_planner_prefers_breaking_stone() -> void:
	# Swapping column 2 down makes three 1s on the left; column 3 or 4 makes
	# three 1s on the right, next to the stone.
	var game: SwapGame = with_board(["451126", "112311"])
	var choice: SwapPlanner.Move = SwapPlanner.choose(game.board, SwapPlanner.settings_for(BotOpponent.Difficulty.MEDIUM), _no_mistakes())
	check(choice != null and choice.junk_broken > 0, "breaks the stone")


func _no_mistakes() -> RandomNumberGenerator:
	# Medium slips up 10% of the time; a fixed seed whose first roll is high avoids that.
	var rng := RandomNumberGenerator.new()
	for seed_value: int in 100:
		rng.seed = seed_value
		if rng.randf() > 0.5:
			rng.seed = seed_value
			return rng
	return rng


func test_bot_plays_swap_and_tops_out_under_junk() -> void:
	var bot: GemBattleBot = GameRegistry.find("gem_battle").create_bot(BotOpponent.Difficulty.HARD) as GemBattleBot
	var got: Array[int] = []
	bot.game_message.connect(func(kind: int, _data: Dictionary) -> void: got.append(kind))
	bot.begin_match(1)
	bot.attach()
	bot.start_match(1234, "Swap")
	check(bot._game is SwapGame, "plays Swap")
	var cleared: Array[int] = [0]
	bot._game.chain_step.connect(func(_chain: int, _groups: Array[PackedInt32Array], _colours: Array[int]) -> void: cleared[0] += 1)
	# Up to 10 minutes of play without waiting for it; junk starts after 20 s.
	for i: int in 12000:
		if i > 400 and bot._game.incoming == 0:
			bot._game.add_incoming(GemBoard.MAX_ATTACK)
		bot._process(0.05)
		if bot._game.is_topped():
			break
	check(cleared[0] > 0, "made matches")
	check(bot._game.is_topped(), "tops out under constant junk")
	await get_tree().process_frame
	check(got.has(GemBattle.Kind.BOARD), "sent board snapshots")
	check_eq(got.back(), GemBattle.Kind.TOPPED, "TOPPED is the last message")
	check_eq(got.count(GemBattle.Kind.TOPPED), 1, "TOPPED sent once")
	bot.free()


func test_every_bot_level_plays_swap() -> void:
	for difficulty: int in BotOpponent.DIFFICULTY_NAMES.size():
		var bot: GemBattleBot = GameRegistry.find("gem_battle").create_bot(difficulty) as GemBattleBot
		bot.begin_match(1)
		bot.attach()
		bot.start_match(77, "Swap")
		var swaps: Array[int] = [0]
		(bot._game as SwapGame).swapped.connect(func(_a: Vector2i, _b: Vector2i) -> void: swaps[0] += 1)
		for i: int in 600:
			bot._process(0.05)
		check(swaps[0] >= 3, "%s swapped in 30 s (got %d)" % [BotOpponent.difficulty_name(difficulty), swaps[0]])
		bot.free()


func test_swap_input_actions_exist() -> void:
	var expected: Dictionary = {
		"gem_up": [KEY_UP, KEY_W],
		"gem_down": [KEY_DOWN, KEY_S],
		"gem_swap": [KEY_SPACE],
	}
	for action: String in expected:
		var keys: Array = []
		for event: InputEvent in InputMap.action_get_events(action):
			keys.append((event as InputEventKey).physical_keycode)
		check_eq(keys, expected[action], action)
	check(InputMap.has_action("primary_click"), "mouse action")


func test_swap_scene_starts_and_runs_against_the_bot() -> void:
	var info: GameInfo = GameRegistry.find("gem_battle")
	check(info.modes.has("Swap"), "Swap is listed")
	var bot: BotOpponent = info.create_bot(BotOpponent.Difficulty.EASY)
	add_child(bot)
	var player := PlayerInfo.new()
	player.player_name = "Tester"
	bot.info = player
	bot.begin_match(1)
	var game: GemBattle = info.scene.instantiate() as GemBattle
	add_child(game)
	game.start_game(99, bot, "Swap", true, player)
	bot.start_match(99, "Swap")
	check(game._game is SwapGame, "Swap mode")
	check_eq(game._next_view.columns, GemBoard.WIDTH, "next row preview")
	# Both sides got the same start board from the seed.
	check_eq(game._game.board.cells, (bot as GemBattleBot)._game.board.cells, "same start board")
	for i: int in 10:
		await get_tree().process_frame
	# A click on a gem picks it.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = game._board_view.cell_centre(GemBoard.WIDTH * (GemBoard.HEIGHT - 1) + 1)
	game._on_board_input(click)
	check_eq(game._cursor, Vector2i(1, GemBoard.HEIGHT - 1), "clicked gem picked")
	check_eq(game._board_view.highlight, GemBoard.WIDTH * (GemBoard.HEIGHT - 1) + 1, "and highlighted")
	for i: int in 10:
		await get_tree().process_frame
	check(not game.is_finished(), "still playing")
	game.queue_free()
	bot.queue_free()


func test_hard_spreads_its_thinking_over_frames() -> void:
	var game: SwapGame = started(11)
	# A busier board than the start: ten rows.
	for i: int in 4:
		game.tick(game.rise_interval() + 0.01)
		settle(game)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var started_usec: int = Time.get_ticks_usec()
	var search := SwapPlanner.Search.new(game.board, SwapPlanner.settings_for(BotOpponent.Difficulty.HARD), rng)
	var slowest: float = (Time.get_ticks_usec() - started_usec) / 1000.0
	var steps: int = 0
	while not search.done:
		started_usec = Time.get_ticks_usec()
		search.step()
		slowest = maxf(slowest, (Time.get_ticks_usec() - started_usec) / 1000.0)
		steps += 1
	print("          Swap Hard: %d steps, slowest %.1f ms" % [steps, slowest])
	check(steps <= SwapPlanner.LOOKAHEAD_WIDTH, "finishes within %d frames" % SwapPlanner.LOOKAHEAD_WIDTH)
	check(slowest < 16.0, "each frame's share is under 16 ms (slowest %.1f)" % slowest)
