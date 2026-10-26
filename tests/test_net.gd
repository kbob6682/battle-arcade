extends "res://tests/test_case.gd"


func test_debug_runs_use_the_local_worker() -> void:
	# Release builds get signalling_url.release; debug and editor runs must not.
	check_eq(Net.signalling_url(), "http://127.0.0.1:8787", "debug signalling URL")
	check(str(ProjectSettings.get_setting("battle_arcade/signalling_url.release", "")).begins_with("https://"), "release URL is set and uses https")
