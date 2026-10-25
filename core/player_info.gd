class_name PlayerInfo
extends RefCounted
## A player's name and colour. Saved locally so it's remembered between visits.

const NAME_MIN: int = 3
const NAME_MAX: int = 16
const NAME_RULE: String = "3 to 16 letters, numbers, - or _"
const SAVE_PATH: String = "user://player.cfg"

const COLOURS: Array[Color] = [
	Color("#e74c3c"), # red
	Color("#e67e22"), # orange
	Color("#f1c40f"), # yellow
	Color("#2ecc71"), # green
	Color("#1abc9c"), # teal
	Color("#3498db"), # blue
	Color("#9b59b6"), # purple
	Color("#ff6fb5"), # pink
]

static var _name_regex: RegEx

var player_name: String = ""
var colour_index: int = 0


static func is_valid_name(text: String) -> bool:
	if _name_regex == null:
		_name_regex = RegEx.create_from_string("^[A-Za-z0-9_-]{%d,%d}$" % [NAME_MIN, NAME_MAX])
	return _name_regex.search(text) != null


func get_colour() -> Color:
	return COLOURS[colour_index]


## The HELLO payload sent to the opponent.
func to_dict() -> Dictionary:
	return {"name": player_name, "colour": colour_index}


## Builds a PlayerInfo from an untrusted HELLO payload, or null if invalid.
static func from_dict(data: Dictionary) -> PlayerInfo:
	var player_name_value: Variant = data.get("name")
	var colour_value: Variant = data.get("colour")
	if typeof(player_name_value) != TYPE_STRING or typeof(colour_value) != TYPE_INT:
		return null
	if not is_valid_name(player_name_value) or colour_value < 0 or colour_value >= COLOURS.size():
		return null
	var info := PlayerInfo.new()
	info.player_name = player_name_value
	info.colour_index = colour_value
	return info


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "colour", colour_index)
	cfg.save(SAVE_PATH)


static func load_saved() -> PlayerInfo:
	var info := PlayerInfo.new()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return info
	var saved_name: Variant = cfg.get_value("player", "name", "")
	var saved_colour: Variant = cfg.get_value("player", "colour", 0)
	if typeof(saved_name) == TYPE_STRING and is_valid_name(saved_name):
		info.player_name = saved_name
	if typeof(saved_colour) == TYPE_INT and saved_colour >= 0 and saved_colour < COLOURS.size():
		info.colour_index = saved_colour
	return info
