extends "res://tests/test_case.gd"


func test_messages_wait_until_the_game_attaches() -> void:
	var opponent := Opponent.new()
	add_child(opponent)
	var got: Array = []
	opponent.game_message.connect(func(kind: int, data: Dictionary) -> void: got.append([kind, data]))
	opponent.begin_match(1)
	opponent._deliver(7, {"x": 1})
	check(got.is_empty(), "held before attach")
	opponent.attach()
	check_eq(got, [[7, {"x": 1}]], "delivered on attach")
	opponent._deliver(8, {})
	check_eq(got.size(), 2, "delivered straight away once attached")


func test_new_match_drops_held_messages() -> void:
	var opponent := Opponent.new()
	add_child(opponent)
	var got: Array = []
	opponent.game_message.connect(func(kind: int, _data: Dictionary) -> void: got.append(kind))
	opponent.begin_match(1)
	opponent._deliver(7, {})
	opponent.begin_match(2)
	opponent.attach()
	check(got.is_empty(), "stale message dropped")


func test_click_race_bot_plays_and_concedes() -> void:
	var bot: TestRaceBot = GameRegistry.find("test_race").create_bot(BotOpponent.Difficulty.HARD) as TestRaceBot
	add_child(bot)
	var got: Array = []
	bot.game_message.connect(func(kind: int, data: Dictionary) -> void: got.append([kind, data]))
	bot.begin_match(1)
	bot.attach()
	bot.start_match(1234, "Normal")
	check(got.is_empty(), "bot replies are not instant")
	var hit: bool = await wait_until(func() -> bool: return not got.is_empty(), 2.0)
	check(hit, "bot hit a target within 2 s")
	if hit:
		check_eq(got[0], [TestRace.Kind.HIT, {"n": 1}], "first message is HIT 1")
	bot.send_game(TestRace.Kind.DONE, {"t": 5})
	var conceded: bool = await wait_until(func() -> bool: return got.any(func(m: Array) -> bool: return m[0] == TestRace.Kind.CONCEDE), 1.0)
	check(conceded, "bot concedes when the player finishes first")
