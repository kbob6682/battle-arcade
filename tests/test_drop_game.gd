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
	var expected: Array[float] = [0.8, 0.526, 0.346, 0.228, 0.15]
	for step: int in expected.size():
		game.elapsed = step * DropGame.SPEEDUP_EVERY_SEC + 1.0
		check(absf(game.fall_interval() - expected[step]) < 0.002, "step %d at %d s: %.3f" % [step, int(game.elapsed), game.fall_interval()])
	game.elapsed = DropGame.SPEEDUP_EVERY_SEC - 0.1
	check(is_equal_approx(game.fall_interval(), DropGame.BASE_FALL_SEC), "no change before 45 s")
	game.elapsed = 100000.0
	check(is_equal_approx(game.fall_interval(), DropGame.SUDDEN_DEATH_FALL_SEC), "never faster than sudden death")


func test_bot_tops_out_under_junk_and_says_so() -> void:
	var bot: GemBattleBot = GameRegistry.find("gem_battle").create_bot(BotOpponent.Difficulty.EASY) as GemBattleBot
	var got: Array[int] = []
	bot.game_message.connect(func(kind: int, _data: Dictionary) -> void: got.append(kind))
	bot.begin_match(1)
	bot.attach()
	bot.start_match(1234, "Drop")
	# Simulate up to 20 minutes of play without waiting for it.
	for i: int in 24000:
		# Keep it buried in junk so even a good bot tops out.
		if bot._game.incoming == 0:
			bot._game.add_incoming(GemBoard.MAX_ATTACK)
		bot._process(0.05)
		if bot._game.is_topped():
			break
	check(bot._game.is_topped(), "tops out under constant junk")
	await get_tree().process_frame
	check(got.has(GemBattle.Kind.BOARD), "sent board snapshots")
	check_eq(got.back(), GemBattle.Kind.TOPPED, "TOPPED is the last message")
	check_eq(got.count(GemBattle.Kind.TOPPED), 1, "TOPPED sent once")
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
	(game._game as DropGame).hard_drop()
	for i: int in 10:
		await get_tree().process_frame
	check(not game.is_finished(), "still playing")
	game.queue_free()
	bot.queue_free()


func test_arrows_and_wasd_both_work() -> void:
	var expected: Dictionary = {
		"gem_left": [KEY_LEFT, KEY_A],
		"gem_right": [KEY_RIGHT, KEY_D],
		"gem_soft_drop": [KEY_DOWN, KEY_S],
		"gem_rotate_cw": [KEY_X, KEY_UP, KEY_W],
		"gem_rotate_ccw": [KEY_Z],
		"gem_hard_drop": [KEY_SPACE],
	}
	for action: String in expected:
		var keys: Array = []
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				keys.append((event as InputEventKey).physical_keycode)
		check_eq(keys, expected[action], action)


func test_mouse_buttons_rotate() -> void:
	# Left click turns the pair left (anticlockwise), right click turns it right.
	var expected: Dictionary = {"gem_rotate_ccw": MOUSE_BUTTON_LEFT, "gem_rotate_cw": MOUSE_BUTTON_RIGHT}
	for action: String in expected:
		var buttons: Array = []
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventMouseButton:
				buttons.append((event as InputEventMouseButton).button_index)
		check_eq(buttons, [expected[action]], action)
		var click := InputEventMouseButton.new()
		click.button_index = expected[action]
		click.pressed = true
		check(click.is_action_pressed(action), "%s matches a click" % action)


func test_a_chain_blocks_incoming_junk_first() -> void:
	var game: DropGame = started()
	var sent: Array[int] = []
	game.attack_sent.connect(func(amount: int) -> void: sent.append(amount))
	game.add_incoming(5)
	game.board.set_cell(0, GemBoard.HEIGHT - 1, 1)
	game.piece_colours = [1, 1]
	game.move(-1)
	game.move(-1)
	game.hard_drop()
	settle(game)
	check(sent.is_empty(), "a single clear (2 junk) only blocks")
	check_eq(game.incoming, 0, "the other 3 dropped")
	check_eq(junk_on(game.board), 3, "3 junk on the board")


func test_a_chain_with_nothing_incoming_attacks() -> void:
	var game: DropGame = started()
	var sent: Array[int] = []
	game.attack_sent.connect(func(amount: int) -> void: sent.append(amount))
	game.board.set_cell(0, GemBoard.HEIGHT - 1, 1)
	game.piece_colours = [1, 1]
	game.move(-1)
	game.move(-1)
	game.hard_drop()
	settle(game)
	check_eq(sent, [2] as Array[int], "a single clear sends 2 junk")


func test_junk_drops_at_most_three_rows_per_landing() -> void:
	var game: DropGame = started()
	game.add_incoming(30)
	game.piece_colours = [1, 2]
	game.hard_drop()
	settle(game)
	check_eq(junk_on(game.board), DropGame.MAX_JUNK_PER_LANDING, "18 dropped")
	check_eq(game.incoming, 30 - DropGame.MAX_JUNK_PER_LANDING, "12 still waiting")


func test_sudden_death_speeds_everything_up() -> void:
	var game: DropGame = started()
	game.elapsed = DropGame.SUDDEN_DEATH_SEC - 1.0
	check(not game.is_sudden_death(), "not yet")
	check(game.fall_interval() > DropGame.SUDDEN_DEATH_FALL_SEC, "still slower before")
	game.elapsed = DropGame.SUDDEN_DEATH_SEC
	check(game.is_sudden_death(), "sudden death at 3:00")
	check(game.fall_interval() <= DropGame.SUDDEN_DEATH_FALL_SEC, "fast after")


func test_both_players_agree_when_both_top_out() -> void:
	check_eq(GemBattle.topped_result(1000, 2000), MiniGame.Outcome.LOSE, "topped first: lose")
	check_eq(GemBattle.topped_result(2000, 1000), MiniGame.Outcome.WIN, "topped second: win")
	check_eq(GemBattle.topped_result(1500, 1500), MiniGame.Outcome.DRAW, "same time: draw")


func junk_on(b: GemBoard) -> int:
	var count: int = 0
	for value: int in b.cells:
		if value == GemBoard.JUNK:
			count += 1
	return count


func test_clear_words_show_the_bonus() -> void:
	check_eq(GemEffects.clear_word(3), "Nice!", "3 gems")
	check_eq(GemEffects.clear_word(4), "Great! +1", "4 gems")
	check_eq(GemEffects.clear_word(5), "Awesome! +2", "5 gems")
	check_eq(GemEffects.clear_word(7), "Amazing! +4", "7 gems")


func test_effects_run_without_errors() -> void:
	var grid := GemGridView.new()
	grid.size = Vector2(240, 480)
	add_child(grid)
	var effects := GemEffects.new()
	grid.add_child(effects)
	effects.grid = grid
	var groups: Array[PackedInt32Array] = [PackedInt32Array([66, 67, 68, 69])]
	effects.show_clear(3, groups, [2] as Array[int])
	effects.show_attack(8)
	for i: int in 30:
		await get_tree().process_frame
	grid.queue_free()
