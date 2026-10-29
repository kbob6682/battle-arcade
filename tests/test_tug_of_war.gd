extends "res://tests/test_case.gd"
## Tug of War bots, screen and controls.


func seeded(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng


func no_mistakes(level: BotOpponent.Difficulty) -> TugPlanner.Settings:
	var settings: TugPlanner.Settings = TugPlanner.settings_for(level)
	settings.mistake_chance = 0.0
	return settings


func test_planner_takes_an_obvious_clear() -> void:
	# Column 0 is full except rows 3-6, which a tall I piece fills exactly.
	var b := TugBoard.new()
	for r: int in TugBoard.ROWS:
		if r < 3 or r > 6:
			b.set_cell(0, r, 2)
	for level: int in BotOpponent.DIFFICULTY_NAMES.size():
		var choice: TugPlanner.Placement = TugPlanner.choose(b, 1, 2, no_mistakes(level), seeded(1))
		check(choice != null and choice.cleared == 1, "level %d clears the column" % level)
		if choice != null:
			check_eq(choice.board.width, TugBoard.START_WIDTH + 1, "and the side grows")


func test_placements_cover_every_row_and_fit() -> void:
	var b := TugBoard.new()
	var options: Array[TugPlanner.Placement] = TugPlanner.placements(b, 3)
	check(options.size() >= 4 * 7, "T has a place in every rotation and many rows (got %d)" % options.size())
	var full := TugBoard.new()
	for d: int in full.width:
		for r: int in TugBoard.ROWS:
			full.set_cell(d, r, 4)
	check(TugPlanner.placements(full, 3).is_empty(), "nothing fits a full side")


func test_medium_and_hard_keep_going_without_pressure() -> void:
	for level: int in [BotOpponent.Difficulty.MEDIUM, BotOpponent.Difficulty.HARD]:
		var settings: TugPlanner.Settings = TugPlanner.settings_for(level)
		var game := TugGame.new()
		game.start(seeded(10 + level))
		var placed: int = 0
		for i: int in 150:
			var choice: TugPlanner.Placement = TugPlanner.choose(game.board, game.piece_type, game.next_type, settings, seeded(i))
			if choice == null or TugPlanner.evaluate(choice) == TugPlanner.TOPPED_SCORE:
				break
			game.board = choice.board
			game.piece_type = game.next_type
			game.next_type = game._take_from_bag()
			placed += 1
		check_eq(placed, 150, "level %d places 150 pieces" % level)


func test_hard_spreads_its_thinking_over_frames() -> void:
	var b := TugBoard.new()
	for d: int in 5:
		for r: int in TugBoard.ROWS:
			if (d + r) % 3 != 0:
				b.set_cell(d, r, 1 + (d + r) % 7)
	var started: int = Time.get_ticks_usec()
	var search := TugPlanner.Search.new(b, 1, 3, no_mistakes(BotOpponent.Difficulty.HARD), seeded(3))
	var slowest: float = (Time.get_ticks_usec() - started) / 1000.0
	var steps: int = 0
	while not search.done:
		started = Time.get_ticks_usec()
		search.step()
		slowest = maxf(slowest, (Time.get_ticks_usec() - started) / 1000.0)
		steps += 1
	print("          Tug Hard: %d steps, slowest %.1f ms" % [steps, slowest])
	check(steps <= TugPlanner.LOOKAHEAD_WIDTH, "finishes within %d frames" % TugPlanner.LOOKAHEAD_WIDTH)
	check(slowest < 16.0, "each frame's share is under 16 ms (slowest %.1f)" % slowest)


func test_bot_clears_and_tops_out_when_pushed() -> void:
	var bot: TugOfWarBot = GameRegistry.find("tug_of_war").create_bot(BotOpponent.Difficulty.HARD) as TugOfWarBot
	var got: Array[int] = []
	bot.game_message.connect(func(kind: int, _data: Dictionary) -> void: got.append(kind))
	bot.begin_match(1)
	bot.attach()
	bot.start_match(1234, "Classic")
	# Two minutes on its own: it should clear some columns.
	for i: int in 2400:
		bot._process(0.05)
	check(not bot._game.is_topped(), "survives two minutes alone")
	await get_tree().process_frame
	check(got.has(TugOfWar.Kind.CLEAR), "cleared columns and said so")
	check(bot._game.board.width > TugBoard.START_WIDTH, "its side grew")
	# Then the player keeps pushing the line until it runs out of room.
	for i: int in 2000:
		if i % 10 == 0:
			bot._on_player_message(TugOfWar.Kind.CLEAR, {"n": 1})
		bot._process(0.05)
		if bot._game.is_topped():
			break
	check(bot._game.is_topped(), "pushed out of room")
	await get_tree().process_frame
	check(got.has(TugOfWar.Kind.BOARD), "sent snapshots")
	check_eq(got.back(), TugOfWar.Kind.TOPPED, "TOPPED is the last message")
	check_eq(got.count(TugOfWar.Kind.TOPPED), 1, "TOPPED sent once")
	bot.free()


func test_bot_ignores_bad_clear_messages() -> void:
	var bot: TugOfWarBot = GameRegistry.find("tug_of_war").create_bot(BotOpponent.Difficulty.EASY) as TugOfWarBot
	bot.begin_match(1)
	bot.start_match(9, "Classic")
	for bad: Variant in [0, 5, -2, "3", 2.5]:
		bot._on_player_message(TugOfWar.Kind.CLEAR, {"n": bad})
	check_eq(bot._game.board.width, TugBoard.START_WIDTH, "line didn't move")
	bot.free()


func test_both_players_agree_when_both_top_out() -> void:
	check_eq(TugOfWar.topped_result(1000, 2000), MiniGame.Outcome.LOSE, "first out loses")
	check_eq(TugOfWar.topped_result(2000, 1000), MiniGame.Outcome.WIN, "last out wins")
	check_eq(TugOfWar.topped_result(1500, 1500), MiniGame.Outcome.DRAW, "same time draws")


func test_controls() -> void:
	var expected: Dictionary = {
		"tug_up": [KEY_UP, KEY_W],
		"tug_down": [KEY_DOWN, KEY_S],
		"tug_rotate_cw": [KEY_LEFT, KEY_A, KEY_X],
		"tug_rotate_ccw": [KEY_Z],
		"tug_soft_drop": [KEY_RIGHT, KEY_D],
		"tug_hard_drop": [KEY_SPACE],
	}
	var clicks: Dictionary = {"tug_rotate_cw": [MOUSE_BUTTON_RIGHT], "tug_rotate_ccw": [MOUSE_BUTTON_LEFT]}
	for action: String in expected:
		var keys: Array = []
		var buttons: Array = []
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				keys.append((event as InputEventKey).physical_keycode)
			elif event is InputEventMouseButton:
				buttons.append((event as InputEventMouseButton).button_index)
		check_eq(keys, expected[action], action)
		check_eq(buttons, clicks.get(action, []), action + " clicks")


func test_listed_with_a_bot_and_classic_mode() -> void:
	var info: GameInfo = GameRegistry.find("tug_of_war")
	check(info != null, "registered")
	check_eq(info.modes, PackedStringArray(["Classic"]), "Classic mode")
	var bot: BotOpponent = info.create_bot(BotOpponent.Difficulty.MEDIUM)
	check(bot is TugOfWarBot, "has a bot")
	bot.free()


func test_scene_runs_against_the_bot_and_the_line_agrees() -> void:
	var info: GameInfo = GameRegistry.find("tug_of_war")
	var bot: TugOfWarBot = info.create_bot(BotOpponent.Difficulty.EASY) as TugOfWarBot
	add_child(bot)
	var player := PlayerInfo.new()
	player.player_name = "Tester"
	bot.info = player
	bot.begin_match(1)
	var game: TugOfWar = info.scene.instantiate() as TugOfWar
	add_child(game)
	game.start_game(99, bot, "Classic", true, player)
	bot.start_match(99, "Classic")
	check_eq(game._game.piece_type, bot._game.piece_type, "same first piece")
	# Make the player clear a column: fill column 0 apart from the landing cells.
	var landing: Array[Vector2i] = game._game.landing_cells()
	for r: int in TugBoard.ROWS:
		var gap: bool = false
		for cell: Vector2i in landing:
			if cell.x == 0 and cell.y == r:
				gap = true
		if not gap:
			game._game.board.set_cell(0, r, 3)
	game._game.hard_drop()
	for i: int in 10:
		await get_tree().process_frame
	check_eq(game._game.board.width, TugBoard.START_WIDTH + 1, "my side grew")
	check_eq(bot._game.board.width, TugBoard.START_WIDTH - 1, "the bot was pushed back")
	check_eq(game._game.board.width + bot._game.board.width, TugBoard.TOTAL_WIDTH, "the line agrees")
	check_eq(game._my_cleared, 1, "counter")
	check(not game.is_finished(), "still playing")
	game.queue_free()
	bot.queue_free()
