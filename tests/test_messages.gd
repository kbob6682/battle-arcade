extends "res://tests/test_case.gd"


func test_round_trip_every_type() -> void:
	for type: int in Messages.Type.values():
		var msg: Dictionary = Messages.decode(Messages.encode(type, {"a": 1, "b": "x"}))
		check_eq(msg.get("type"), type, "type %d" % type)
		check_eq(msg.get("payload"), {"a": 1, "b": "x"}, "payload of type %d" % type)


func test_wrong_version_is_flagged() -> void:
	var bytes: PackedByteArray = var_to_bytes([Messages.PROTOCOL_VERSION + 1, Messages.Type.PING, {}])
	check_eq(Messages.decode(bytes), {"error": "bad_version"}, "newer version")


func test_malformed_packets_are_rejected() -> void:
	var v: int = Messages.PROTOCOL_VERSION
	var oversize := PackedByteArray()
	oversize.resize(Messages.MAX_PACKET_BYTES + 1)
	var cases: Dictionary = {
		"empty": PackedByteArray(),
		"oversize": oversize,
		"not an array": var_to_bytes("hello"),
		"too short": var_to_bytes([v, Messages.Type.PING]),
		"unknown type": var_to_bytes([v, 999, {}]),
		"payload not a dict": var_to_bytes([v, Messages.Type.PING, "x"]),
		"version not an int": var_to_bytes(["1", Messages.Type.PING, {}]),
	}
	for label: String in cases:
		check_eq(Messages.decode(cases[label]), {"error": "bad_packet"}, label)
