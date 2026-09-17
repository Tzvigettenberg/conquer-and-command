class_name Main
extends Node3D
## Entry point: main menu, host/join lobby, then hands over to Session + ClientView.

const PORT := 7788
const GAME_VERSION := "0.1.0"
const MAX_PLAYERS := 6

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
var lobby_opts := {"map": "desert2", "cash": 10000, "superweapons": true, "slots": []}
var menu_box: VBoxContainer
var menu_scene: Node3D = null
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
	Settings.apply()
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
		if args.has("screenshot") and not args.has("autostart"):
			get_tree().create_timer(4.0).timeout.connect(func() -> void:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/lobby.png" % str(args["screenshot"]))
				print("[Shot] lobby saved")
				if args.has("exit_after"):
					get_tree().quit())
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
	bg.color = Color(0.02, 0.03, 0.05, 0.35)   # the 3D shell map shows through
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(bg)
	_show_menu_scene(true)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var pst := StyleBoxFlat.new()
	pst.bg_color = Color(0.05, 0.06, 0.08, 0.86)
	pst.set_content_margin_all(14)
	pst.set_corner_radius_all(6)
	pst.border_color = Color(0.3, 0.35, 0.45)
	pst.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", pst)
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
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	lobby_box.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	lobby_list = Label.new()
	lobby_list.text = "SLOTS  ·  click a spawn point on the map to move there"
	lobby_list.add_theme_font_size_override("font_size", 12)
	lobby_list.modulate = Color(0.7, 0.75, 0.8)
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
	var pl := Label.new()
	pl.text = "MAP"
	pl.add_theme_font_size_override("font_size", 12)
	pl.modulate = Color(0.7, 0.75, 0.8)
	right.add_child(pl)
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
	invite.text = "Invite: send friends your IP (port %d). Each map has its own number of spawn slots; set any slot to an AI (Easy / Medium / Hard) or close it." % PORT
	invite.add_theme_font_size_override("font_size", 12)
	invite.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	invite.modulate = Color(0.6, 0.6, 0.6)
	lobby_box.add_child(invite)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	lobby_box.add_child(hb)
	start_btn = Button.new()
	start_btn.text = "Start game"
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
	v.add_child(status_label)
	var quit := Button.new()
	quit.text = "Quit"
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
	_ensure_slots()
	lobby_opts["slots"][0] = {"kind": "human", "peer": 1, "name": my_name, "level": "", "team": 0}
	_apply_opts_ui()
	_show_lobby(true)
	_set_status("Hosting on port %d. Waiting for players... (or start with AI opponents)" % port)
	_refresh_lobby()
	if args.has("autostart") and (args.has("solo") or args.has("bot") or args.has("ai")):
		_start_game.call_deferred()

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
				if int(sl["peer"]) == 1:
					slots[0] = sl
				else:
					_kick(int(sl["peer"]), "The host picked a smaller map")
	for i in range(slots.size()):
		if int(slots[i]["team"]) < 0 or int(slots[i]["team"]) >= MAX_PLAYERS:
			slots[i]["team"] = i
	lobby_opts["slots"] = slots

func _empty_slot() -> Dictionary:
	return {"kind": "open", "peer": 0, "name": "", "level": "medium", "team": -1}

func _find_slot(peer: int) -> int:
	var slots: Array = lobby_opts.get("slots", [])
	for i in range(slots.size()):
		if slots[i]["kind"] == "human" and int(slots[i]["peer"]) == peer:
			return i
	return -1

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
	if slot < 0 or slot >= slots.size():
		return
	match str(c.get("t", "")):
		"kind":
			if peer != 1:
				return
			var k := str(c["kind"])
			if slots[slot]["kind"] == "human":
				if int(slots[slot]["peer"]) == 1:
					return
				_kick(int(slots[slot]["peer"]), "The host closed your slot")
			if k in ["easy", "medium", "hard"]:
				slots[slot] = {"kind": "ai", "peer": -1, "name": "", "level": k, "team": slots[slot]["team"]}
			else:
				slots[slot] = {"kind": k, "peer": 0, "name": "", "level": "medium", "team": slots[slot]["team"]}
		"team":
			var owner_peer := int(slots[slot]["peer"]) if slots[slot]["kind"] == "human" else 1
			if peer != 1 and peer != owner_peer:
				return
			slots[slot]["team"] = clampi(int(c["team"]), 0, MAX_PLAYERS - 1)
		"move":
			var from := _find_slot(peer)
			if from < 0 or slots[slot]["kind"] != "open":
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
			h.add_child(_team_picker(i, is_host))
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
				h.add_child(_team_picker(i, is_host))
		lobby_rows.add_child(h)
	_update_preview()
	if is_host:
		start_btn.text = "Start game" if players_n >= 2 else "Start solo (sandbox)"
		for sl in slots:
			if sl["kind"] == "human" and int(sl["peer"]) != 1:
				session.rpc_id(int(sl["peer"]), "cl_lobby", [], lobby_opts)
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

func on_lobby(players: Array, opts: Dictionary) -> void:
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
	if game_started or open < 0:
		session.rpc_id(peer, "cl_kick", "Game is full or already started")
		return
	lobby_players.append({"peer": peer, "name": pname})
	lobby_opts["slots"][open] = {"kind": "human", "peer": peer, "name": pname, "level": "", "team": lobby_opts["slots"][open]["team"]}
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
	_set_status("Connected. Waiting for host to start...")
	session.rpc_id(1, "srv_hello", my_name, GAME_VERSION)

func _on_conn_failed() -> void:
	_set_status("Connection failed. Check the IP and that the host's port %d is reachable." % PORT)
	_leave()

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
	for i in range(slots.size()):
		if ai_n > 0 and slots[i]["kind"] == "open":
			slots[i] = {"kind": "ai", "peer": -1, "name": "", "level": level, "team": slots[i]["team"]}
			ai_n -= 1
	var peers := []
	var names := []
	var teams := []
	var levels := []
	var starts := []
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
	if args.has("teams"):
		teams = []
		for t in str(args["teams"]).split(","):
			teams.append(int(t))
	if peers.is_empty():
		return
	game_started = true
	var w := World.new()
	w.debug = args.has("debug") or args.has("simdebug")
	session.world = w
	w.start(session, peers, names, {"map": lobby_opts["map"], "cash": lobby_opts["cash"], "superweapons": lobby_opts["superweapons"], "teams": teams, "levels": levels, "slots": starts})
	if args.has("simtest"):
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
