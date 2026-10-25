extends "res://tests/test_case.gd"


func test_name_rules() -> void:
	for good: String in ["Bob", "Caleb_2", "a-b", "ABCDEFGHIJKLMNOP"]:
		check(PlayerInfo.is_valid_name(good), "should accept '%s'" % good)
	for bad: String in ["", "ab", "ABCDEFGHIJKLMNOPQ", "bad name", "émile", "<b>", "x;y"]:
		check(not PlayerInfo.is_valid_name(bad), "should reject '%s'" % bad)


func test_from_dict_validates_untrusted_input() -> void:
	var good: PlayerInfo = PlayerInfo.from_dict({"name": "Bob", "colour": 2})
	check(good != null, "valid HELLO accepted")
	if good != null:
		check_eq(good.player_name, "Bob", "name")
		check_eq(good.colour_index, 2, "colour")
	check(PlayerInfo.from_dict({}) == null, "empty rejected")
	check(PlayerInfo.from_dict({"name": "Bob", "colour": 99}) == null, "colour out of range rejected")
	check(PlayerInfo.from_dict({"name": "Bob", "colour": -1}) == null, "negative colour rejected")
	check(PlayerInfo.from_dict({"name": "no spaces", "colour": 0}) == null, "bad name rejected")
	check(PlayerInfo.from_dict({"name": 5, "colour": 0}) == null, "name of wrong type rejected")
