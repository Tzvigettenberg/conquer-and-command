class_name RoomList
extends Node
## Public room list: hosts announce a named (optionally password-locked) room, everyone else sees
## it in the menu and joins with one click - no IPs to send around.
##
## Talks to a small JSON API of our own (see tools/room-api/), which is the only thing that ever
## sees a host's address: the list hands out names and player counts, and the address only comes
## back from /join once the password checks out. The API reads the host's public address from the
## request itself, so the game never has to ask a what-is-my-IP service. Hosts heartbeat every
## 10 s and a room that goes quiet for 45 s disappears by itself.
##
## SERVICE empty = this build has no room list: the menu says so and everyone joins by IP.
## Override at runtime with --room_api=https://host/path (handy for testing a new backend).

const SERVICE := ""
const HEARTBEAT := 10.0

signal rooms_changed(rooms: Array)
signal rooms_failed(message: String)
signal announced(ok: bool, message: String)
signal joined(ok: bool, ip: String, port: int, message: String)

var room_id := ""
var room_secret := ""
var rooms: Array = []
var _hb_t := 0.0
var _players := 1
var _started := false
var _pending_announce: Dictionary = {}

func base_url() -> String:
	var over := str(Main.I.args.get("room_api", "")) if Main.I != null else ""
	return (over if over != "" and over != "true" else SERVICE).trim_suffix("/")

func enabled() -> bool:
	return base_url() != ""

func _process(dt: float) -> void:
	if room_id == "":
		return
	_hb_t -= dt
	if _hb_t <= 0.0:
		_hb_t = HEARTBEAT
		_request("POST", "/rooms/%s/heartbeat" % room_id, {"secret": room_secret, "players": _players, "started": _started},
			func(ok: bool, body: Variant) -> void:
				if ok and body is Dictionary and not bool(body.get("ok", true)):
					# the backend forgot us (long hiccup): announce again
					room_id = ""
					if not _pending_announce.is_empty():
						announce(_pending_announce["name"], _pending_announce["password"], _pending_announce["max"], _pending_announce["port"]))

## Host: put this game on the list.
func announce(name: String, password: String, max_players: int, port: int) -> void:
	_pending_announce = {"name": name, "password": password, "max": max_players, "port": port}
	if not enabled():
		announced.emit(false, "This build has no room list - friends join by IP.")
		return
	_request("POST", "/rooms", {"name": name, "password": password, "max": max_players, "port": port, "version": Main.GAME_VERSION},
		func(ok: bool, body: Variant) -> void:
			if ok and body is Dictionary and body.has("id"):
				room_id = str(body["id"])
				room_secret = str(body["secret"])
				_hb_t = HEARTBEAT
				announced.emit(true, "Listed as \"%s\"%s" % [name, " (password)" if password != "" else ""])
			else:
				announced.emit(false, "Room list unavailable (%s) - friends can still join by IP." % str(body)))

func set_players(n: int, started: bool) -> void:
	if n != _players or started != _started:
		_players = n
		_started = started
		_hb_t = 0.0   # push the change right away

## Host: take the room down (leaving the lobby / quitting).
func close() -> void:
	_pending_announce = {}
	if room_id == "":
		return
	_request("POST", "/rooms/%s/close" % room_id, {"secret": room_secret}, func(_ok: bool, _b: Variant) -> void: pass)
	room_id = ""
	room_secret = ""

## Everyone: fetch the rooms running this version.
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

## Everyone: ask for a room's address (password checked by the server).
func join(id: String, password: String) -> void:
	_request("POST", "/rooms/%s/join" % id, {"password": password}, func(ok: bool, body: Variant) -> void:
		if not ok or not (body is Dictionary):
			joined.emit(false, "", 0, "Room list unavailable")
		elif body.has("error"):
			match str(body["error"]):
				"password":
					joined.emit(false, "", 0, "Wrong password")
				"started":
					joined.emit(false, "", 0, "That game has already started")
				_:
					joined.emit(false, "", 0, "That room is gone")
		else:
			joined.emit(true, str(body["ip"]), int(body["port"]), str(body.get("name", ""))))

## Honour HTTPS_PROXY / SSL_CERT_FILE so this works behind a corporate proxy or in a sandbox.
func _new_request(timeout: float) -> HTTPRequest:
	var req := HTTPRequest.new()
	req.timeout = timeout
	req.use_threads = true   # never let a slow frame (a big battle) time a lobby call out
	var proxy := OS.get_environment("HTTPS_PROXY")
	if proxy == "":
		proxy = OS.get_environment("https_proxy")
	if "127.0.0.1" in base_url() or "localhost" in base_url():
		proxy = ""   # a room API on this machine / LAN is not reached through a proxy
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
		cb.call(false, "no room list in this build")
		return
	var req := _new_request(8.0)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if Main.I.args.has("netdebug"):
			print("[Rooms] %s %s -> result %d code %d %s" % [method, path, result, code, body.get_string_from_utf8().left(120)])
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
