class_name RoomList
extends Node
## The games list. Matches run on dedicated servers (tools/server/), so players only ever make
## outgoing connections - there is nothing to forward and no address to type.
##
## Two roles use this:
##   a match server  - serve(port) registers it and keeps saying what it is doing
##   a player        - claim() asks for a free server to create a game on, refresh() lists the
##                     games that are up, and each row already carries the address to connect to
##
## Room passwords never leave the game: the list only says whether a room has one, and the match
## server itself checks it when a player connects.
##
## SERVICE empty = no list in this build (offline skirmish and LAN still work).
## Override at runtime with --room_api=https://host/path.

const SERVICE := "https://cc-rooms.zerobudget.workers.dev"
const HEARTBEAT := 8.0

signal rooms_changed(rooms: Array)
signal rooms_failed(message: String)
signal claimed(ok: bool, ip: String, port: int, message: String)

var rooms: Array = []
# ---- match-server side ----
var serving_port := 0
var secret := ""
var room_name := ""
var has_password := false
var players := 0
var max_players := 6
var started := false
var _hb_due := 0.0

func base_url() -> String:
	var over := str(Main.I.args.get("room_api", "")) if Main.I != null else ""
	return (over if over != "" and over != "true" else SERVICE).trim_suffix("/")

func enabled() -> bool:
	return base_url() != ""

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

## Heartbeats run off the clock, never off frame deltas: a machine under load can lose most of its
## process time, and a server that misses two heartbeats drops out of everyone's list.
func _process(_dt: float) -> void:
	if serving_port == 0 or not enabled():
		return
	if _now() >= _hb_due:
		_hb_due = _now() + HEARTBEAT
		_request("POST", "/servers", {
			"port": serving_port, "version": Main.GAME_VERSION, "secret": secret,
			"name": room_name, "has_password": has_password,
			"players": players, "max": max_players, "started": started,
		}, func(_ok: bool, _body: Variant) -> void: pass)

# ---------------------------------------------------------------------------
# Match server
# ---------------------------------------------------------------------------
## Start telling the list about this match server.
func serve(port: int) -> void:
	serving_port = port
	if secret == "":
		secret = "%d-%d" % [Time.get_unix_time_from_system(), randi()]
	_hb_due = 0.0

## What this server is doing right now (pushed on the next heartbeat, which is due immediately).
func set_room(name: String, with_password: bool) -> void:
	room_name = name
	has_password = with_password
	_hb_due = 0.0

func set_players(n: int, in_match: bool) -> void:
	if n != players or in_match != started:
		players = n
		started = in_match
		_hb_due = 0.0

## Back to an empty server that anyone may claim.
func free_server() -> void:
	set_room("", false)
	set_players(0, false)

# ---------------------------------------------------------------------------
# Player
# ---------------------------------------------------------------------------
## Ask for a free match server to create a game on.
func claim() -> void:
	if not enabled():
		claimed.emit(false, "", 0, "This build has no games list.")
		return
	_request("POST", "/claim", {"version": Main.GAME_VERSION}, func(ok: bool, body: Variant) -> void:
		if ok and body is Dictionary and body.has("ip"):
			claimed.emit(true, str(body["ip"]), int(body["port"]), "")
		elif ok and body is Dictionary and str(body.get("error", "")) == "none_free":
			claimed.emit(false, "", 0, "Every game server is busy right now. Try again in a minute, or play a skirmish against the AI.")
		else:
			claimed.emit(false, "", 0, "Could not reach the games list (%s)." % str(body)))

## The games that are up right now.
func refresh() -> void:
	if not enabled():
		rooms_failed.emit("off")
		return
	_request("GET", "/rooms?version=" + Main.GAME_VERSION.uri_encode(), {}, func(ok: bool, body: Variant) -> void:
		if ok and body is Array:
			rooms = body
			rooms_changed.emit(rooms)
		else:
			rooms_failed.emit(str(body)))

# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------
## Honour HTTPS_PROXY / SSL_CERT_FILE so this works behind a company proxy or in a sandbox.
func _new_request(timeout: float) -> HTTPRequest:
	var req := HTTPRequest.new()
	req.timeout = timeout
	req.use_threads = true   # a slow frame must never time a lobby call out
	var proxy := OS.get_environment("HTTPS_PROXY")
	if proxy == "":
		proxy = OS.get_environment("https_proxy")
	if "127.0.0.1" in base_url() or "localhost" in base_url():
		proxy = ""
	if proxy != "":
		var hp := proxy.trim_prefix("http://").trim_prefix("https://").trim_suffix("/").split(":")
		if hp.size() == 2:
			req.set_https_proxy(hp[0], int(hp[1]))
			req.set_http_proxy(hp[0], int(hp[1]))
	var ca := OS.get_environment("SSL_CERT_FILE")
	if ca != "" and base_url().begins_with("https://") and FileAccess.file_exists(ca):
		var cert := X509Certificate.new()
		if cert.load(ca) == OK:
			req.set_tls_options(TLSOptions.client(cert))
	add_child(req)
	return req

func _request(method: String, path: String, params: Dictionary, cb: Callable) -> void:
	if not enabled():
		cb.call(false, "no games list in this build")
		return
	var req := _new_request(8.0)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if Main.I.args.has("netdebug"):
			print("[Rooms] t=%.1fs %s %s -> result %d code %d %s" % [_now(), method, path, result, code, body.get_string_from_utf8().left(100)])
		if result != HTTPRequest.RESULT_SUCCESS:
			cb.call(false, "no connection")
			return
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if code < 200 or code >= 300:
			cb.call(false, str(parsed.get("error", code)) if parsed is Dictionary else str(code))
			return
		cb.call(true, parsed))
	var headers := PackedStringArray(["Content-Type: application/json"])
	var verb := HTTPClient.METHOD_GET if method == "GET" else HTTPClient.METHOD_POST
	if req.request(base_url() + path, headers, verb, "" if method == "GET" else JSON.stringify(params)) != OK:
		req.queue_free()
		cb.call(false, "request failed")
