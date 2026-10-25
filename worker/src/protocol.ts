// Signalling protocol between the game clients and a Room.
// JSON text frames over a WebSocket. See docs/signalling.md.

export const PROTOCOL_VERSION = 1;

// Room codes: 5 characters with look-alikes (I, L, O, 0, 1) left out.
export const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const CODE_LENGTH = 5;
export const CODE_PATTERN = /^[A-HJKMNP-Z2-9]{5}$/;

export const MAX_MESSAGE_BYTES = 16 * 1024;
export const MAX_SDP_LENGTH = 12 * 1024;
export const MAX_MESSAGES_PER_SOCKET = 100;

// WebSocket close codes (4000-4999 are free for applications).
export const Close = {
  EXPIRED: 4000,
  ROOM_FULL: 4001,
  BAD_MESSAGE: 4002,
  BAD_TOKEN: 4003,
  NO_SUCH_ROOM: 4004,
  BAD_VERSION: 4005,
  TOO_MANY_MESSAGES: 4029,
} as const;

export type Role = "host" | "guest";

// Messages a client sends, relayed as-is to the other peer.
export type RelayMessage =
  | { v: number; t: "offer"; sdp: string }
  | { v: number; t: "answer"; sdp: string }
  | { v: number; t: "ice"; media: string; index: number; name: string };

// Messages only the Room sends.
export type ServerMessage =
  | { v: number; t: "joined"; role: Role }
  | { v: number; t: "peer_joined" }
  | { v: number; t: "peer_left" }
  | { v: number; t: "error"; reason: string };

export type ParseResult =
  | { ok: true; msg: RelayMessage }
  | { ok: false; close: number; reason: string };

// Validates a client frame and rebuilds it so only known fields are relayed.
export function parseRelayMessage(raw: string, from: Role): ParseResult {
  const bad: ParseResult = { ok: false, close: Close.BAD_MESSAGE, reason: "bad_message" };
  let data: unknown;
  try {
    data = JSON.parse(raw);
  } catch {
    return bad;
  }
  if (typeof data !== "object" || data === null) return bad;
  const d = data as Record<string, unknown>;
  if (d.v !== PROTOCOL_VERSION) {
    return { ok: false, close: Close.BAD_VERSION, reason: "bad_version" };
  }
  const v = PROTOCOL_VERSION;
  switch (d.t) {
    case "offer":
    case "answer": {
      // The host always offers and the guest always answers.
      const expected: Role = d.t === "offer" ? "host" : "guest";
      if (from !== expected) return bad;
      if (typeof d.sdp !== "string" || d.sdp.length === 0 || d.sdp.length > MAX_SDP_LENGTH) return bad;
      return { ok: true, msg: { v, t: d.t, sdp: d.sdp } };
    }
    case "ice": {
      if (typeof d.media !== "string" || d.media.length > 64) return bad;
      if (typeof d.index !== "number" || !Number.isInteger(d.index) || d.index < 0 || d.index > 64) return bad;
      if (typeof d.name !== "string" || d.name.length === 0 || d.name.length > 1024) return bad;
      return { ok: true, msg: { v, t: "ice", media: d.media, index: d.index, name: d.name } };
    }
    default:
      return bad;
  }
}

export function encode(msg: RelayMessage | ServerMessage): string {
  return JSON.stringify(msg);
}

// Upgrades the request only to close it straight away with a reason the
// client can read (a plain HTTP error isn't visible to a WebSocket client).
export function rejectWebSocket(code: number, reason: string): Response {
  const pair = new WebSocketPair();
  const server = pair[1];
  server.accept();
  server.close(code, reason);
  return new Response(null, { status: 101, webSocket: pair[0] });
}
