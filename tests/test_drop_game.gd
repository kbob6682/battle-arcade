extends "res://tests/test_case.gd"
## Drop mode rules, stepped with fixed times.


func started(seed_value: int = 42) -> DropGame:
	var pieces_rng := RandomNumberGenerator.new()
	pieces_rng.seed = seed_value
	var game := DropGame.new()
	game.start(pieces_rng)
	return game


## Ticks until the next pair appears (or the board tops out).
func settle(game: DropGame) -> void:
	for i: int in 200:
		if game.phase != DropGame.Phase.RESOLVING:
			return
		game.tick(0.05)


func test_same_seed_gives_same_pairs() -> void:
	var a: DropGame = started(7)
	var b: DropGame = started(7)
	for i: int in 10:
		check_eq(a.piece_colours, b.piece_colours, "pair %d" % i)
		check_eq(a.next_colours, b.next_colours, "next %d" % i)
		a.hard_drop()
		b.hard_drop()
		settle(a)
		settle(b)


func test_pair_falls_and_lands() -> void:
	var game: DropGame = started()
	check_eq(game.piece_cells(), [Vector2i(2, 1), Vector2i(2, 0)] as Array[Vector2i], "spawns with second gem on top")
	game.tick(DropGame.BASE_FALL_SEC)
	check_eq(game.pivot, Vector2i(2, 2), "fell one row")
	game.hard_drop()
	check_eq(game.phase, DropGame.Phase.RESOLVING, "landed")
	check_eq(game.board.column_height(2), 2, "both gems on the board")
	settle(game)
	check_eq(game.phase, DropGame.Phase.FALLING, "next pair appeared")


func test_gems_fall_separately_after_landing() -> void:
	var game: DropGame = started()
	game.board.set_cell(3, GemBoard.HEIGHT - 1, GemBoard.JUNK)
	game.rotate(1) # second gem to the right, over the junk
	game.hard_drop()
	check_eq(game.board.column_height(2), 1, "pivot fell to the floor")
	check_eq(game.board.column_height(3), 2, "second gem landed on the junk")


func test_rotating_against_a_wall_nudges_the_pair() -> void:
	var game: DropGame = started()
	while game.move(-1):
		pass
	check_eq(game.pivot.x, 0, "against the left wall")
	check(game.rotate(-1), "rotation still works")
	check_eq(game.piece_cells(), [Vector2i(1, 1), Vector2i(0, 1)] as Array[Vector2i], "nudged right")


func test_landing_a_match_clears_and_reports_the_chain() -> void:
	var game: DropGame = started()
	var chains: Array[int] = []
	game.chain_finished.connect(func(chain: int) -> void: chains.append(chain))
	game.board.set_cell(0, GemBoard.HEIGHT - 1, 1)
	game.piece_colours = [1, 1]
	game.move(-1)
	game.move(-1)
	game.hard_drop()
	settle(game)
	check_eq(chains, [1] as Array[int], "one 1-step chain")
	check_eq(game.board.column_height(0), 0, "the three gems cleared")


func test_tops_out_when_a_new_pair_has_no_room() -> void:
	var game: DropGame = started()
	var topped: Array[bool] = []
	game.topped_out.connect(func() -> void: topped.append(true))
	# Column 2 nearly full with alternating colours, so nothing clears.
	for y: int in range(2, GemBoard.HEIGHT):
		game.board.set_cell(2, y, 1 + y % 2)
	game.piece_colours = [3, 4]
	game.hard_drop()
	settle(game)
	check_eq(game.phase, DropGame.Phase.TOPPED, "topped out")
	check_eq(topped.size(), 1, "reported once")


func test_speeds_up_over_time() -> void:
	var game: DropGame = started()
	check(is_equal_approx(game.fall_interval(), DropGame.BASE_FALL_SEC), "starts at base speed")
	game.elapsed = DropGame.SPEEDUP_EVERY_SEC
	check(game.fall_interval() < DropGame.BASE_FALL_SEC, "faster after 30 s")
	game.elapsed = 100000.0
	check(is_equal_approx(game.fall_interval(), DropGame.MIN_FALL_SEC), "never faster than the minimum")


func test_placeholder_bot_tops_out_and_says_so() -> void:
	var bot: GemBattleBot = GameRegistry.find("gem_battle").create_bot(BotOpponent.Difficulty.EASY) as GemBattleBot
	var got: Array[int] = []
	bot.game_message.connect(func(kind: int, _data: Dictionary) -> void: got.append(kind))
	bot.begin_match(1)
	bot.attach()
	bot.start_match(1234, "Drop")
	# Simulate up to 20 minutes of play without waiting for it.
	for i: int in 24000:
		bot._process(0.05)
		if bot._game.phase == DropGame.Phase.TOPPED:
			break
	check_eq(bot._game.phase, DropGame.Phase.TOPPED, "random play tops out")
	await get_tree().process_frame
	check_eq(got, [GemBattle.Kind.TOPPED] as Array[int], "sent TOPPED")
	bot.free()


func test_input_actions_exist() -> void:
	for action: String in ["gem_left", "gem_right", "gem_soft_drop", "gem_hard_drop", "gem_rotate_cw", "gem_rotate_ccw"]:
		check(InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty(), "%s has a key" % action)


func test_scene_starts_and_runs_against_the_bot() -> void:
	var info: GameInfo = GameRegistry.find("gem_battle")
	var bot: BotOpponent = info.create_bot(BotOpponent.Difficulty.EASY)
	add_child(bot)
	var player := PlayerInfo.new()
	player.player_name = "Tester"
	bot.info = player
	bot.begin_match(1)
	var game: GemBattle = info.scene.instantiate() as GemBattle
	add_child(game)
	game.start_game(99, bot, "Drop", true, player)
	bot.start_match(99, "Drop")
	for i: int in 10:
		await get_tree().process_frame
	game._game.hard_drop()
	for i: int in 10:
		await get_tree().process_frame
	check(not game.is_finished(), "still playing")
	game.queue_free()
	bot.queue_free()
