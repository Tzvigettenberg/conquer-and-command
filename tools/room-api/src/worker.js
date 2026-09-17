// Conquer & Command: Zero Budget - the games list.
//
// Matches run on dedicated servers (see tools/server/), never on a player's PC, so nobody has to
// forward a port or know what an IP is. Each match server says hello here every few seconds with
// what it is doing; players ask for the list, or ask for a free one when they create a game.
//
// Everything lives in one Durable Object's memory: no database, nothing to clean up. A server that
// stops calling disappears after 45 s and re-registers on its next heartbeat. Room passwords are
// never sent here - the match server itself checks them when a player connects - so this only ever
// holds a room's name, its player count and the address of a public server.
//
// Endpoints (all JSON):
//   POST /servers   {port, version, secret, name, players, max, started, has_password}
//                                      -> {ok, claimed}   (match servers, every ~8 s)
//   POST /claim     {version}          -> {ip, port} | {error: "none_free"}   (a player creating a game)
//   GET  /rooms?version=0.3.3          -> [{id, name, players, max_players, has_password, started, ip, port, age_s}]
//   GET  /health                       -> {ok, servers, free, rooms}

const STALE_MS = 45_000;
const CLAIM_MS = 40_000; // long enough for the creator to connect and name the room
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
    return env.ROOMS.get(env.ROOMS.idFromName("global")).fetch(request);
  },
};

export class RoomRegistry {
  constructor(state) {
    this.state = state;
    this.servers = new Map(); // "ip:port" -> {...}
  }

  sweep() {
    const now = Date.now();
    for (const [key, s] of this.servers) if (now - s.seen > STALE_MS) this.servers.delete(key);
  }

  // a room is a match server that a player has named; a free server is one nobody is using yet
  isRoom(s) {
    return s.name !== "";
  }

  isFree(s, now) {
    return s.name === "" && !s.started && s.claimedUntil < now;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean);
    const body = request.method === "POST" ? await request.json().catch(() => ({})) : {};
    const now = Date.now();
    this.sweep();

    if (parts[0] === "health") {
      let free = 0;
      let rooms = 0;
      for (const s of this.servers.values()) {
        if (this.isFree(s, now)) free++;
        if (this.isRoom(s)) rooms++;
      }
      return json({ ok: true, servers: this.servers.size, free, rooms });
    }

    // ---- a match server checking in ----
    if (request.method === "POST" && parts[0] === "servers") {
      const ip =
        request.headers.get("cf-connecting-ip") ||
        (request.headers.get("x-forwarded-for") || "").split(",")[0].trim();
      const port = Number.isInteger(body.port) ? body.port : 0;
      if (!ip || !port) return json({ error: "bad_server" }, 400);
      const key = `${ip}:${port}`;
      const prev = this.servers.get(key);
      // the secret stops anyone else claiming to be this address:port
      if (prev && prev.secret !== body.secret) return json({ error: "not_yours" }, 403);
      this.servers.set(key, {
        ip,
        port,
        version: String(body.version ?? ""),
        secret: String(body.secret ?? ""),
        name: String(body.name ?? "").trim().slice(0, NAME_MAX),
        hasPassword: !!body.has_password,
        players: Number.isInteger(body.players) ? body.players : 0,
        max: Number.isInteger(body.max) ? body.max : 6,
        started: !!body.started,
        seen: now,
        since: prev && prev.name === String(body.name ?? "").trim() ? prev.since : now,
        claimedUntil: prev ? prev.claimedUntil : 0,
      });
      // tell the server it has been handed to someone, so it can expect them
      return json({ ok: true, claimed: (prev?.claimedUntil ?? 0) > now });
    }

    // ---- a player creating a game wants a free server ----
    if (request.method === "POST" && parts[0] === "claim") {
      const version = String(body.version ?? "");
      let best = null;
      for (const s of this.servers.values()) {
        if (s.version !== version || !this.isFree(s, now)) continue;
        if (!best || s.seen > best.seen) best = s;
      }
      if (!best) return json({ error: "none_free" });
      best.claimedUntil = now + CLAIM_MS;
      return json({ ip: best.ip, port: best.port });
    }

    // ---- the games list ----
    if (request.method === "GET" && parts[0] === "rooms") {
      const version = url.searchParams.get("version") || "";
      const out = [];
      for (const [key, s] of this.servers) {
        if (!this.isRoom(s) || (version && s.version !== version)) continue;
        out.push({
          id: key,
          name: s.name,
          players: s.players,
          max_players: s.max,
          has_password: s.hasPassword,
          started: s.started,
          ip: s.ip,
          port: s.port,
          age_s: Math.round((now - s.since) / 1000),
        });
      }
      out.sort((a, b) => a.age_s - b.age_s);
      return json(out.slice(0, 50));
    }

    return json({ error: "not_found" }, 404);
  }
}
