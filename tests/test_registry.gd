extends "res://tests/test_case.gd"


func test_finds_click_race() -> void:
	var game: GameInfo = GameRegistry.find("test_race")
	check(game != null, "test_race registered")
	if game != null:
		check(game.hidden, "test_race is hidden from release builds")


func test_every_game_is_complete() -> void:
	var games: Array[GameInfo] = GameRegistry.all_games()
	check(not games.is_empty(), "at least one game")
	for game: GameInfo in games:
		check(not game.display_name.is_empty(), "%s has a name" % game.id)
		check(not game.modes.is_empty(), "%s has a mode" % game.id)
		check(game.scene != null, "%s has a scene" % game.id)
		if game.scene != null:
			var root: Node = game.scene.instantiate()
			check(root is MiniGame, "%s scene root extends MiniGame" % game.id)
			root.free()
		check(game.bot_script != null, "%s has a bot" % game.id)
		if game.bot_script != null:
			for level: int in BotOpponent.Difficulty.values():
				var bot: BotOpponent = game.create_bot(level)
				check(bot != null and bot.difficulty == level, "%s makes a level %d bot" % [game.id, level])
				if bot != null:
					bot.free()
