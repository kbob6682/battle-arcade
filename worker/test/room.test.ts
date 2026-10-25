import { env, runDurableObjectAlarm } from "cloudflare:test";
import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { isAllowedOrigin, newRoomCode } from "../src/index";
import { CODE_PATTERN, Close, PROTOCOL_VERSION } from "../src/protocol";

const BASE = "https://signal.test";
const v = PROTOCOL_VERSION;

// A test client: queues incoming JSON messages and records how it closed.
class Client {
  private queue: unknown[] = [];
  private waiters: ((msg: unknown) => void)[] = [];
  closed: Promise<{ code: number; reason: string }>;

  constructor(readonly ws: WebSocket) {
    this.closed = new Promise((resolve) => {
      ws.addEventListener("close", (e) => resolve({ code: e.code, reason: e.reason }));
    });
    ws.addEventListener("message", (e) => {
      const msg: unknown = JSON.parse(e.data as string);
      const waiter = this.waiters.shift();
      if (waiter) waiter(msg);
      else this.queue.push(msg);
    });
    ws.accept();
  }

  next(): Promise<unknown> {
    if (this.queue.length > 0) return Promise.resolve(this.queue.shift());
    return new Promise((resolve) => this.waiters.push(resolve));
  }

  send(msg: unknown): void {
    this.ws.send(typeof msg === "string" ? msg : JSON.stringify(msg));
  }
}

async function createRoom(): Promise<{ code: string; token: string }> {
  const res = await exports.default.fetch(`${BASE}/rooms`, { method: "POST" });
  expect(res.status).toBe(201);
  return (await res.json()) as { code: string; token: string };
}

async function connect(code: string, token?: string): Promise<Client> {
  const query = token === undefined ? "" : `?token=${token}`;
  const res = await exports.default.fetch(`${BASE}/rooms/${code}/ws${query}`, {
    headers: { Upgrade: "websocket" },
  });
  expect(res.status).toBe(101);
  return new Client(res.webSocket!);
}

// Host and guest connected, with the join messages already read.
async function pairUp(): Promise<{ code: string; host: Client; guest: Client }> {
  const { code, token } = await createRoom();
  const host = await connect(code, token);
  expect(await host.next()).toEqual({ v, t: "joined", role: "host" });
  const guest = await connect(code);
  expect(await guest.next()).toEqual({ v, t: "joined", role: "guest" });
  expect(await guest.next()).toEqual({ v, t: "peer_joined" });
  expect(await host.next()).toEqual({ v, t: "peer_joined" });
  return { code, host, guest };
}

describe("room codes", () => {
  it("are 5 characters with no look-alikes", () => {
    for (let i = 0; i < 200; i++) expect(newRoomCode()).toMatch(CODE_PATTERN);
  });

  it("POST /rooms returns a code and host token", async () => {
    const { code, token } = await createRoom();
    expect(code).toMatch(CODE_PATTERN);
    expect(token).toMatch(/^[0-9a-f]{32}$/);
  });

  it("joins case-insensitively", async () => {
    const { code, token } = await createRoom();
    await connect(code, token);
    const guest = await connect(code.toLowerCase());
    expect(await guest.next()).toEqual({ v, t: "joined", role: "guest" });
  });
});

describe("signalling relay", () => {
  it("relays offer, answer and ICE both ways", async () => {
    const { host, guest } = await pairUp();
    host.send({ v, t: "offer", sdp: "v=0 offer" });
    expect(await guest.next()).toEqual({ v, t: "offer", sdp: "v=0 offer" });
    guest.send({ v, t: "answer", sdp: "v=0 answer" });
    expect(await host.next()).toEqual({ v, t: "answer", sdp: "v=0 answer" });
    const ice = { v, t: "ice", media: "0", index: 0, name: "candidate:1 1 udp 1 192.0.2.1 5000 typ host" };
    host.send(ice);
    expect(await guest.next()).toEqual(ice);
    guest.send(ice);
    expect(await host.next()).toEqual(ice);
  });

  it("drops unknown fields when relaying", async () => {
    const { host, guest } = await pairUp();
    host.send({ v, t: "offer", sdp: "x", extra: "nope" });
    expect(await guest.next()).toEqual({ v, t: "offer", sdp: "x" });
  });

  it("tells the sender when there's no peer yet", async () => {
    const { code, token } = await createRoom();
    const host = await connect(code, token);
    await host.next();
    host.send({ v, t: "offer", sdp: "x" });
    expect(await host.next()).toEqual({ v, t: "error", reason: "no_peer" });
  });

  it("tells the other peer when someone leaves", async () => {
    const { host, guest } = await pairUp();
    guest.ws.close(1000, "bye");
    expect(await host.next()).toEqual({ v, t: "peer_left" });
  });

  it("refuses new players once a pair has met, even after they leave", async () => {
    const { code, host, guest } = await pairUp();
    guest.ws.close(1000, "bye");
    host.ws.close(1000, "bye");
    await guest.closed;
    await host.closed;
    const late = await connect(code);
    expect(await late.closed).toEqual({ code: Close.ROOM_FULL, reason: "room_full" });
  });

  it("refuses a guest when the host isn't in the room", async () => {
    const { code } = await createRoom();
    const guest = await connect(code);
    expect(await guest.closed).toEqual({ code: Close.NO_SUCH_ROOM, reason: "no_such_room" });
  });
});

describe("rejections", () => {
  it("closes a third player with room_full", async () => {
    const { code } = await pairUp();
    const extra = await connect(code);
    expect(await extra.closed).toEqual({ code: Close.ROOM_FULL, reason: "room_full" });
  });

  it("closes an unknown code with no_such_room", async () => {
    let code = newRoomCode();
    const extra = await connect(code);
    expect(await extra.closed).toEqual({ code: Close.NO_SUCH_ROOM, reason: "no_such_room" });
    code = "!!!!!";
    const junk = await connect(code);
    expect(await junk.closed).toEqual({ code: Close.NO_SUCH_ROOM, reason: "no_such_room" });
  });

  it("closes a wrong host token with bad_token", async () => {
    const { code } = await createRoom();
    const fake = await connect(code, "0".repeat(32));
    expect(await fake.closed).toEqual({ code: Close.BAD_TOKEN, reason: "bad_token" });
  });

  it("closes on invalid JSON", async () => {
    const { host } = await pairUp();
    host.send("not json");
    expect(await host.closed).toEqual({ code: Close.BAD_MESSAGE, reason: "bad_message" });
  });

  it("only lets the host offer and the guest answer", async () => {
    const { guest } = await pairUp();
    guest.send({ v, t: "offer", sdp: "x" });
    expect(await guest.closed).toEqual({ code: Close.BAD_MESSAGE, reason: "bad_message" });
  });

  it("closes on a protocol version mismatch", async () => {
    const { host } = await pairUp();
    host.send({ v: v + 1, t: "offer", sdp: "x" });
    expect(await host.closed).toEqual({ code: Close.BAD_VERSION, reason: "bad_version" });
  });

  it("closes a socket that sends too many messages", async () => {
    const { host } = await pairUp();
    for (let i = 0; i < 101; i++) host.send({ v, t: "ice", media: "0", index: 0, name: "c" });
    expect(await host.closed).toEqual({ code: Close.TOO_MANY_MESSAGES, reason: "too_many_messages" });
  });

  it("requires a WebSocket upgrade", async () => {
    const res = await exports.default.fetch(`${BASE}/rooms/ABCDE/ws`);
    expect(res.status).toBe(426);
  });
});

describe("expiry", () => {
  it("closes sockets and frees the code when the alarm fires", async () => {
    const { code, host, guest } = await pairUp();
    const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
    expect(await runDurableObjectAlarm(stub)).toBe(true);
    expect(await host.closed).toEqual({ code: Close.EXPIRED, reason: "expired" });
    expect(await guest.closed).toEqual({ code: Close.EXPIRED, reason: "expired" });
    const late = await connect(code);
    expect(await late.closed).toEqual({ code: Close.NO_SUCH_ROOM, reason: "no_such_room" });
  });
});

describe("origins", () => {
  it("allows localhost, listed origins and native clients", async () => {
    expect(isAllowedOrigin("http://localhost:8060", "")).toBe(true);
    expect(isAllowedOrigin("http://127.0.0.1:5500", "")).toBe(true);
    expect(isAllowedOrigin("https://kbob6682.github.io", env.ALLOWED_ORIGINS)).toBe(true);
    const native = await exports.default.fetch(`${BASE}/rooms`, { method: "POST" });
    expect(native.status).toBe(201);
  });

  it("rejects other websites", async () => {
    expect(isAllowedOrigin("https://evil.example", env.ALLOWED_ORIGINS)).toBe(false);
    const res = await exports.default.fetch(`${BASE}/rooms`, {
      method: "POST",
      headers: { Origin: "https://evil.example" },
    });
    expect(res.status).toBe(403);
  });

  it("answers CORS preflight with the caller's origin", async () => {
    const res = await exports.default.fetch(`${BASE}/rooms`, {
      method: "OPTIONS",
      headers: { Origin: "http://localhost:8060" },
    });
    expect(res.status).toBe(204);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBe("http://localhost:8060");
  });
});
