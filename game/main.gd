class_name Main
extends Node3D
## Entry point: main menu, host/join lobby, then hands over to Session + ClientView.

const PORT := 7788
const GAME_VERSION := "0.3.2"
const GAME_TITLE := "CONQUER & COMMAND"
const GAME_SUBTITLE := "ZERO BUDGET"
const MAX_PLAYERS := 6
const NO_LIST_TEXT := "The open-games list is not switched on in this build - send your friends your IP and they join below."

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
var opt_map: OptionButton
var opt_cash: OptionButton
var opt_sw: CheckButton
var preview_rect: TextureRect
var preview_marks: Control
var preview_name: Label
var preview_id := ""
const PREVIEW_PX := 240
## Host-owned lobby state, mirrored to clients. slots[i] = {kind: open|closed|ai|human, peer, name, level, team}
## observers = [{peer, name}]: humans watching the match without a slot (see everything, command nothing).
var lobby_opts := {"map": "desert2", "cash": 10000, "superweapons": true, "slots": [], "observers": []}
var menu_box: VBoxContainer
var menu_scene: Node3D = null
var rooms: RoomList
var room_name_edit: LineEdit
var room_pw_edit: LineEdit
var room_public: CheckButton
var room_rows: VBoxContainer
var room_hint: Label
var pw_box: VBoxContainer
var pw_edit: LineEdit
var pw_room_id := ""
var room_refresh_t := 0.0
const JOIN_TIMEOUT := 12.0     # ENet gives up on its own eventually; this is the friendly one
const LOBBY_TIMEOUT := 8.0
var connecting_to := ""
var connect_t := 0.0
var lobby_t := 0.0
var lobby_seen := false
var joining_room_id := ""
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
	rooms = RoomList.new()
	rooms.name = "RoomList"
	add_child(rooms)
	rooms.rooms_changed.connect(_on_rooms_changed)
	rooms.rooms_failed.connect(func(msg: String) -> void:
		if room_rows.get_child_count() == 0:
			room_hint.text = NO_LIST_TEXT if msg == "off" else "Can't reach the room list (%s). Join by IP below, or try Refresh." % msg)
	rooms.announced.connect(func(ok: bool, msg: String) -> void: _set_status(("Hosting on port %d. " % port) + msg) if ok else _set_status(msg))
	rooms.joined.connect(_on_room_joined)
	rooms.unreachable_reported.connect(func(n: int) -> void:
		_set_status("%d player%s found your room but could not connect. They need UDP port %d open on your router - forward it, or host from a Tailscale / ZeroTier address instead." % [n, "" if n == 1 else "s", port]))
	if args.has("port"):
		port = int(args["port"])
	Settings.apply()
	if not args.has("headless_audio_off"):
		audio.play_music("menu")
	_build_menu()
	if args.has("shell_only"):
		# website / trailer capture: just the living shell map, no panels
		menu.visible = false
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
		if args.has("screenshot") and not args.has("autostart"):
			get_tree().create_timer(float(args.get("shot_delay", 4.0))).timeout.connect(func() -> void:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/lobby.png" % str(args["screenshot"]))
				print("[Shot] lobby saved")
				if args.has("exit_after"):
					get_tree().quit())
	elif args.has("join"):
		ip_edit.text = args["join"]
		_join()
		if args.has("screenshot"):
			get_tree().create_timer(float(args.get("shot_delay", 8.0))).timeout.connect(func() -> void:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/client_lobby.png" % str(args["screenshot"]))
				print("[Shot] client lobby saved")
				if args.has("exit_after"):
					get_tree().quit())
	elif args.has("screenshot"):
		# main menu shot (room list included) for the README / site
		get_tree().create_timer(5.0).timeout.connect(func() -> void:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/menu.png" % str(args["screenshot"]))
			print("[Shot] menu saved")
			if args.has("exit_after"):
				get_tree().quit())

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
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = MenuTheme.build()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.35)   # the 3D shell map shows through
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	# letterbox bars top and bottom, Generals-style
	for side in [Control.PRESET_TOP_WIDE, Control.PRESET_BOTTOM_WIDE]:
		var bar := ColorRect.new()
		bar.color = Color(0.03, 0.03, 0.04, 0.85)
		bar.set_anchors_preset(side)
		bar.custom_minimum_size = Vector2(0, 46)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
		var rule := ColorRect.new()
		rule.color = MenuTheme.BRASS_DIM
		rule.set_anchors_preset(side)
		rule.custom_minimum_size = Vector2(0, 2)
		if side == Control.PRESET_TOP_WIDE:
			rule.position.y = 46
		else:
			rule.anchor_top = 1.0
			rule.offset_top = -48
			rule.offset_bottom = -46
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(rule)
	var ver := Label.new()
	ver.text = "%s: %s  ·  v%s" % [GAME_TITLE, GAME_SUBTITLE, GAME_VERSION]
	ver.add_theme_font_size_override("font_size", 12)
	ver.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(14, -34)
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_top = -34
	ver.offset_bottom = -14
	root.add_child(ver)
	_show_menu_scene(true)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(MenuTheme.headline(GAME_TITLE, 42))
	var sub := Label.new()
	sub.text = GAME_SUBTITLE
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", MenuTheme.TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 8)
	v.add_child(menu_box)
	menu_box.add_child(MenuTheme.section("Commander"))
	menu_box.add_child(_label("Callsign"))
	name_edit = LineEdit.new()
	name_edit.text = my_name
	name_edit.placeholder_text = "Your name"
	menu_box.add_child(name_edit)
	# ---- host a room ----
	menu_box.add_child(MenuTheme.section("Host a game"))
	var hg := GridContainer.new()
	hg.columns = 2
	hg.add_theme_constant_override("h_separation", 12)
	hg.add_theme_constant_override("v_separation", 6)
	menu_box.add_child(hg)
	hg.add_child(_label("Room name"))
	room_name_edit = LineEdit.new()
	room_name_edit.placeholder_text = "%s's game" % my_name
	room_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hg.add_child(room_name_edit)
	hg.add_child(_label("Password"))
	room_pw_edit = LineEdit.new()
	room_pw_edit.placeholder_text = "optional - friends only"
	room_pw_edit.secret = true
	room_pw_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hg.add_child(room_pw_edit)
	hg.add_child(_label("Show in the list"))
	room_public = CheckButton.new()
	room_public.button_pressed = true
	room_public.tooltip_text = "Off: nobody sees the room; friends join by IP as before."
	if not rooms.enabled():
		room_public.button_pressed = false
	hg.add_child(room_public)
	var host_btn := Button.new()
	host_btn.text = "HOST GAME"
	host_btn.custom_minimum_size = Vector2(0, 44)
	host_btn.pressed.connect(_host)
	menu_box.add_child(host_btn)
	# ---- join ----
	var jh := HBoxContainer.new()
	jh.add_theme_constant_override("separation", 8)
	var js := MenuTheme.section("Open games")
	js.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jh.add_child(js)
	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(func() -> void: rooms.refresh())
	jh.add_child(refresh_btn)
	menu_box.add_child(jh)
	if not rooms.enabled():
		# nothing to name or lock without a list: just host, and say so below
		hg.visible = false
		jh.visible = false
	room_rows = VBoxContainer.new()
	room_rows.add_theme_constant_override("separation", 4)
	menu_box.add_child(room_rows)
	room_hint = Label.new()
	room_hint.text = "Looking for games..." if rooms.enabled() else NO_LIST_TEXT
	room_hint.add_theme_font_size_override("font_size", 12)
	room_hint.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	room_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_box.add_child(room_hint)
	pw_box = VBoxContainer.new()
	pw_box.visible = false
	pw_box.add_theme_constant_override("separation", 6)
	menu_box.add_child(pw_box)
	var pwl := _label("This room needs a password")
	pw_box.add_child(pwl)
	var pwh := HBoxContainer.new()
	pwh.add_theme_constant_override("separation", 8)
	pw_box.add_child(pwh)
	pw_edit = LineEdit.new()
	pw_edit.secret = true
	pw_edit.placeholder_text = "Password"
	pw_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pw_edit.text_submitted.connect(func(_t: String) -> void: _join_room(pw_room_id, pw_edit.text))
	pwh.add_child(pw_edit)
	var pwj := Button.new()
	pwj.text = "Join"
	pwj.pressed.connect(func() -> void: _join_room(pw_room_id, pw_edit.text))
	pwh.add_child(pwj)
	var pwc := Button.new()
	pwc.text = "Cancel"
	pwc.pressed.connect(func() -> void: pw_box.visible = false)
	pwh.add_child(pwc)
	var ih := HBoxContainer.new()
	ih.add_theme_constant_override("separation", 8)
	menu_box.add_child(ih)
	ip_edit = LineEdit.new()
	ip_edit.text = ""
	ip_edit.placeholder_text = "...or join by IP / hostname"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_edit.text_submitted.connect(func(_t: String) -> void: _join())
	ih.add_child(ip_edit)
	var join_btn := Button.new()
	join_btn.text = "JOIN BY IP"
	join_btn.pressed.connect(_join)
	ih.add_child(join_btn)
	var help := Label.new()
	help.text = "Hosting needs UDP port %d reachable: forward it on your router, or everyone uses a mesh VPN (Tailscale / ZeroTier) and you host from that IP. Same Wi-Fi: it just works." % PORT
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(0.6, 0.6, 0.6)
	help.add_theme_font_size_override("font_size", 12)
	menu_box.add_child(help)

	lobby_box = VBoxContainer.new()
	lobby_box.add_theme_constant_override("separation", 8)
	lobby_box.visible = false
	v.add_child(lobby_box)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	lobby_box.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(MenuTheme.section("Game setup"))
	lobby_list = Label.new()
	lobby_list.text = "Slots  ·  click a spawn point on the map to move there"
	lobby_list.add_theme_font_size_override("font_size", 12)
	lobby_list.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	left.add_child(lobby_list)
	lobby_rows = VBoxContainer.new()
	lobby_rows.add_theme_constant_override("separation", 4)
	left.add_child(lobby_rows)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	grid.add_child(_label("Map"))
	opt_map = OptionButton.new()
	for k in MapGen.MAP_ORDER:
		opt_map.add_item("%s  (%d players)" % [MapGen.MAPS[k]["name"], MapGen.MAPS[k]["players"]])
		opt_map.set_item_metadata(opt_map.item_count - 1, k)
	opt_map.item_selected.connect(func(_i: int) -> void: _opts_changed())
	grid.add_child(opt_map)
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
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	cols.add_child(right)
	right.add_child(MenuTheme.section("Map"))
	preview_rect = TextureRect.new()
	preview_rect.custom_minimum_size = Vector2(PREVIEW_PX, PREVIEW_PX)
	preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	right.add_child(preview_rect)
	preview_marks = Control.new()
	preview_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_marks.draw.connect(_draw_preview_marks)
	preview_marks.gui_input.connect(_preview_input)
	preview_rect.add_child(preview_marks)
	preview_name = Label.new()
	preview_name.add_theme_font_size_override("font_size", 12)
	preview_name.modulate = Color(0.7, 0.7, 0.7)
	right.add_child(preview_name)
	var invite := Label.new()
	invite.text = "Invite: send friends your IP (UDP port %d - forward it on your router for internet play). Each map has its own number of spawn slots; set any slot to an AI (Easy / Medium / Hard) or close it. Observe = watch the match with everything revealed (e.g. AI vs AI)." % PORT
	invite.add_theme_font_size_override("font_size", 12)
	invite.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	invite.modulate = Color(0.6, 0.6, 0.6)
	lobby_box.add_child(invite)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	lobby_box.add_child(hb)
	start_btn = Button.new()
	start_btn.text = "Start game"
	start_btn.custom_minimum_size = Vector2(0, 44)
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_btn.pressed.connect(_on_start_pressed)
	hb.add_child(start_btn)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(_leave)
	hb.add_child(leave)

	status_label = Label.new()
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", MenuTheme.AMBER)
	v.add_child(status_label)
	var quit := Button.new()
	quit.text = "QUIT"
	quit.pressed.connect(func() -> void: get_tree().quit())
	v.add_child(quit)

## Living 3D backdrop behind the menu (freed when a match starts).
func _show_menu_scene(on: bool) -> void:
	if on and menu_scene == null and not args.has("headless_audio_off") and DisplayServer.get_name() != "headless":
		menu_scene = MenuScene.new()
		menu_scene.name = "MenuScene"
		add_child(menu_scene)
	elif not on and menu_scene != null:
		menu_scene.queue_free()
		menu_scene = null

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
	lobby_opts["slots"] = []
	if args.has("map"):
		lobby_opts["map"] = MapGen.map_id(str(args["map"]))
	lobby_opts["observers"] = []
	_ensure_slots()
	lobby_opts["slots"][0] = {"kind": "human", "peer": 1, "name": my_name, "level": "", "team": 0, "faction": str(args.get("faction", "random"))}
	if args.has("observe"):
		_set_observer(1, true)
	_apply_opts_ui()
	_show_lobby(true)
	_set_status("Hosting on port %d. Waiting for players... (or start with AI opponents)" % port)
	if room_public.button_pressed and rooms.enabled() and not args.has("autostart") and DisplayServer.get_name() != "headless":
		var rn := room_name_edit.text.strip_edges()
		if rn == "":
			rn = "%s's game" % my_name
		rooms.announce(rn, room_pw_edit.text, MapGen.MAPS[lobby_opts["map"]]["players"], port)
	_refresh_lobby()
	if args.has("autostart") and (args.has("solo") or args.has("bot") or args.has("ai")):
		_start_game.call_deferred()

## Room list: rebuild the rows.
func _on_rooms_changed(list: Array) -> void:
	if args.has("join_first") and not list.is_empty() and joining_room_id == "" and not in_lobby:
		# test hook: take the first room in the list without clicking it
		_join_room(str(list[0]["id"]), str(args.get("pw", "")))
		return
	for c in room_rows.get_children():
		c.queue_free()
	if list.is_empty():
		room_hint.text = "No open games right now. Host one, or join a friend by IP below."
	else:
		room_hint.text = "%d open game%s - click one to join." % [list.size(), "" if list.size() == 1 else "s"]
	for r in list:
		var b := Button.new()
		var lock := "  [locked]" if bool(r.get("has_password", false)) else ""
		var state := "  · in progress" if bool(r.get("started", false)) else ""
		b.text = "%s    %d / %d players%s%s" % [str(r["name"]), int(r["players"]), int(r["max_players"]), lock, state]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = bool(r.get("started", false))
		var rid := str(r["id"])
		var pw := bool(r.get("has_password", false))
		var rname := str(r["name"])
		b.pressed.connect(func() -> void:
			if pw:
				pw_room_id = rid
				pw_edit.text = ""
				pw_box.visible = true
				(pw_box.get_child(0) as Label).text = "Password for \"%s\"" % rname
				pw_edit.grab_focus()
			else:
				_join_room(rid, ""))
		room_rows.add_child(b)

func _join_room(id: String, password: String) -> void:
	pw_box.visible = false
	joining_room_id = id
	_set_status("Asking for the room address...")
	rooms.join(id, password)

func _on_room_joined(ok: bool, ip: String, jport: int, message: String) -> void:
	if not ok:
		_set_status(message)
		return
	ip_edit.text = ip
	port = jport
	_join()

func _process(dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if connect_t > 0.0 and now >= connect_t:
		connect_t = 0.0
		_fail_join()
	elif lobby_t > 0.0 and now >= lobby_t and not lobby_seen:
		lobby_t = 0.0
		_fail_join("Connected to the host, but they never sent the lobby - are you both on the same version? Ask them to check, then try again.")
	# keep the open-games list fresh while the menu is up
	if menu != null and menu.visible and menu_box != null and menu_box.visible and not in_lobby and not game_started and rooms.enabled():
		if Time.get_ticks_msec() / 1000.0 >= room_refresh_t:
			room_refresh_t = Time.get_ticks_msec() / 1000.0 + 6.0
			if DisplayServer.get_name() != "headless" and not args.has("autostart"):
				rooms.refresh()

func _join() -> void:
	my_name = name_edit.text.strip_edges()
	if my_name == "":
		my_name = "Guest"
	var ip := ip_edit.text.strip_edges()
	if ip == "":
		_set_status("Pick an open game above, or enter the host's IP address first.")
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		_set_status("Could not start client (error %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	# stay on the menu until the host actually answers - showing an empty lobby while nothing is
	# connected is what makes an unreachable host look like a broken one
	connecting_to = "%s:%d" % [ip, port]
	connect_t = Time.get_ticks_msec() / 1000.0 + JOIN_TIMEOUT
	lobby_seen = false
	_set_status("Connecting to %s..." % connecting_to)

func _leave() -> void:
	rooms.close()
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
	for c in [opt_map, opt_cash, opt_sw]:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_STOP if is_host else Control.MOUSE_FILTER_IGNORE
		(c as Control).modulate = Color.WHITE if is_host else Color(0.7, 0.7, 0.7)
	start_btn.text = "Start game"

func _opts_changed() -> void:
	if not multiplayer.is_server():
		return
	lobby_opts["map"] = opt_map.get_item_metadata(opt_map.selected)
	lobby_opts["cash"] = opt_cash.get_item_metadata(opt_cash.selected)
	lobby_opts["superweapons"] = opt_sw.button_pressed
	_ensure_slots()
	_refresh_lobby()

## Make the slot list match the map: keep occupants, drop humans that no longer fit
## into open slots, default the rest to Open.
func _ensure_slots() -> void:
	var n := MapGen.slots(str(lobby_opts["map"]))
	var slots: Array = lobby_opts.get("slots", [])
	while slots.size() < n:
		var e := _empty_slot()
		e["team"] = slots.size()
		slots.append(e)
	if slots.size() > n:
		var cut: Array = slots.slice(n)
		slots = slots.slice(0, n)
		for sl in cut:
			if sl["kind"] != "human":
				continue
			var placed := false
			for i in range(n):
				if slots[i]["kind"] == "open" or slots[i]["kind"] == "closed":
					slots[i] = sl
					placed = true
					break
			if not placed:
				lobby_opts["observers"].append({"peer": int(sl["peer"]), "name": str(sl["name"])})
	for i in range(slots.size()):
		if int(slots[i]["team"]) < 0 or int(slots[i]["team"]) >= MAX_PLAYERS:
			slots[i]["team"] = i
	lobby_opts["slots"] = slots

func _empty_slot() -> Dictionary:
	return {"kind": "open", "peer": 0, "name": "", "level": "medium", "team": -1, "faction": "random"}

func _faction_picker(slot: int, is_host: bool) -> OptionButton:
	var ob := OptionButton.new()
	var opts := [["random", "Random"]]
	for f in Data.FACTION_ORDER:
		opts.append([f, Data.FACTIONS[f]["name"]])
	var slots: Array = lobby_opts["slots"]
	var cur := str(slots[slot].get("faction", "random"))
	for i in range(opts.size()):
		ob.add_item(opts[i][1])
		ob.set_item_metadata(i, opts[i][0])
		if opts[i][0] == cur:
			ob.select(i)
	ob.tooltip_text = "USA: air power and lasers.  China: hordes, flame, the Overlord, the Nuke.  GLA: no power needed, tunnels, toxins, suicide bombers, SCUDs."
	var mine: bool = slots[slot]["kind"] == "human" and int(slots[slot]["peer"]) == multiplayer.get_unique_id()
	ob.mouse_filter = Control.MOUSE_FILTER_STOP if (is_host or mine) else Control.MOUSE_FILTER_IGNORE
	ob.item_selected.connect(func(i: int) -> void:
		_lobby_cmd({"t": "faction", "slot": slot, "faction": opts[i][0]}))
	return ob

func _find_slot(peer: int) -> int:
	var slots: Array = lobby_opts.get("slots", [])
	for i in range(slots.size()):
		if slots[i]["kind"] == "human" and int(slots[i]["peer"]) == peer:
			return i
	return -1

func _is_observer(peer: int) -> bool:
	for ob in lobby_opts.get("observers", []):
		if int(ob["peer"]) == peer:
			return true
	return false

func peer_name(peer: int) -> String:
	for lp in lobby_players:
		if int(lp["peer"]) == peer:
			return str(lp["name"])
	return "?"

## Move a human between the slot list and the observer list (host only).
func _set_observer(peer: int, on: bool) -> void:
	var slots: Array = lobby_opts["slots"]
	if on:
		var k := _find_slot(peer)
		if k < 0 or _is_observer(peer):
			return
		var t: int = slots[k]["team"]
		lobby_opts["observers"].append({"peer": peer, "name": str(slots[k]["name"])})
		slots[k] = _empty_slot()
		slots[k]["team"] = t
	else:
		var open := _first_open()
		if open < 0 or not _is_observer(peer):
			return
		_seat(peer, open)

## Take an observer out of the observer list and into slot k (must be open).
func _seat(peer: int, k: int) -> void:
	var obs: Array = lobby_opts["observers"]
	for i in range(obs.size()):
		if int(obs[i]["peer"]) == peer:
			var nm: String = str(obs[i]["name"])
			obs.remove_at(i)
			lobby_opts["slots"][k] = {"kind": "human", "peer": peer, "name": nm, "level": "", "team": lobby_opts["slots"][k]["team"], "faction": str(lobby_opts["slots"][k].get("faction", "random"))}
			return

func _first_open() -> int:
	var slots: Array = lobby_opts.get("slots", [])
	for i in range(slots.size()):
		if slots[i]["kind"] == "open":
			return i
	return -1

func _occupied() -> Array:
	var out: Array = []
	var slots: Array = lobby_opts.get("slots", [])
	for i in range(slots.size()):
		if slots[i]["kind"] == "human" or slots[i]["kind"] == "ai":
			out.append(i)
	return out

## Colour a slot will get in game = its index among the occupied slots.
func _slot_color(i: int) -> Color:
	var occ := _occupied()
	var k := occ.find(i)
	if k < 0:
		return Color(0.3, 0.3, 0.32)
	return Data.TEAM_COLORS[k % Data.TEAM_COLORS.size()]

func _team_picker(slot: int, is_host: bool) -> OptionButton:
	var ob := OptionButton.new()
	for t in range(MAX_PLAYERS):
		ob.add_item("Team %d" % (t + 1))
	var slots: Array = lobby_opts["slots"]
	ob.select(clampi(int(slots[slot]["team"]), 0, MAX_PLAYERS - 1))
	var mine: bool = slots[slot]["kind"] == "human" and int(slots[slot]["peer"]) == multiplayer.get_unique_id()
	ob.mouse_filter = Control.MOUSE_FILTER_STOP if (is_host or mine) else Control.MOUSE_FILTER_IGNORE
	ob.item_selected.connect(func(i: int) -> void:
		_lobby_cmd({"t": "team", "slot": slot, "team": i}))
	return ob

func _kind_picker(slot: int) -> OptionButton:
	var ob := OptionButton.new()
	var kinds := [["open", "Open"], ["closed", "Closed"], ["easy", "Easy AI"], ["medium", "Medium AI"], ["hard", "Hard AI"]]
	var sl: Dictionary = lobby_opts["slots"][slot]
	var cur: String = sl["kind"] if sl["kind"] != "ai" else sl["level"]
	for i in range(kinds.size()):
		ob.add_item(kinds[i][1])
		ob.set_item_metadata(i, kinds[i][0])
		if kinds[i][0] == cur:
			ob.select(i)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.item_selected.connect(func(i: int) -> void:
		_lobby_cmd({"t": "kind", "slot": slot, "kind": kinds[i][0]}))
	return ob

## Lobby change request: applied directly on the host, sent to the host otherwise.
func _lobby_cmd(c: Dictionary) -> void:
	if multiplayer.is_server():
		on_lobby_cmd(1, c)
	else:
		session.rpc_id(1, "srv_lobby", c)

func on_lobby_cmd(peer: int, c: Dictionary) -> void:
	if not multiplayer.is_server() or game_started:
		return
	var slots: Array = lobby_opts["slots"]
	var slot := int(c.get("slot", -1))
	var t := str(c.get("t", ""))
	if t == "observe":
		# a player steps out to watch (themselves, or anyone by the host)
		var who := int(c.get("peer", peer))
		if peer != 1 and who != peer:
			return
		_set_observer(who, bool(c.get("on", true)))
		_refresh_lobby()
		return
	if slot < 0 or slot >= slots.size():
		return
	match t:
		"kind":
			if peer != 1:
				return
			var k := str(c["kind"])
			if slots[slot]["kind"] == "human":
				if int(slots[slot]["peer"]) == 1:
					return
				_kick(int(slots[slot]["peer"]), "The host closed your slot")
			var fac := str(slots[slot].get("faction", "random"))
			if k in ["easy", "medium", "hard"]:
				slots[slot] = {"kind": "ai", "peer": -1, "name": "", "level": k, "team": slots[slot]["team"], "faction": fac}
			else:
				slots[slot] = {"kind": k, "peer": 0, "name": "", "level": "medium", "team": slots[slot]["team"], "faction": fac}
		"team":
			var owner_peer := int(slots[slot]["peer"]) if slots[slot]["kind"] == "human" else 1
			if peer != 1 and peer != owner_peer:
				return
			slots[slot]["team"] = clampi(int(c["team"]), 0, MAX_PLAYERS - 1)
		"faction":
			var owner_peer := int(slots[slot]["peer"]) if slots[slot]["kind"] == "human" else 1
			if peer != 1 and peer != owner_peer:
				return
			var f := str(c.get("faction", "random"))
			slots[slot]["faction"] = f if (f == "random" or Data.FACTIONS.has(f)) else "random"
		"move":
			var from := _find_slot(peer)
			if slots[slot]["kind"] != "open":
				return
			if from < 0:
				if _is_observer(peer):
					_seat(peer, slot)
					_refresh_lobby()
				return
			var me: Dictionary = slots[from]
			slots[from] = _empty_slot()
			slots[from]["team"] = from
			me["team"] = slot if me["team"] == from else me["team"]
			slots[slot] = me
	_refresh_lobby()

func _apply_opts_ui() -> void:
	for i in range(opt_map.item_count):
		if opt_map.get_item_metadata(i) == lobby_opts["map"]:
			opt_map.select(i)
	for i in range(opt_cash.item_count):
		if int(opt_cash.get_item_metadata(i)) == int(lobby_opts["cash"]):
			opt_cash.select(i)
	opt_sw.button_pressed = bool(lobby_opts["superweapons"])

func _refresh_lobby() -> void:
	if multiplayer.is_server():
		rooms.set_players(lobby_players.size(), game_started)
	for c in lobby_rows.get_children():
		lobby_rows.remove_child(c)
		c.queue_free()
	var is_host := multiplayer.is_server()
	var slots: Array = lobby_opts.get("slots", [])
	var players_n := 0
	for i in range(slots.size()):
		var sl: Dictionary = slots[i]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var num := Label.new()
		num.text = "%d" % (i + 1)
		num.custom_minimum_size = Vector2(18, 0)
		num.modulate = Color(0.6, 0.6, 0.65)
		h.add_child(num)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(14, 14)
		sw.color = _slot_color(i)
		h.add_child(sw)
		if sl["kind"] == "human":
			players_n += 1
			var l := Label.new()
			l.text = "  %s%s" % [sl["name"], "  (host)" if int(sl["peer"]) == 1 else ""]
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(l)
			h.add_child(_faction_picker(i, is_host))
			h.add_child(_team_picker(i, is_host))
			if is_host or int(sl["peer"]) == multiplayer.get_unique_id():
				var ob := Button.new()
				ob.text = "Observe"
				ob.tooltip_text = "Step out of the match and watch it with everything revealed"
				ob.pressed.connect(func() -> void: _lobby_cmd({"t": "observe", "peer": int(sl["peer"]), "on": true}))
				h.add_child(ob)
			if is_host and int(sl["peer"]) != 1:
				var kick := Button.new()
				kick.text = "Kick"
				kick.pressed.connect(func() -> void: _kick(int(sl["peer"]), "You were removed from the lobby by the host"))
				h.add_child(kick)
		else:
			if sl["kind"] == "ai":
				players_n += 1
			if is_host:
				h.add_child(_kind_picker(i))
			else:
				var l := Label.new()
				l.text = "  " + ({"open": "Open", "closed": "Closed", "ai": "%s AI" % str(sl["level"]).capitalize()}[sl["kind"]])
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				l.modulate = Color(0.75, 0.75, 0.75) if sl["kind"] == "ai" else Color(0.5, 0.5, 0.5)
				h.add_child(l)
			if sl["kind"] == "ai":
				h.add_child(_faction_picker(i, is_host))
				h.add_child(_team_picker(i, is_host))
		lobby_rows.add_child(h)
	var observers: Array = lobby_opts.get("observers", [])
	if not observers.is_empty():
		var ol := Label.new()
		ol.text = "Observers"
		ol.modulate = Color(0.7, 0.7, 0.75)
		lobby_rows.add_child(ol)
		for ob in observers:
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 6)
			var eye := Label.new()
			eye.text = "  •"
			eye.custom_minimum_size = Vector2(36, 0)
			eye.modulate = Color(0.6, 0.6, 0.65)
			h.add_child(eye)
			var l := Label.new()
			l.text = "%s%s  (watching)" % [str(ob["name"]), "  (host)" if int(ob["peer"]) == 1 else ""]
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.modulate = Color(0.85, 0.85, 0.9)
			h.add_child(l)
			if (is_host or int(ob["peer"]) == multiplayer.get_unique_id()) and _first_open() >= 0:
				var jb := Button.new()
				jb.text = "Play"
				jb.tooltip_text = "Take the first open slot (or click a spawn point on the map)"
				jb.pressed.connect(func() -> void: _lobby_cmd({"t": "observe", "peer": int(ob["peer"]), "on": false}))
				h.add_child(jb)
			if is_host and int(ob["peer"]) != 1:
				var kick := Button.new()
				kick.text = "Kick"
				kick.pressed.connect(func() -> void: _kick(int(ob["peer"]), "You were removed from the lobby by the host"))
				h.add_child(kick)
			lobby_rows.add_child(h)
	_update_preview()
	if args.has("netdebug"):
		var dbg := []
		for sl in slots:
			dbg.append("%s:%s" % [sl["kind"], sl.get("name", "")])
		print("[Lobby] %s rows=%s observers=%d map=%s cash=%s" % ["host" if is_host else "client", str(dbg), observers.size(), lobby_opts.get("map", "?"), lobby_opts.get("cash", "?")])
	if is_host:
		var humans := 0
		for sl in slots:
			if sl["kind"] == "human":
				humans += 1
		if players_n == 0:
			start_btn.text = "Add a player or an AI to start"
		elif humans == 0:
			start_btn.text = "Watch the AIs fight" if players_n >= 2 else "Watch AI (sandbox)"
		else:
			start_btn.text = "Start game" if players_n >= 2 else "Start solo (sandbox)"
		start_btn.disabled = players_n == 0
		for sl in slots:
			if sl["kind"] == "human" and int(sl["peer"]) != 1:
				session.rpc_id(int(sl["peer"]), "cl_lobby", [], lobby_opts)
		for ob in observers:
			if int(ob["peer"]) != 1:
				session.rpc_id(int(ob["peer"]), "cl_lobby", [], lobby_opts)
		if args.has("autostart") and players_n >= 2 and not game_started and not (args.has("ai") or args.has("bot") or args.has("solo")):
			_start_game()

func _update_preview() -> void:
	var id := MapGen.map_id(str(lobby_opts["map"]))
	if id != preview_id:
		preview_id = id
		preview_rect.texture = ImageTexture.create_from_image(MapGen.preview(id, PREVIEW_PX))
		preview_name.text = "%s  ·  %d slots  ·  %d m" % [MapGen.MAPS[id]["name"], MapGen.MAPS[id]["players"], int(MapGen.MAPS[id]["size"])]
	preview_marks.queue_redraw()

func _preview_pos(i: int) -> Vector2:
	var md: Dictionary = MapGen.MAPS[preview_id]
	var f: Vector2 = md["starts"][i]
	return Vector2(f.x, f.y) * preview_marks.size

func _draw_preview_marks() -> void:
	if preview_id == "":
		return
	var slots: Array = lobby_opts.get("slots", [])
	var md: Dictionary = MapGen.MAPS[preview_id]
	var font := ThemeDB.fallback_font
	for i in range(md["starts"].size()):
		var p := _preview_pos(i)
		var col := _slot_color(i)
		var kind: String = slots[i]["kind"] if i < slots.size() else "open"
		preview_marks.draw_circle(p, 13.0, Color(0, 0, 0, 0.6))
		if kind == "closed":
			preview_marks.draw_arc(p, 11.0, 0, TAU, 24, Color(0.4, 0.4, 0.4), 2.0)
			preview_marks.draw_line(p + Vector2(-7, -7), p + Vector2(7, 7), Color(0.5, 0.5, 0.5), 2.0)
		else:
			preview_marks.draw_circle(p, 11.0, col if kind != "open" else Color(0.2, 0.2, 0.22))
			preview_marks.draw_arc(p, 11.0, 0, TAU, 24, Color.WHITE if kind != "open" else Color(0.6, 0.6, 0.6), 1.5)
		preview_marks.draw_string(font, p + Vector2(-4, 5), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		if i < slots.size() and slots[i]["kind"] == "human":
			var nm: String = slots[i]["name"]
			preview_marks.draw_string(font, p + Vector2(-nm.length() * 3.2, 26), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	var obs: Array = lobby_opts.get("observers", [])
	if not obs.is_empty():
		var names := []
		for ob in obs:
			names.append(str(ob["name"]))
		preview_marks.draw_string(font, Vector2(6, preview_marks.size.y - 6), "Watching: " + ", ".join(names), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.9, 1.0))

func _preview_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and preview_id != "":
		var md: Dictionary = MapGen.MAPS[preview_id]
		for i in range(md["starts"].size()):
			if _preview_pos(i).distance_to(ev.position) < 14.0:
				_lobby_cmd({"t": "move", "slot": i})
				return

func _kick(peer: int, reason := "You were removed from the lobby by the host") -> void:
	session.rpc_id(peer, "cl_kick", reason)
	_remove_peer(peer)
	_refresh_lobby()
	var mp := multiplayer.multiplayer_peer
	if mp is ENetMultiplayerPeer:
		get_tree().create_timer(0.5).timeout.connect(func() -> void: (mp as ENetMultiplayerPeer).disconnect_peer(peer))

func _remove_peer(peer: int) -> void:
	for i in range(lobby_players.size()):
		if lobby_players[i]["peer"] == peer:
			lobby_players.remove_at(i)
			break
	var k := _find_slot(peer)
	if k >= 0:
		var t: int = lobby_opts["slots"][k]["team"]
		lobby_opts["slots"][k] = _empty_slot()
		lobby_opts["slots"][k]["team"] = t
	var obs: Array = lobby_opts.get("observers", [])
	for i in range(obs.size()):
		if int(obs[i]["peer"]) == peer:
			obs.remove_at(i)
			break

func on_lobby(players: Array, opts: Dictionary) -> void:
	if not lobby_seen:
		lobby_seen = true
		lobby_t = 0.0
		joining_room_id = ""
		_set_status("")
	if not players.is_empty():
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
	var open := _first_open()
	if game_started:
		session.rpc_id(peer, "cl_kick", "Game already started")
		return
	lobby_players.append({"peer": peer, "name": pname})
	if open < 0:
		lobby_opts["observers"].append({"peer": peer, "name": pname})
		_set_status("%s joined as an observer (no open slot)." % pname)
	else:
		lobby_opts["slots"][open] = {"kind": "human", "peer": peer, "name": pname, "level": "", "team": lobby_opts["slots"][open]["team"], "faction": "random"}
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
					_remove_peer(id)
					_set_status("%s left." % nm)
					_refresh_lobby()
				break

func _on_connected() -> void:
	connecting_to = ""
	connect_t = 0.0
	lobby_t = Time.get_ticks_msec() / 1000.0 + LOBBY_TIMEOUT
	_show_lobby(false)
	_set_status("Connected. Waiting for the host...")
	session.rpc_id(1, "srv_hello", my_name, GAME_VERSION)

func _on_conn_failed() -> void:
	_fail_join()

## Nothing answered, or the host answered but never sent the lobby: say which, and why it happens.
func _fail_join(reason := "") -> void:
	var where := connecting_to if connecting_to != "" else "the host"
	connecting_to = ""
	connect_t = 0.0
	lobby_t = 0.0
	_leave()
	if joining_room_id != "":
		# the host can see this on their own screen - they are the one who can open the port
		rooms.report_unreachable(joining_room_id)
		joining_room_id = ""
	if reason != "":
		_set_status(reason)
	else:
		_set_status("Could not reach %s. The host has to be reachable on UDP port %d: forward it on their router, or both of you join a mesh VPN (Tailscale / ZeroTier) and host from that address. On the same Wi-Fi, use their local IP." % [where, port])

func _on_server_disconnected() -> void:
	if view:
		view.on_msg("Host disconnected")
		view.on_gameover(-2, [])
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
	var slots: Array = lobby_opts["slots"]
	# command-line fills (tests): --ai=N [--ai_level=x] fills open slots with AIs
	var ai_n := 0
	if args.has("bot"):
		ai_n = 1
	if args.has("ai"):
		ai_n = int(args["ai"])
	var level := str(args.get("ai_level", "medium"))
	var ai_facs: Array = str(args.get("ai_faction", "random")).split(",")
	var ai_i := 0
	for i in range(slots.size()):
		if ai_n > 0 and slots[i]["kind"] == "open":
			slots[i] = {"kind": "ai", "peer": -1, "name": "", "level": level, "team": slots[i]["team"], "faction": str(ai_facs[mini(ai_i, ai_facs.size() - 1)])}
			ai_i += 1
			ai_n -= 1
	var peers := []
	var names := []
	var teams := []
	var levels := []
	var starts := []
	var factions := []
	var ai_k := 0
	for i in range(slots.size()):
		var sl: Dictionary = slots[i]
		if sl["kind"] == "human":
			peers.append(int(sl["peer"]))
			names.append(sl["name"])
		elif sl["kind"] == "ai":
			ai_k += 1
			peers.append(-1)
			names.append("AI General %d (%s)" % [ai_k, str(sl["level"]).capitalize()])
		else:
			continue
		teams.append(int(sl["team"]))
		levels.append(str(sl["level"]) if sl["kind"] == "ai" else "")
		starts.append(i)
		factions.append(str(sl.get("faction", "random")))
	if args.has("teams"):
		teams = []
		for t in str(args["teams"]).split(","):
			teams.append(int(t))
	if peers.is_empty():
		return
	var observers := []
	for ob in lobby_opts.get("observers", []):
		observers.append(int(ob["peer"]))
	game_started = true
	rooms.set_players(lobby_players.size(), true)
	var w := World.new()
	w.debug = args.has("debug") or args.has("simdebug")
	session.world = w
	w.start(session, peers, names, {"map": lobby_opts["map"], "cash": lobby_opts["cash"], "superweapons": lobby_opts["superweapons"], "teams": teams, "levels": levels, "slots": starts, "observers": observers, "factions": factions, "cheats": args.has("test")})
	if args.has("simtest"):
		if str(args["simtest"]) == "load":
			w.probe_load()
		elif str(args["simtest"]) == "garrison":
			w.probe_garrison()
		elif str(args["simtest"]) == "content":
			w.probe_content()
		elif w.has_method("probe_" + str(args["simtest"])):
			w.call("probe_" + str(args["simtest"]))
		else:
			w.probe_ridge()
		get_tree().quit()

## Called (via Session.cl_map) on every peer once the server has built the map.
func begin_game(map: Dictionary, player_index: int) -> void:
	game_started = true
	menu.visible = false
	_show_menu_scene(false)
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
	rooms.close()
	Audio.I.stop_all()
	Audio.I.play_music("menu")
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	lobby_players.clear()
	menu.visible = true
	lobby_box.visible = false
	menu_box.visible = true
	in_lobby = false
	_show_menu_scene(true)
	_set_status("")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and rooms != null:
		rooms.close()   # best effort: take the room off the list when the window closes
