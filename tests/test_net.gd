extends "res://tests/test_case.gd"


func test_debug_runs_use_the_local_worker() -> void:
	# Release builds get signalling_url.release; debug and editor runs must not.
	check_eq(Net.signalling_url(), "http://127.0.0.1:8787", "debug signalling URL")
	check(str(ProjectSettings.get_setting("battle_arcade/signalling_url.release", "")).begins_with("https://"), "release URL is set and uses https")


func test_keepalive_ping_matches_the_worker() -> void:
	# The Worker's auto-response only fires on identical text.
	var source: String = FileAccess.get_file_as_string("res://worker/src/protocol.ts")
	check(source.contains("export const PROTOCOL_VERSION = %d;" % SignallingClient.PROTOCOL_VERSION), "same protocol version")
	check(source.contains('PING_FRAME = `{"v":${PROTOCOL_VERSION},"t":"ping"}`'), "Worker PING_FRAME has the expected form")
	check_eq(SignallingClient.PING_FRAME, '{"v":%d,"t":"ping"}' % SignallingClient.PROTOCOL_VERSION, "ping text")
