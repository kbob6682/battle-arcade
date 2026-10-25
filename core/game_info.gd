class_name GameInfo
extends Resource
## Describes one mini game for the lobby. Each game folder has a game_info.tres.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Root must have a script extending MiniGame.
@export var scene: PackedScene
@export var modes: PackedStringArray = PackedStringArray(["Normal"])
## Script extending BotOpponent.
@export var bot_script: GDScript
## Dev-only games are listed in debug builds only.
@export var hidden: bool = false


func create_bot(difficulty: BotOpponent.Difficulty) -> BotOpponent:
	var bot: BotOpponent = bot_script.new() as BotOpponent
	bot.difficulty = difficulty
	return bot
