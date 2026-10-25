import {
  CODE_ALPHABET,
  CODE_LENGTH,
  CODE_PATTERN,
  Close,
  PROTOCOL_VERSION,
  rejectWebSocket,
} from "./protocol";

export { Room } from "./room";

const CREATE_ATTEMPTS = 5;
const WS_PATH = /^\/rooms\/([^/]+)\/ws$/;

// Routes:
//   POST /rooms               -> 201 {v, code, token}  (token proves the host)
//   GET  /rooms/{code}/ws     -> WebSocket into that Room (?token=... for the host)
export default {
  async fetch(request, env): Promise<Response> {
    const origin = request.headers.get("Origin");
    // Native (editor/desktop) clients send no Origin; browsers always do.
    if (origin !== null && !isAllowedOrigin(origin, env.ALLOWED_ORIGINS)) {
      return new Response("forbidden", { status: 403 });
    }
    const cors = corsHeaders(origin);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });

    const url = new URL(request.url);
    if (url.pathname === "/rooms") {
      if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405, cors);
      return createRoom(env, cors);
    }

    const match = WS_PATH.exec(url.pathname);
    if (match !== null) {
      if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
        return json({ error: "websocket_required" }, 426, cors);
      }
      const code = (match[1] ?? "").toUpperCase();
      if (!CODE_PATTERN.test(code)) return rejectWebSocket(Close.NO_SUCH_ROOM, "no_such_room");
      return env.ROOMS.get(env.ROOMS.idFromName(code)).fetch(request);
    }

    return json({ error: "not_found" }, 404, cors);
  },
} satisfies ExportedHandler<Env>;

async function createRoom(env: Env, cors: Headers): Promise<Response> {
  for (let i = 0; i < CREATE_ATTEMPTS; i++) {
    const code = newRoomCode();
    const token = await env.ROOMS.get(env.ROOMS.idFromName(code)).create();
    if (token !== null) return json({ v: PROTOCOL_VERSION, code, token }, 201, cors);
  }
  return json({ error: "no_free_code" }, 503, cors);
}

// Uniform random code: rejection sampling avoids bias from 256 % 31.
export function newRoomCode(): string {
  const n = CODE_ALPHABET.length;
  const limit = 256 - (256 % n);
  let code = "";
  while (code.length < CODE_LENGTH) {
    for (const b of crypto.getRandomValues(new Uint8Array(CODE_LENGTH * 2))) {
      if (b < limit && code.length < CODE_LENGTH) code += CODE_ALPHABET[b % n];
    }
  }
  return code;
}

export function isAllowedOrigin(origin: string, allowed: string): boolean {
  let host: string;
  try {
    host = new URL(origin).hostname;
  } catch {
    return false;
  }
  if (host === "localhost" || host === "127.0.0.1") return true;
  return allowed.split(",").map((o) => o.trim()).includes(origin);
}

function corsHeaders(origin: string | null): Headers {
  const h = new Headers();
  if (origin !== null) {
    h.set("Access-Control-Allow-Origin", origin);
    h.set("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
    h.set("Access-Control-Allow-Headers", "Content-Type");
    h.set("Vary", "Origin");
  }
  return h;
}

function json(body: unknown, status: number, headers: Headers): Response {
  const h = new Headers(headers);
  h.set("Content-Type", "application/json");
  return new Response(JSON.stringify(body), { status, headers: h });
}
