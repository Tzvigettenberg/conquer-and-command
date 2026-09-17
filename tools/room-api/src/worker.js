// Conquer & Command: Zero Budget - open games list.
//
// A room is just a name, a player count and the host's address, alive only while the host keeps
// saying so (heartbeat every 10 s, dropped after 45 s of silence). Everything lives in one
// Durable Object's memory: no database, nothing to clean up, and if the object ever restarts the
// hosts re-announce on their next heartbeat. The host's address is never listed - it is read from
// the request itself and only handed back by /join, after the password checks out.
//
// Endpoints (all JSON):
//   GET  /rooms?version=0.3.0            -> [{id, name, players, max_players, has_password, started, age_s}]
//   POST /rooms                          {name, password, max, port, version} -> {id, secret}
//   POST /rooms/:id/heartbeat            {secret, players, started}           -> {ok}
//   POST /rooms/:id/join                 {password}                           -> {ip, port, name} | {error}
//   POST /rooms/:id/unreachable          {}                                   -> {ok}   (a joiner could not connect)
//   POST /rooms/:id/close                {secret}                             -> {ok}
//   GET  /health                         -> {ok, rooms}

const STALE_MS = 45_000;
const MAX_ROOMS = 200;
const NAME_MAX = 40;

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "content-type",
  "access-control-allow-methods": "GET,POST,OPTIONS",
};

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...CORS },
  });

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    const id = env.ROOMS.idFromName("global");
    return env.ROOMS.get(id).fetch(request);
  },
};

export class RoomRegistry {
  constructor(state) {
    this.state = state;
    this.rooms = new Map(); // id -> {name, ip, port, version, players, max, started, password, secret, created, seen}
  }

  sweep() {
    const now = Date.now();
    for (const [id, r] of this.rooms) if (now - r.seen > STALE_MS) this.rooms.delete(id);
  }

  async fetch(request) {
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean); // rooms[/:id[/action]]
    const body = request.method === "POST" ? await request.json().catch(() => ({})) : {};
    this.sweep();

    if (parts[0] === "health") return json({ ok: true, rooms: this.rooms.size });
    if (parts[0] !== "rooms") return json({ error: "not_found" }, 404);

    // ---- GET /rooms?version=x : names and counts only, never an address ----
    if (request.method === "GET" && parts.length === 1) {
      const version = url.searchParams.get("version") || "";
      const now = Date.now();
      const out = [];
      for (const [id, r] of this.rooms) {
        if (version && r.version !== version) continue;
        out.push({
          id,
          name: r.name,
          players: r.players,
          max_players: r.max,
          has_password: !!r.password,
          started: r.started,
          age_s: Math.round((now - r.created) / 1000),
        });
      }
      out.sort((a, b) => a.age_s - b.age_s);
      return json(out.slice(0, 50));
    }

    // ---- POST /rooms : announce ----
    if (request.method === "POST" && parts.length === 1) {
      if (this.rooms.size >= MAX_ROOMS) return json({ error: "full" }, 503);
      const ip =
        request.headers.get("cf-connecting-ip") ||
        (request.headers.get("x-forwarded-for") || "").split(",")[0].trim();
      if (!ip) return json({ error: "no_address" }, 400);
      const name = String(body.name ?? "").trim().slice(0, NAME_MAX) || "Unnamed game";
      const port = Number.isInteger(body.port) ? Math.min(Math.max(body.port, 1), 65535) : 7788;
      const max = Number.isInteger(body.max) ? Math.min(Math.max(body.max, 2), 8) : 6;
      const id = crypto.randomUUID();
      const secret = crypto.randomUUID().replace(/-/g, "");
      const now = Date.now();
      this.rooms.set(id, {
        name,
        ip,
        port,
        version: String(body.version ?? ""),
        players: 1,
        max,
        started: false,
        password: body.password ? String(body.password) : "",
        secret,
        created: now,
        seen: now,
      });
      return json({ id, secret });
    }

    const room = parts.length >= 2 ? this.rooms.get(parts[1]) : null;
    const action = parts[2] || "";

    // a joiner got the address but nothing answered: the host is the one who can fix that,
    // so park a count for them to pick up on their next heartbeat
    if (request.method === "POST" && action === "unreachable") {
      if (room) room.unreachable = (room.unreachable || 0) + 1;
      return json({ ok: true });
    }

    if (request.method === "POST" && action === "join") {
      if (!room) return json({ error: "gone" });
      if (room.password && String(body.password ?? "") !== room.password) return json({ error: "password" });
      if (room.started) return json({ error: "started" });
      return json({ ip: room.ip, port: room.port, name: room.name });
    }

    // the rest need the host's secret
    if (!room || body.secret !== room.secret) return json({ ok: false });

    if (request.method === "POST" && action === "heartbeat") {
      room.seen = Date.now();
      room.players = Number.isInteger(body.players) ? Math.max(1, body.players) : room.players;
      room.started = !!body.started;
      // tell the host once about anyone who found the room but could not reach the port
      const unreachable = room.unreachable || 0;
      room.unreachable = 0;
      return json({ ok: true, unreachable });
    }
    if (request.method === "POST" && action === "close") {
      this.rooms.delete(parts[1]);
      return json({ ok: true });
    }
    return json({ error: "not_found" }, 404);
  }
}
