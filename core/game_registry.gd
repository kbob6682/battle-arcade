class_name GameRegistry
extends RefCounted
## Finds every mini game: each folder in res://games that has a game_info.tres.
## Adding a game means adding a folder; no lobby or network code changes.

const GAMES_DIR: String = "res://games"
const INFO_FILE: String = "game_info.tres"

static var _games: Array[GameInfo] = []
static var _loaded: bool = false


static func all_games() -> Array[GameInfo]:
	if not _loaded:
		_games = scan(GAMES_DIR)
		_loaded = true
	return _games


## Games for the picker. Hidden (dev-only) games appear in debug builds, and in
## release builds exported with the "playtest" feature tag.
static func visible_games() -> Array[GameInfo]:
	return filter_visible(all_games(), OS.is_debug_build() or OS.has_feature("playtest"))


static func filter_visible(games: Array[GameInfo], show_hidden: bool) -> Array[GameInfo]:
	var result: Array[GameInfo] = []
	for game: GameInfo in games:
		if show_hidden or not game.hidden:
			result.append(game)
	return result


static func find(id: String) -> GameInfo:
	for game: GameInfo in all_games():
		if game.id == id:
			return game
	return null


static func scan(dir: String) -> Array[GameInfo]:
	var found: Array[GameInfo] = []
	var ids: Dictionary = {}
	for folder: String in DirAccess.get_directories_at(dir):
		var path: String = "%s/%s/%s" % [dir, folder, INFO_FILE]
		# ResourceLoader.exists also follows the .remap files of exported builds.
		if not ResourceLoader.exists(path):
			continue
		var game: GameInfo = load(path) as GameInfo
		if game == null or game.id.is_empty():
			push_warning("Skipping %s: not a GameInfo with an id" % path)
			continue
		if ids.has(game.id):
			push_error("Duplicate game id '%s' in %s" % [game.id, path])
			continue
		ids[game.id] = true
		found.append(game)
	found.sort_custom(func(a: GameInfo, b: GameInfo) -> bool: return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return found
