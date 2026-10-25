# Signalling protocol (v1)

The Worker in `worker/` pairs two players by room code and relays WebRTC
signalling between them. It never carries game traffic: once the data channel
is up, both clients close their WebSocket.

## HTTP

| Request | Response |
|---|---|
| `POST /rooms` | `201 {"v":1,"code":"K7QX4","token":"<32 hex>"}`. `token` proves the host. Keep it in memory only. |
| `GET /rooms/{code}/ws` | WebSocket upgrade. Add `?token=...` to join as host; without it you join as guest. Codes are case-insensitive. |

Browsers must come from an allowed origin (`ALLOWED_ORIGINS` in `wrangler.jsonc`, plus `localhost`/`127.0.0.1` on any port). Native clients (editor/desktop) send no `Origin` and are allowed.

Room codes are 5 characters from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no I, L, O, 0, 1). A room lasts 10 minutes from creation, then closes every socket and frees the code.

## WebSocket messages

JSON text frames. Every message carries `v` (protocol version) and `t` (type).

From the Room:

| `t` | Fields | Meaning |
|---|---|---|
| `joined` | `role`: `"host"` or `"guest"` | You're in the room. |
| `peer_joined` | | The other player is here. The host sends its offer now. |
| `peer_left` | | The other player's socket closed. |
| `error` | `reason`: `"no_peer"` | Sent a relay message with no one to receive it. |

Relayed between players (the Room validates each one and forwards only these fields):

| `t` | Fields | Who sends it |
|---|---|---|
| `offer` | `sdp` | Host only |
| `answer` | `sdp` | Guest only |
| `ice` | `media`, `index`, `name` | Both. These match Godot's `WebRTCPeerConnection.ice_candidate_created(media, index, name)`. |

## Close codes

| Code | Reason | When |
|---|---|---|
| 4000 | `expired` | The room's 10 minutes are up. |
| 4001 | `room_full` | That role is already taken (a third player tried to join). |
| 4002 | `bad_message` | Not JSON, an unknown type, a bad field, or the wrong role (e.g. a guest offering). |
| 4003 | `bad_token` | Wrong host token. |
| 4004 | `no_such_room` | The code doesn't exist, has expired, or is malformed. |
| 4005 | `bad_version` | `v` doesn't match the Worker's protocol version. |
| 4029 | `too_many_messages` | More than 100 messages on one socket. |

## Connection sequence

1. Host: `POST /rooms`, then open `/rooms/{code}/ws?token=...` and get `joined(host)`.
2. Guest: open `/rooms/{code}/ws` and get `joined(guest)` + `peer_joined`. The host gets `peer_joined`.
3. Host creates the offer and sends `offer`. Guest replies with `answer`. Both send `ice` as candidates appear.
4. When the WebRTC data channel opens, both close the WebSocket (1000).

## Limits and costs

Free plan only. A match uses roughly 3 Worker requests plus a few Durable Object requests, and the hibernating WebSockets don't bill duration while idle.
