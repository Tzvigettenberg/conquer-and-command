# Open games list (room API)

The tiny service behind **Open games** in the main menu. Hosts announce a room, everyone else lists
rooms and joins one by clicking it - no IP addresses passed around by hand.

It is one Cloudflare Worker with one Durable Object and **no database**: a room lives only while its
host keeps heartbeating (every 10 s, dropped after 45 s of silence), so there is nothing to store,
nothing to clean up and nothing to leak. The host's address is never part of the listing - the Worker
reads it from the request itself and only hands it back from `/join`, after the password check.

## Deploy

```
npm install -g wrangler     # once
wrangler login              # opens a browser, free Cloudflare account
cd tools/room-api
wrangler deploy
```

Wrangler prints the URL, e.g. `https://cc-rooms.<your-subdomain>.workers.dev`. Put it in
`game/room_list.gd`:

```gdscript
const SERVICE := "https://cc-rooms.<your-subdomain>.workers.dev"
```

Rebuild and the menu lists games. Leaving `SERVICE` empty disables the feature cleanly: the menu says
so and everyone joins by IP. `--room_api=https://...` overrides it at runtime for testing.

Free plan limits are 100,000 requests a day; a lobby costs about 6 requests a minute per player, so
that is roughly 250 player-hours a day.

## API

| | | |
|---|---|---|
| `GET /rooms?version=0.3.0` | | `[{id, name, players, max_players, has_password, started, age_s}]` |
| `POST /rooms` | `{name, password, max, port, version}` | `{id, secret}` |
| `POST /rooms/:id/heartbeat` | `{secret, players, started}` | `{ok}` |
| `POST /rooms/:id/join` | `{password}` | `{ip, port, name}` or `{error: password\|started\|gone}` |
| `POST /rooms/:id/close` | `{secret}` | `{ok}` |
| `GET /health` | | `{ok, rooms}` |

Version is matched exactly, so a room only shows up for players on the same build.

## Test it locally

```
wrangler dev                 # http://127.0.0.1:8787
godot --path . -- --room_api=http://127.0.0.1:8787 --netdebug
```
