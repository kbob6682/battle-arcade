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


func test_describe_candidate_hides_the_address() -> void:
	check_eq(Net.describe_candidate("candidate:1 1 udp 2122260223 4f2c9a1e-5b6d-4c3e-9f1a-2b3c4d5e6f70.local 54321 typ host generation 0"), "host udp mdns", "mDNS host")
	check_eq(Net.describe_candidate("candidate:2 1 UDP 1686052607 203.0.113.5 50000 typ srflx raddr 0.0.0.0 rport 0"), "srflx udp ipv4", "srflx")
	check_eq(Net.describe_candidate("candidate:3 1 tcp 1518280447 2001:db8::1 9 typ host tcptype active"), "host tcp ipv6", "IPv6 TCP host")
	check_eq(Net.describe_candidate("candidate:4 1 udp 41885439 198.51.100.7 3478 typ relay raddr 203.0.113.5 rport 50000"), "relay udp ipv4", "relay")
	check_eq(Net.describe_candidate(""), "unknown", "empty")
	check_eq(Net.describe_candidate("garbage"), "unknown", "garbage")
