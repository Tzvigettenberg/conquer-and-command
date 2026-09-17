class_name Main
extends Node3D
## Entry point: main menu, host/join lobby, then hands over to Session + ClientView.

const PORT := 7788
const GAME_VERSION := "0.1.0"
const MAX_PLAYERS := 4

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
var lobby_rows: VBoxContainer
var opt_ai: OptionButton
var opt_ai_level: OptionButton
var opt_map: OptionButton
var opt_cash: OptionButton
var opt_sw: CheckButton
var lobby_opts := {"ai": 1, "ai_level": "medium", "map": "desert", "cash": 10000, "superweapons": true}
var menu_box: VBoxContainer
var args: Dictionary = {}
var lobby_players: Array = []      # server: [{peer, name}]
var in_lobby := false
var game_started := false
var my_name := "Commander"
var port := PORT

func _ready() -> void:
	I = self
	session = Session.new()
	session.name = "Session"
	add_child(session)
	var audio := Audio.new()
	audio.name = "Audio"
	add_child(audio)
	_parse_args()
	if args.has("port"):
		port = int(args["port"])
	if not args.has("headless_audio_off"):
		audio.play_music("menu")
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
	sub.text = "Generals-style RTS  ·  v%s" % GAME_VERSION
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
	lobby_list.text = "PLAYERS"
	lobby_list.add_theme_font_size_override("font_size", 12)
	lobby_list.modulate = Color(0.7, 0.75, 0.8)
	lobby_box.add_child(lobby_list)
	lobby_rows = VBoxContainer.new()
	lobby_box.add_child(lobby_rows)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	lobby_box.add_child(grid)
	grid.add_child(_label("Map"))
	opt_map = OptionButton.new()
	for k in ["desert", "snow", "grass"]:
		opt_map.add_item(MapGen.THEMES[k]["name"])
		opt_map.set_item_metadata(opt_map.item_count - 1, k)
	opt_map.item_selected.connect(func(_i: int) -> void: _opts_changed())
	grid.add_child(opt_map)
	grid.add_child(_label("AI opponents"))
	opt_ai = OptionButton.new()
	for i in range(4):
		opt_ai.add_item(str(i))
	opt_ai.select(1)
	opt_ai.item_selected.connect(func(_i: int) -> void: _opts_changed())
	grid.add_child(opt_ai)
	grid.add_child(_label("AI difficulty"))
	opt_ai_level = OptionButton.new()
	for k in ["easy", "medium", "hard"]:
		opt_ai_level.add_item(k.capitalize())
		opt_ai_level.set_item_metadata(opt_ai_level.item_count - 1, k)
	opt_ai_level.select(1)
	opt_ai_level.item_selected.connect(func(_i: int) -> void: _opts_changed())
	grid.add_child(opt_ai_level)
	grid.add_child(_label("Starting cash"))
	opt_cash = OptionButton.new()
	for c in [5000, 10000, 20000, 50000]:
		opt_cash.add_item("$%d" % c)
		opt_cash.set_item_metadata(opt_cash.item_count - 1, c)
	opt_cash.select(1)
	opt_cash.item_selected.connect(func(_i: int) -> void: _opts_changed())
	grid.add_child(opt_cash)
	grid.add_child(_label("Superweapons"))
	opt_sw = CheckButton.new()
	opt_sw.button_pressed = true
	opt_sw.toggled.connect(func(_on: bool) -> void: _opts_changed())
	grid.add_child(opt_sw)
	var invite := Label.new()
	invite.text = "Invite: send friends your IP (port %d). Up to %d players + AI." % [PORT, MAX_PLAYERS]
	invite.add_theme_font_size_override("font_size", 12)
	invite.modulate = Color(0.6, 0.6, 0.6)
	lobby_box.add_child(invite)
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
	var err := peer.create_server(port, MAX_PLAYERS + 2)
	if err != OK:
		_set_status("Could not open port %d (error %d). Is another copy running?" % [PORT, err])
		return
	multiplayer.multiplayer_peer = peer
	lobby_players = [{"peer": 1, "name": my_name}]
	_show_lobby(true)
	_set_status("Hosting on port %d. Waiting for players... (or start with AI opponents)" % port)
	_refresh_lobby()
	if args.has("autostart") and (args.has("solo") or args.has("bot") or args.has("ai")):
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
	var err := peer.create_client(ip, port)
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
	for c in [opt_map, opt_ai, opt_ai_level, opt_cash, opt_sw]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_STOP if is_host else Control.MOUSE_FILTER_IGNORE
		(c as Control).modulate = Color.WHITE if is_host else Color(0.7, 0.7, 0.7)
	start_btn.text = "Start game"

func _opts_changed() -> void:
	lobby_opts = {
		"ai": opt_ai.selected, "ai_level": opt_ai_level.get_item_metadata(opt_ai_level.selected),
		"map": opt_map.get_item_metadata(opt_map.selected), "cash": opt_cash.get_item_metadata(opt_cash.selected),
		"superweapons": opt_sw.button_pressed,
	}
	_refresh_lobby()

func _apply_opts_ui() -> void:
	for i in range(opt_map.item_count):
		if opt_map.get_item_metadata(i) == lobby_opts["map"]:
			opt_map.select(i)
	opt_ai.select(clampi(int(lobby_opts["ai"]), 0, 3))
	for i in range(opt_ai_level.item_count):
		if opt_ai_level.get_item_metadata(i) == lobby_opts["ai_level"]:
			opt_ai_level.select(i)
	for i in range(opt_cash.item_count):
		if int(opt_cash.get_item_metadata(i)) == int(lobby_opts["cash"]):
			opt_cash.select(i)
	opt_sw.button_pressed = bool(lobby_opts["superweapons"])

func _refresh_lobby() -> void:
	for c in lobby_rows.get_children():
		c.queue_free()
	var is_host := multiplayer.is_server()
	var ai_n := clampi(int(lobby_opts["ai"]), 0, MAX_PLAYERS - lobby_players.size())
	for i in range(lobby_players.size()):
		var p: Dictionary = lobby_players[i]
		var h := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(14, 14)
		sw.color = Data.TEAM_COLORS[i % Data.TEAM_COLORS.size()]
		h.add_child(sw)
		var l := Label.new()
		l.text = "  %s%s" % [p["name"], "  (host)" if p["peer"] == 1 else ""]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		if is_host and p["peer"] != 1:
			var kick := Button.new()
			kick.text = "Kick"
			kick.pressed.connect(func() -> void: _kick(p["peer"]))
			h.add_child(kick)
		lobby_rows.add_child(h)
	for i in range(ai_n):
		var h := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(14, 14)
		sw.color = Data.TEAM_COLORS[(lobby_players.size() + i) % Data.TEAM_COLORS.size()]
		h.add_child(sw)
		var l := Label.new()
		l.text = "  AI General (%s)" % str(lobby_opts["ai_level"]).capitalize()
		h.add_child(l)
		lobby_rows.add_child(h)
	if lobby_players.size() + ai_n < 2:
		var l := Label.new()
		l.text = "  (waiting for an opponent - or start solo to practice)"
		l.modulate = Color(0.6, 0.6, 0.6)
		lobby_rows.add_child(l)
	if is_host:
		start_btn.text = "Start game" if lobby_players.size() + ai_n >= 2 else "Start solo (sandbox)"
		for p in lobby_players:
			if p["peer"] != 1:
				session.rpc_id(p["peer"], "cl_lobby", lobby_players, lobby_opts)
		if args.has("autostart") and lobby_players.size() >= 2 and not game_started:
			_start_game()

func _kick(peer: int) -> void:
	session.rpc_id(peer, "cl_kick", "You were removed from the lobby by the host")
	for i in range(lobby_players.size()):
		if lobby_players[i]["peer"] == peer:
			lobby_players.remove_at(i)
			break
	_refresh_lobby()
	var mp := multiplayer.multiplayer_peer
	if mp is ENetMultiplayerPeer:
		get_tree().create_timer(0.5).timeout.connect(func() -> void: (mp as ENetMultiplayerPeer).disconnect_peer(peer))

func on_lobby(players: Array, opts: Dictionary) -> void:
	lobby_players = players
	lobby_opts = opts
	_apply_opts_ui()
	_refresh_lobby()

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
	if lobby_players.size() + int(lobby_opts["ai"]) >= MAX_PLAYERS:
		lobby_opts["ai"] = MAX_PLAYERS - lobby_players.size() - 1
		_apply_opts_ui()
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
	var ai_n := clampi(int(lobby_opts["ai"]), 0, MAX_PLAYERS - peers.size())
	if args.has("solo"):
		ai_n = 0
	elif args.has("bot"):
		ai_n = maxi(ai_n, 1)
	if args.has("ai"):
		ai_n = clampi(int(args["ai"]), 0, MAX_PLAYERS - peers.size())
	for i in range(ai_n):
		peers.append(-1)
		names.append("AI General %d" % (i + 1) if ai_n > 1 else "AI General")
	var opts := lobby_opts.duplicate()
	if args.has("map"):
		opts["map"] = args["map"]
	if args.has("ai_level"):
		opts["ai_level"] = args["ai_level"]
	var w := World.new()
	w.debug = args.has("debug")
	session.world = w
	w.start(session, peers, names, {"map": opts["map"], "cash": opts["cash"], "superweapons": opts["superweapons"], "ai": opts["ai_level"]})
	if args.has("simtest"):
		w.probe_ridge()
		get_tree().quit()

## Called (via Session.cl_map) on every peer once the server has built the map.
func begin_game(map: Dictionary, player_index: int) -> void:
	game_started = true
	menu.visible = false
	Audio.I.play_music("game")
	Audio.I.start_ambience()
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
	Audio.I.stop_all()
	Audio.I.play_music("menu")
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	lobby_players.clear()
	menu.visible = true
	lobby_box.visible = false
	menu_box.visible = true
	in_lobby = false
	_set_status("")
