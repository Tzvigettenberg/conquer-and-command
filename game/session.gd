class_name Session
extends Node
## RPC hub. Exists at the same path on every peer. The host owns the World;
## every peer (host included) owns a ClientView that renders replicated state.

var world: World = null
var view: Node = null
var my_peer := 1
var tick_accum := 0.0

func _ready() -> void:
	my_peer = multiplayer.get_unique_id()

func _physics_process(_delta: float) -> void:
	if world != null and not world.paused:
		world.step(World.TICK)

# ---------------------------------------------------------------------------
# client -> server
# ---------------------------------------------------------------------------
func send_cmd(c: Dictionary) -> void:
	if world != null:
		world.cmd(world.player_of_peer(my_peer), c)
	else:
		rpc_id(1, "srv_cmd", c)

@rpc("any_peer", "call_remote", "reliable")
func srv_cmd(c: Dictionary) -> void:
	if world == null:
		return
	var peer := multiplayer.get_remote_sender_id()
	world.cmd(world.player_of_peer(peer), c)

# ---------------------------------------------------------------------------
# server -> client helpers (local delivery for the host)
# ---------------------------------------------------------------------------
func _to(peer: int, method: StringName, args: Array) -> void:
	if peer == my_peer:
		callv(method, args)
	elif multiplayer.get_peers().has(peer):
		callv("rpc_id", [peer, method] + args)

func s_spawn(peer: int, id: int, type: String, owner: int, x: float, y: float, alt: float, yaw: float, extra: Dictionary) -> void:
	_to(peer, "cl_spawn", [id, type, owner, x, y, alt, yaw, extra])

func s_despawn(peer: int, id: int, reason: String) -> void:
	_to(peer, "cl_despawn", [id, reason])

func s_state(peer: int, bytes: PackedByteArray) -> void:
	_to(peer, "cl_state", [bytes])

func s_events(peer: int, evs: Array) -> void:
	_to(peer, "cl_events", [evs])

func s_fog(peer: int, bytes: PackedByteArray) -> void:
	_to(peer, "cl_fog", [bytes])

func s_pstate(peer: int, st: Dictionary) -> void:
	_to(peer, "cl_pstate", [st])

func s_map(peer: int, map: Dictionary, player_index: int) -> void:
	_to(peer, "cl_map", [map, player_index])

func s_msg(peer: int, text: String) -> void:
	_to(peer, "cl_msg", [text])

func s_gameover(winner: int, rep: Array) -> void:
	for p in world.players:
		_to(p["peer"], "cl_gameover", [winner, rep])
	for ob in world.observers:
		_to(ob["peer"], "cl_gameover", [winner, rep])

func s_paused(on: bool) -> void:
	for p in world.players:
		_to(p["peer"], "cl_paused", [on])
	for ob in world.observers:
		_to(ob["peer"], "cl_paused", [on])

# ---------------------------------------------------------------------------
# server -> client RPCs
# ---------------------------------------------------------------------------
@rpc("authority", "call_remote", "reliable")
func cl_map(map: Dictionary, player_index: int) -> void:
	get_parent().begin_game(map, player_index)

@rpc("authority", "call_remote", "reliable")
func cl_spawn(id: int, type: String, owner: int, x: float, y: float, alt: float, yaw: float, extra: Dictionary) -> void:
	if view:
		view.on_spawn(id, type, owner, Vector2(x, y), alt, yaw, extra)

@rpc("authority", "call_remote", "reliable")
func cl_despawn(id: int, reason: String) -> void:
	if view:
		view.on_despawn(id, reason)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func cl_state(bytes: PackedByteArray) -> void:
	if view:
		view.on_state(bytes)

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func cl_events(evs: Array) -> void:
	if view:
		view.on_events(evs)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func cl_fog(bytes: PackedByteArray) -> void:
	if view:
		view.on_fog(bytes)

@rpc("authority", "call_remote", "reliable")
func cl_pstate(st: Dictionary) -> void:
	if view:
		view.on_pstate(st)

@rpc("authority", "call_remote", "reliable")
func cl_msg(text: String) -> void:
	if view:
		view.on_msg(text)

@rpc("authority", "call_remote", "reliable")
func cl_gameover(winner: int, rep: Array) -> void:
	if view:
		view.on_gameover(winner, rep)

@rpc("authority", "call_remote", "reliable")
func cl_paused(on: bool) -> void:
	if view:
		view.on_paused(on)

# ---------------------------------------------------------------------------
# lobby
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func srv_hello(name: String, version: String, room_name := "", room_pw := "") -> void:
	get_parent().on_client_hello(multiplayer.get_remote_sender_id(), name, version, room_name, room_pw)

@rpc("any_peer", "call_remote", "reliable")
func srv_lobby(c: Dictionary) -> void:
	get_parent().on_lobby_cmd(multiplayer.get_remote_sender_id(), c)

## In-game chat: relayed by the host to everyone (or allies only).
@rpc("any_peer", "call_remote", "reliable")
func srv_chat(text: String, allies: bool) -> void:
	if world == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	var from := world.player_of_peer(sender)
	if from < 0 and world.is_observer(sender):
		relay_chat(-1, "[%s] %s" % [get_parent().peer_name(sender), text], false)
		return
	relay_chat(from, text, allies)

## from == -1 is an observer (name folded into the text), heard by everyone.
func relay_chat(from: int, text: String, allies: bool) -> void:
	if world == null:
		return
	for i in range(world.players.size()):
		var p: Dictionary = world.players[i]
		if int(p["peer"]) < 0:
			continue
		if allies and from >= 0 and not world.allied(from, i):
			continue
		_to(int(p["peer"]), "cl_chat", [from, text, allies])
	for ob in world.observers:
		if allies and from >= 0:
			continue
		_to(int(ob["peer"]), "cl_chat", [from, text, allies])

@rpc("authority", "call_remote", "reliable")
func cl_chat(from: int, text: String, allies: bool) -> void:
	if view:
		view.on_chat(from, text, allies)

@rpc("authority", "call_remote", "reliable")
func cl_lobby(players: Array, opts: Dictionary) -> void:
	get_parent().on_lobby(players, opts)

@rpc("authority", "call_remote", "reliable")
func cl_kick(reason: String) -> void:
	get_parent().on_kick(reason)
