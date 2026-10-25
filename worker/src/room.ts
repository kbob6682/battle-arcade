import { DurableObject } from "cloudflare:workers";
import {
  Close,
  MAX_MESSAGE_BYTES,
  MAX_MESSAGES_PER_SOCKET,
  PROTOCOL_VERSION,
  encode,
  parseRelayMessage,
  rejectWebSocket,
  type Role,
  type ServerMessage,
} from "./protocol";

export const ROOM_TTL_MS = 10 * 60 * 1000;

interface Attachment {
  role: Role;
  count: number;
}

// One Room per room code. Holds at most a host and a guest, relays WebRTC
// signalling between them, and deletes itself after ROOM_TTL_MS.
// Uses hibernatable WebSockets, so an idle room isn't billed for duration.
export class Room extends DurableObject<Env> {
  // Claims this room. Returns the host token, or null if the code is taken.
  async create(): Promise<string | null> {
    if ((await this.ctx.storage.get<string>("host_token")) !== undefined) return null;
    const token = randomHex(16);
    await this.ctx.storage.put("host_token", token);
    await this.ctx.storage.setAlarm(Date.now() + ROOM_TTL_MS);
    return token;
  }

  async fetch(request: Request): Promise<Response> {
    const hostToken = await this.ctx.storage.get<string>("host_token");
    if (hostToken === undefined) return rejectWebSocket(Close.NO_SUCH_ROOM, "no_such_room");

    const token = new URL(request.url).searchParams.get("token");
    if (token !== null && token !== hostToken) return rejectWebSocket(Close.BAD_TOKEN, "bad_token");
    const role: Role = token === null ? "guest" : "host";
    // Once a host and guest have met, the room is used up: they close their
    // sockets after connecting peer-to-peer, and nobody else may take a slot.
    if ((await this.ctx.storage.get<boolean>("paired")) === true || this.ctx.getWebSockets(role).length > 0) {
      return rejectWebSocket(Close.ROOM_FULL, "room_full");
    }
    // Only the host's game holds the token, so a room without its host can't
    // complete. Tell the guest straight away instead of letting them wait.
    if (role === "guest" && this.peer(role) === null) {
      return rejectWebSocket(Close.NO_SUCH_ROOM, "no_such_room");
    }

    const pair = new WebSocketPair();
    const server = pair[1];
    this.ctx.acceptWebSocket(server, [role]);
    server.serializeAttachment({ role, count: 0 } satisfies Attachment);
    send(server, { v: PROTOCOL_VERSION, t: "joined", role });

    const other = this.peer(role);
    if (other !== null) {
      await this.ctx.storage.put("paired", true);
      send(other, { v: PROTOCOL_VERSION, t: "peer_joined" });
      send(server, { v: PROTOCOL_VERSION, t: "peer_joined" });
    }
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const att = ws.deserializeAttachment() as Attachment;
    att.count += 1;
    ws.serializeAttachment(att);
    if (att.count > MAX_MESSAGES_PER_SOCKET) {
      ws.close(Close.TOO_MANY_MESSAGES, "too_many_messages");
      return;
    }
    if (typeof message !== "string" || message.length > MAX_MESSAGE_BYTES) {
      ws.close(Close.BAD_MESSAGE, "bad_message");
      return;
    }
    const result = parseRelayMessage(message, att.role);
    if (!result.ok) {
      ws.close(result.close, result.reason);
      return;
    }
    const other = this.peer(att.role);
    if (other === null) {
      send(ws, { v: PROTOCOL_VERSION, t: "error", reason: "no_peer" });
      return;
    }
    other.send(encode(result.msg));
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    const role = (ws.deserializeAttachment() as Attachment).role;
    const other = this.peer(role);
    if (other !== null) send(other, { v: PROTOCOL_VERSION, t: "peer_left" });
    try {
      ws.close(code, reason);
    } catch {
      // Already closed, or a reserved code (1005/1006) that can't be echoed.
    }
  }

  async alarm(): Promise<void> {
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.close(Close.EXPIRED, "expired");
      } catch {
        // Already closing.
      }
    }
    await this.ctx.storage.deleteAll();
  }

  private peer(role: Role): WebSocket | null {
    const otherRole: Role = role === "host" ? "guest" : "host";
    return this.ctx.getWebSockets(otherRole)[0] ?? null;
  }
}

function send(ws: WebSocket, msg: ServerMessage): void {
  ws.send(encode(msg));
}

function randomHex(bytes: number): string {
  const buf = crypto.getRandomValues(new Uint8Array(bytes));
  return Array.from(buf, (b) => b.toString(16).padStart(2, "0")).join("");
}
