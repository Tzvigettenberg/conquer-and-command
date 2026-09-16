class_name Main
extends Node3D
## Entry point: main menu, host/join lobby, then hands over to Session + ClientView.

const PORT := 7788
const GAME_VERSION := "0.1.0"
const MAX_PLAYERS := 2

static var I: Main = null

var session: Session
var view: Node = null
var menu: CanvasLayer
var status_label: Label
var name_edit: LineEdit
var ip_edit: LineEdit
var lobby_box: VBoxContainer
var lobby_list: Label
var start_btn: Button
var menu_box: VBoxContainer
var args: Dictionary = {}
var lobby_players: Array = []      # server: [{peer, name}]
var in_lobby := false
var game_started := false
var my_name := "Commander"

func _ready() -> void:
	I = self
	session = Session.new()
	session.name = "Session"
	add_child(session)
	_parse_args()
	_build_menu()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_conn_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if args.has("name"):
		my_name = args["name"]
		name_edit.text = my_name
	if args.has("host"):
		_host()
	elif args.has("join"):
		ip_edit.text = args["join"]
		_join()

func _parse_args() -> void:
	var all := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a in all:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else true

# ---------------------------------------------------------------------------
# Menu UI
# ---------------------------------------------------------------------------
func _build_menu() -> void:
	menu = CanvasLayer.new()
	menu.layer = 5
	add_child(menu)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := Label.new()
	title.text = "FRONTLINE"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "1v1 RTS  ·  v%s" % GAME_VERSION
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(0.7, 0.7, 0.7)
	v.add_child(sub)

	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 8)
	v.add_child(menu_box)
	menu_box.add_child(_label("Callsign"))
	name_edit = LineEdit.new()
	name_edit.text = my_name
	name_edit.placeholder_text = "Your name"
	menu_box.add_child(name_edit)
	menu_box.add_child(_label("Host address (for Join)"))
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "IP or hostname"
	menu_box.add_child(ip_edit)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	menu_box.add_child(h)
	var host_btn := Button.new()
	host_btn.text = "Host game"
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(_host)
	h.add_child(host_btn)
	var join_btn := Button.new()
	join_btn.text = "Join game"
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(_join)
	h.add_child(join_btn)
	var help := Label.new()
	help.text = "Host: share your IP (port %d must be reachable - forward it or use the same LAN / a VPN).\nJoin: enter the host's IP and click Join." % PORT
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(0.6, 0.6, 0.6)
	help.add_theme_font_size_override("font_size", 12)
	menu_box.add_child(help)

	lobby_box = VBoxContainer.new()
	lobby_box.add_theme_constant_override("separation", 8)
	lobby_box.visible = false
	v.add_child(lobby_box)
	lobby_list = Label.new()
	lobby_list.text = ""
	lobby_box.add_child(lobby_list)
	start_btn = Button.new()
	start_btn.text = "Start game"
	start_btn.pressed.connect(_on_start_pressed)
	lobby_box.add_child(start_btn)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(_leave)
	lobby_box.add_child(leave)

	status_label = Label.new()
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(status_label)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	v.add_child(quit)

func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.modulate = Color(0.8, 0.8, 0.8)
	return l

func _set_status(t: String) -> void:
	status_label.text = t
	print("[Main] " + t)

# ---------------------------------------------------------------------------
# Host / join
# ---------------------------------------------------------------------------
func _host() -> void:
	my_name = name_edit.text.strip_edges()
	if my_name == "":
		my_name = "Host"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS + 2)
	if err != OK:
		_set_status("Could not open port %d (error %d). Is another copy running?" % [PORT, err])
		return
	multiplayer.multiplayer_peer = peer
	lobby_players = [{"peer": 1, "name": my_name}]
	_show_lobby(true)
	_set_status("Hosting on port %d. Waiting for an opponent... (you can also start solo to practice)" % PORT)
	_refresh_lobby()
	if args.has("autostart") and args.has("solo"):
		_start_game()

func _join() -> void:
	my_name = name_edit.text.strip_edges()
	if my_name == "":
		my_name = "Guest"
	var ip := ip_edit.text.strip_edges()
	if ip == "":
		_set_status("Enter the host's IP address first.")
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		_set_status("Could not start client (error %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	_show_lobby(false)
	_set_status("Connecting to %s..." % ip)

func _leave() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	lobby_players.clear()
	_show_lobby(false)
	lobby_box.visible = false
	menu_box.visible = true
	_set_status("")

func _show_lobby(is_host: bool) -> void:
	in_lobby = true
	menu_box.visible = false
	lobby_box.visible = true
	start_btn.visible = is_host
	start_btn.text = "Start game"

func _refresh_lobby() -> void:
	var text := "Players:\n"
	for p in lobby_players:
		text += "  · %s%s\n" % [p["name"], " (host)" if p["peer"] == 1 else ""]
	if lobby_players.size() < 2:
		text += "  · (waiting for opponent)\n"
	lobby_list.text = text
	if multiplayer.is_server():
		start_btn.text = "Start game" if lobby_players.size() >= 2 else "Start solo (sandbox)"
		for p in lobby_players:
			if p["peer"] != 1:
				session.rpc_id(p["peer"], "cl_lobby", lobby_players, text)
		if args.has("autostart") and lobby_players.size() >= 2 and not game_started:
			_start_game()

func on_lobby(players: Array, text: String) -> void:
	lobby_players = players
	lobby_list.text = text

func on_kick(reason: String) -> void:
	_set_status(reason)
	_leave()

func _on_peer_connected(id: int) -> void:
	print("[Main] peer connected ", id)
	if not multiplayer.is_server():
		return
	# wait for hello (name/version) before adding

func on_client_hello(peer: int, pname: String, version: String) -> void:
	if not multiplayer.is_server():
		return
	if version != GAME_VERSION:
		session.rpc_id(peer, "cl_kick", "Version mismatch: host %s, you %s" % [GAME_VERSION, version])
		return
	if game_started or lobby_players.size() >= MAX_PLAYERS:
		session.rpc_id(peer, "cl_kick", "Game is full or already started")
		return
	lobby_players.append({"peer": peer, "name": pname})
	_set_status("%s joined." % pname)
	_refresh_lobby()

func _on_peer_disconnected(id: int) -> void:
	print("[Main] peer disconnected ", id)
	if multiplayer.is_server():
		for i in range(lobby_players.size()):
			if lobby_players[i]["peer"] == id:
				var nm: String = lobby_players[i]["name"]
				if game_started:
					if view:
						view.on_msg("%s disconnected" % nm)
				else:
					lobby_players.remove_at(i)
					_set_status("%s left." % nm)
					_refresh_lobby()
				break

func _on_connected() -> void:
	_set_status("Connected. Waiting for host to start...")
	session.rpc_id(1, "srv_hello", my_name, GAME_VERSION)

func _on_conn_failed() -> void:
	_set_status("Connection failed. Check the IP and that the host's port %d is reachable." % PORT)
	_leave()

func _on_server_disconnected() -> void:
	if view:
		view.on_msg("Host disconnected")
		view.on_gameover(-2)
	else:
		_set_status("Host disconnected.")
		_leave()

func _on_start_pressed() -> void:
	if multiplayer.is_server():
		_start_game()

# ---------------------------------------------------------------------------
# Game start
# ---------------------------------------------------------------------------
func _start_game() -> void:
	if game_started or not multiplayer.is_server():
		return
	game_started = true
	var peers := []
	var names := []
	for p in lobby_players:
		peers.append(p["peer"])
		names.append(p["name"])
	var w := World.new()
	w.debug = args.has("debug")
	session.world = w
	w.start(session, peers, names)   # sends cl_map to everyone, including the host locally

## Called (via Session.cl_map) on every peer once the server has built the map.
func begin_game(map: Dictionary, player_index: int) -> void:
	game_started = true
	menu.visible = false
	if view == null:
		var cv_script: GDScript = load("res://game/client/client_view.gd")
		view = cv_script.new()
		view.name = "ClientView"
		add_child(view)
		session.view = view
	view.setup(map, player_index, lobby_players, args)

func return_to_menu() -> void:
	if view:
		view.queue_free()
		view = null
		session.view = null
	session.world = null
	game_started = false
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	lobby_players.clear()
	menu.visible = true
	lobby_box.visible = false
	menu_box.visible = true
	in_lobby = false
	_set_status("")
