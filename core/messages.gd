class_name Messages
extends RefCounted
## Game messages between the two players. Each packet is
## [version, type, payload] packed with var_to_bytes. Payloads are small
## Dictionaries of plain values, never objects.

const PROTOCOL_VERSION: int = 1
const MAX_PACKET_BYTES: int = 4096

enum Type {
	HELLO = 1, ## {name: String, colour: int}, sent by both sides on connect.
	PING = 2, ## {t: int}, sender's ticks in msec.
	PONG = 3, ## {t: int}, echoed from the PING.
	GAME = 4, ## {n: match number, k: game-defined kind, d: Dictionary}. See RemoteOpponent.
	PICK = 5, ## {game: String, mode: String}, host only.
	READY = 6, ## {ready: bool, game: String, mode: String}. Ignored if it's for an older pick.
	START = 7, ## {seed: int, n: match number, game: String, mode: String}, host only.
	REMATCH = 8, ## {}, this player wants a rematch.
	TO_LOBBY = 9, ## {}, both go back to the game picker.
	HEARTBEAT = 10, ## {}, sent every second while connected so silence can be noticed.
}


static func encode(type: Type, payload: Dictionary = {}) -> PackedByteArray:
	return var_to_bytes([PROTOCOL_VERSION, type, payload])


## Returns {"type": int, "payload": Dictionary} for a good packet,
## {"error": "bad_version"} for another protocol version, or
## {"error": "bad_packet"} for anything malformed.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_PACKET_BYTES:
		return {"error": "bad_packet"}
	# bytes_to_var refuses to decode objects, so untrusted input is safe here.
	var data: Variant = bytes_to_var(bytes)
	if typeof(data) != TYPE_ARRAY:
		return {"error": "bad_packet"}
	var parts: Array = data
	if parts.size() != 3 or typeof(parts[0]) != TYPE_INT:
		return {"error": "bad_packet"}
	if parts[0] != PROTOCOL_VERSION:
		return {"error": "bad_version"}
	if typeof(parts[1]) != TYPE_INT or not Type.values().has(parts[1]) or typeof(parts[2]) != TYPE_DICTIONARY:
		return {"error": "bad_packet"}
	return {"type": parts[1], "payload": parts[2]}
