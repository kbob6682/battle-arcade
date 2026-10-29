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
		# Classic.
		"tug_left": [KEY_LEFT, KEY_A],
		"tug_right": [KEY_RIGHT, KEY_D],
		"tug_rotate": [KEY_UP, KEY_W, KEY_X],
		"tug_rotate_back": [KEY_Z],
		"tug_soft_drop": [KEY_DOWN, KEY_S],
		"tug_drop": [KEY_SPACE],
		# Cannon and Rope.
		"tug_aim_up": [KEY_UP, KEY_W],
		"tug_aim_down": [KEY_DOWN, KEY_S],
		"tug_turn": [KEY_LEFT, KEY_A, KEY_X],
		"tug_turn_back": [KEY_Z],
		"tug_fire": [KEY_SPACE, KEY_RIGHT, KEY_D],
	}
	var clicks: Dictionary = {
		"tug_rotate": [MOUSE_BUTTON_RIGHT],
		"tug_rotate_back": [MOUSE_BUTTON_LEFT],
		"tug_turn": [MOUSE_BUTTON_RIGHT],
		"tug_fire": [MOUSE_BUTTON_LEFT],
	}
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
	check_eq(info.modes, PackedStringArray(["Classic", "Cannon", "Rope"]), "three modes")
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
	check(game._field.upright, "Classic is drawn upright")
	game.queue_free()
	bot.queue_free()


func cannon_game(seed_value: int = 42) -> TugGame:
	var game := TugGame.new()
	game.cannon = true
	game.start(seeded(seed_value))
	return game


func test_cannon_waits_at_the_back_until_fired() -> void:
	var game: TugGame = cannon_game()
	var start: Vector2i = game.pos
	game.tick(TugGame.BASE_STEP_SEC * 3.0)
	check_eq(game.pos, start, "doesn't travel on its own")
	check(game.fuse_left() < 1.0 and game.fuse_left() > 0.0, "the fuse is burning")
	check(game.move(1), "can be aimed")
	game.fire()
	check_eq(game.phase, TugGame.Phase.FLYING, "flying")
	check(not game.move(-1), "no aiming in flight")
	game.tick(0.5)
	var nearest: int = 99
	for d: int in game.board.width:
		for r: int in TugBoard.ROWS:
			if game.board.get_cell(d, r) != TugBoard.EMPTY:
				nearest = mini(nearest, d)
	check_eq(nearest, 0, "landed against the line")


func test_cannon_fuse_fires_by_itself() -> void:
	var game: TugGame = cannon_game()
	var first: int = game.piece_type
	game.tick(TugGame.BASE_FUSE_SEC + 0.01)
	check_eq(game.phase, TugGame.Phase.FLYING, "the fuse fired it")
	game.tick(1.0)
	check_eq(game.phase, TugGame.Phase.FALLING, "next piece loaded")
	check(game.board.cells.count(first) >= 4, "the first piece is on the board")
	game.elapsed = TugGame.SUDDEN_DEATH_SEC
	check(is_equal_approx(game.fuse_interval(), TugGame.SUDDEN_DEATH_FUSE_SEC), "short fuse in sudden death")


func test_aim_at_follows_the_mouse_row() -> void:
	var game: TugGame = cannon_game()
	game.aim_at(0)
	var top: int = 99
	for cell: Vector2i in game.piece_cells():
		top = mini(top, cell.y)
	check_eq(top, 0, "aimed at the top row")
	game.aim_at(50)
	for cell: Vector2i in game.piece_cells():
		check(cell.y < TugBoard.ROWS, "stops at the bottom")


func test_rope_shots_pull_lanes() -> void:
	var rope := RopeGame.new()
	rope.start(seeded(4))
	var shots: Array[PackedInt32Array] = []
	rope.fired.connect(func(pulls: PackedInt32Array) -> void: shots.append(pulls))
	check(rope.fire(), "fires when loaded")
	check(not rope.fire(), "not while reloading")
	var total: int = 0
	for knot: int in rope.knots:
		total += knot
	check_eq(total, 4, "four blocks pulled four steps")
	check_eq(shots.size(), 1, "reported")
	rope.apply_their_pulls(shots[0])
	for knot: int in rope.knots:
		check_eq(knot, 0, "their identical shot cancels it")
	rope.tick(RopeGame.BASE_RELOAD_SEC + 0.01)
	check_eq(rope.phase, RopeGame.Phase.AIMING, "reloaded")


func test_rope_flat_pieces_pull_one_lane_hard() -> void:
	check_eq(RopeGame.pulls_for(1, 0, 2), PackedInt32Array([0, 0, 0, 4, 0, 0, 0, 0, 0, 0]), "flat I: 4 in one lane")
	check_eq(RopeGame.pulls_for(1, 1, 3), PackedInt32Array([0, 0, 0, 1, 1, 1, 1, 0, 0, 0]), "tall I: 1 in four lanes")
	check(not RopeGame.fits(1, 1, 8), "can't stick out of the lanes")


func test_rope_aim_and_turn_stay_in_the_lanes() -> void:
	var rope := RopeGame.new()
	rope.start(seeded(4))
	rope.aim_at(-10)
	check(RopeGame.fits(rope.piece_type, rope.rotation, rope.row), "top")
	rope.aim_at(20)
	check(RopeGame.fits(rope.piece_type, rope.rotation, rope.row), "bottom")
	for i: int in 4:
		rope.rotate(1)
		check(RopeGame.fits(rope.piece_type, rope.rotation, rope.row), "turned %d" % i)


func test_rope_result_counts_lanes_then_pull() -> void:
	check_eq(RopeGame.result_for(PackedInt32Array([1, 1, -6, 0, 0, 0, 0, 0, 0, 0])), MiniGame.Outcome.WIN, "2 lanes to 1")
	check_eq(RopeGame.result_for(PackedInt32Array([1, -1, 0, 0, 0, 0, 0, 0, 0, 0])), MiniGame.Outcome.DRAW, "even")
	check_eq(RopeGame.result_for(PackedInt32Array([1, -3, 0, 0, 0, 0, 0, 0, 0, 0])), MiniGame.Outcome.LOSE, "same lanes, less pull")
	var mine := PackedInt32Array([3, -2, 5, 0, 0, -1, 0, 0, 0, 0])
	var theirs := PackedInt32Array()
	for knot: int in mine:
		theirs.append(-knot)
	check_eq(RopeGame.result_for(theirs), MiniGame.Outcome.LOSE, "the other side sees the opposite")


func test_rope_ends_after_two_minutes() -> void:
	var rope := RopeGame.new()
	rope.start(seeded(4))
	var ended: Array[bool] = [false]
	rope.time_up.connect(func() -> void: ended[0] = true)
	rope.tick(RopeGame.MATCH_SEC - 1.0)
	check(not ended[0], "not yet")
	check(rope.is_final_stretch(), "final stretch")
	check(is_equal_approx(rope.reload_interval(), RopeGame.FINAL_RELOAD_SEC), "fastest reload")
	rope.tick(2.0)
	check(ended[0] and rope.is_done(), "time up")
	check(not rope.fire(), "no shots after time")


func test_pull_messages_are_checked() -> void:
	check_eq(TugOfWar.decode_pulls("0004000000"), PackedInt32Array([0, 0, 0, 4, 0, 0, 0, 0, 0, 0]), "good")
	check(TugOfWar.decode_pulls("0005000000").is_empty(), "too many in a lane")
	check(TugOfWar.decode_pulls("1111100000").is_empty(), "too many in total")
	check(TugOfWar.decode_pulls("0000000000").is_empty(), "empty shot")
	check(TugOfWar.decode_pulls("000400000").is_empty(), "wrong length")
	check(TugOfWar.decode_pulls("00a4000000").is_empty(), "not a digit")


func test_rope_planner_saves_a_lane() -> void:
	# Every lane is mine by 6 except lane 4, which they lead by 1.
	var knots := PackedInt32Array([6, 6, 6, 6, -1, 6, 6, 6, 6, 6])
	var shot: RopePlanner.Shot = RopePlanner.choose(knots, 1, RopePlanner.settings_for(BotOpponent.Difficulty.HARD), seeded(2))
	var pulls: PackedInt32Array = RopeGame.pulls_for(1, shot.rotation, shot.row)
	check(pulls[4] >= 2, "pulls lane 4 back (got %s)" % str(pulls))


func test_every_bot_plays_cannon_and_rope() -> void:
	for mode: String in [TugOfWar.CANNON_MODE, TugOfWar.ROPE_MODE]:
		for difficulty: int in BotOpponent.DIFFICULTY_NAMES.size():
			var bot: TugOfWarBot = GameRegistry.find("tug_of_war").create_bot(difficulty) as TugOfWarBot
			var got: Array[int] = []
			bot.game_message.connect(func(kind: int, _data: Dictionary) -> void: got.append(kind))
			bot.begin_match(1)
			bot.attach()
			bot.start_match(31, mode)
			for i: int in 600:
				bot._process(0.05)
			await get_tree().process_frame
			var label: String = "%s %s" % [mode, BotOpponent.difficulty_name(difficulty)]
			if mode == TugOfWar.ROPE_MODE:
				check(got.count(TugOfWar.Kind.PULL) >= 8, "%s fired in 30 s (got %d)" % [label, got.count(TugOfWar.Kind.PULL)])
			else:
				check(bot._game.board.cells.count(TugBoard.EMPTY) < bot._game.board.cells.size() - 12 or got.has(TugOfWar.Kind.CLEAR), "%s placed pieces" % label)
				check(not bot._game.is_topped(), "%s still playing after 30 s" % label)
			bot.free()


func test_rope_scene_against_the_bot_agrees_on_the_result() -> void:
	var info: GameInfo = GameRegistry.find("tug_of_war")
	var bot: TugOfWarBot = info.create_bot(BotOpponent.Difficulty.HARD) as TugOfWarBot
	add_child(bot)
	var player := PlayerInfo.new()
	player.player_name = "Tester"
	bot.info = player
	bot.begin_match(1)
	var game: TugOfWar = info.scene.instantiate() as TugOfWar
	add_child(game)
	var results: Array[int] = []
	game.finished.connect(func(outcome: MiniGame.Outcome, _stats: Dictionary) -> void: results.append(outcome))
	game.start_game(77, bot, "Rope", true, player)
	bot.start_match(77, "Rope")
	check(game._rope != null and game._rope_view != null and not game._field.visible, "Rope view shown")
	game._rope.fire()
	for i: int in 30:
		await get_tree().process_frame
	# Skip to the end of both clocks.
	game._rope.elapsed = RopeGame.MATCH_SEC - 0.01
	bot._rope.elapsed = RopeGame.MATCH_SEC - 0.01
	for i: int in 30:
		await get_tree().process_frame
	check_eq(results.size(), 1, "finished once")
	var bot_view: MiniGame.Outcome = RopeGame.result_for(bot._rope.knots)
	var expected: Dictionary = {MiniGame.Outcome.WIN: MiniGame.Outcome.LOSE, MiniGame.Outcome.LOSE: MiniGame.Outcome.WIN, MiniGame.Outcome.DRAW: MiniGame.Outcome.DRAW}
	if results.size() == 1:
		check_eq(results[0], expected[bot_view], "both sides agree on who won")
	for lane: int in RopeGame.LANES:
		check_eq(game._rope.knots[lane], -bot._rope.knots[lane], "lane %d agrees" % lane)
	game.queue_free()
	bot.queue_free()


func test_cannon_scene_runs_sideways() -> void:
	var info: GameInfo = GameRegistry.find("tug_of_war")
	var bot: TugOfWarBot = info.create_bot(BotOpponent.Difficulty.EASY) as TugOfWarBot
	add_child(bot)
	var player := PlayerInfo.new()
	player.player_name = "Tester"
	bot.info = player
	bot.begin_match(1)
	var game: TugOfWar = info.scene.instantiate() as TugOfWar
	add_child(game)
	game.start_game(5, bot, "Cannon", true, player)
	bot.start_match(5, "Cannon")
	check(game._game.cannon and not game._field.upright, "Cannon is sideways")
	game._game.fire()
	for i: int in 30:
		await get_tree().process_frame
	check(not game.is_finished(), "still playing")
	check(game._field.fuse >= 0.0, "fuse shown")
	game.queue_free()
	bot.queue_free()
