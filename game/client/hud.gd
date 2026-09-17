class_name Hud
extends CanvasLayer
## Generals-style command bar: minimap, selection info, command grid, top bar,
## general's powers, messages, world-space overlay (health bars, selection box).

const BAR_H := 256.0
const GRID_COLS := 4
const GRID_ROWS := 3

var view: ClientView
var ctl: Controller
var cash_label: Label
var power_label: Label
var rank_label: Label
var time_label: Label
var promo_btn: Button
var sw_label: Label
var hint_label: Label
var msg_box: VBoxContainer
var info_title: Label
var info_body: RichTextLabel
var queue_box: HBoxContainer
var grid_buttons: Array[Button] = []
var grid_actions: Array = []
var grid_why: Array[Label] = []
var powers_box: VBoxContainer
var power_buttons: Dictionary = {}
var promo_panel: PanelContainer
var promo_backdrop: ColorRect
var pause_panel: PanelContainer
var pause_backdrop: ColorRect
var pause_box: VBoxContainer
var settings_box: VBoxContainer
var paused_label: Label
var sim_paused := false
var promo_list: VBoxContainer
var promo_scroll: ScrollContainer
var promo_key := ""
var promo_xp: Label
var minimap: Control
var overlay: Control
var gameover_panel: PanelContainer
var gameover_label: Label
var bottom: Control
var msgs: Array = []
var minimap_t := 0.0
var sel_cache: Array = []
var last_sel_sig := ""

func setup(_view: ClientView, _ctl: Controller) -> void:
	view = _view
	ctl = _ctl
	layer = 3
	_build()

func _style(c: Color, border := Color(0.25, 0.3, 0.38)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(6)
	return s

func _panel(c := Color(0.09, 0.1, 0.13, 0.94)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(c))
	return p

func _build() -> void:
	# ---- overlay (3D-anchored drawing) ----
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)

	# ---- top bar ----
	var top := _panel()
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.position = Vector2(8, 8)
	add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 18)
	top.add_child(th)
	cash_label = Label.new()
	cash_label.add_theme_font_size_override("font_size", 22)
	cash_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	th.add_child(cash_label)
	power_label = Label.new()
	power_label.add_theme_font_size_override("font_size", 18)
	th.add_child(power_label)
	rank_label = Label.new()
	rank_label.add_theme_font_size_override("font_size", 18)
	th.add_child(rank_label)
	promo_btn = Button.new()
	promo_btn.text = "Promotion"
	promo_btn.visible = false
	promo_btn.pressed.connect(_toggle_promo)
	th.add_child(promo_btn)
	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 16)
	time_label.modulate = Color(0.8, 0.8, 0.8)
	th.add_child(time_label)

	# superweapon timers (top centre)
	sw_label = Label.new()
	sw_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sw_label.position = Vector2(-200, 10)
	sw_label.size = Vector2(400, 30)
	sw_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sw_label.add_theme_font_size_override("font_size", 18)
	sw_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	add_child(sw_label)

	# ---- general's powers (top right) ----
	var pp := _panel()
	pp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pp.anchor_left = 1.0
	pp.anchor_right = 1.0
	pp.offset_left = -190
	pp.offset_right = -8
	pp.offset_top = 8
	pp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(pp)
	powers_box = VBoxContainer.new()
	pp.add_child(powers_box)
	var pl := Label.new()
	pl.text = "GENERAL'S POWERS"
	pl.add_theme_font_size_override("font_size", 12)
	pl.modulate = Color(0.7, 0.75, 0.8)
	powers_box.add_child(pl)

	# ---- promotion / tech tree modal ----
	promo_backdrop = ColorRect.new()
	promo_backdrop.color = Color(0, 0, 0, 0.55)
	promo_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	promo_backdrop.visible = false
	promo_backdrop.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			promo_backdrop.visible = false
			promo_panel.visible = false)
	add_child(promo_backdrop)
	var promo_center := CenterContainer.new()
	promo_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	promo_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(promo_center)
	promo_panel = _panel(Color(0.08, 0.09, 0.12, 0.98))
	promo_panel.visible = false
	promo_panel.custom_minimum_size = Vector2(800, 0)
	promo_center.add_child(promo_panel)
	promo_scroll = ScrollContainer.new()
	promo_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	promo_scroll.custom_minimum_size = Vector2(800, 400)
	promo_panel.add_child(promo_scroll)
	promo_list = VBoxContainer.new()
	promo_list.add_theme_constant_override("separation", 6)
	promo_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	promo_scroll.add_child(promo_list)
	get_viewport().size_changed.connect(func() -> void:
		if promo_panel.visible:
			_fit_promo())

	# ---- messages ----
	msg_box = VBoxContainer.new()
	msg_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	msg_box.anchor_top = 1.0
	msg_box.anchor_bottom = 1.0
	msg_box.offset_left = 12
	msg_box.offset_top = -BAR_H - 200
	msg_box.offset_bottom = -BAR_H - 10
	msg_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	msg_box.alignment = BoxContainer.ALIGNMENT_END
	msg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(msg_box)

	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.anchor_top = 1.0
	hint_label.anchor_bottom = 1.0
	hint_label.offset_left = -300
	hint_label.offset_right = 300
	hint_label.offset_top = -BAR_H - 34
	hint_label.offset_bottom = -BAR_H - 6
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 16)
	hint_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	add_child(hint_label)

	# ---- bottom command bar ----
	bottom = _panel(Color(0.08, 0.09, 0.11, 0.96))
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.anchor_top = 1.0
	bottom.offset_top = -BAR_H
	bottom.offset_bottom = 0
	bottom.offset_left = 0
	bottom.offset_right = 0
	add_child(bottom)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	bottom.add_child(bh)

	minimap = Control.new()
	minimap.custom_minimum_size = Vector2(BAR_H - 14, BAR_H - 14)
	minimap.draw.connect(_draw_minimap)
	minimap.gui_input.connect(_minimap_input)
	bh.add_child(minimap)

	var info := _panel(Color(0.11, 0.12, 0.15, 1.0))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(info)
	var iv := VBoxContainer.new()
	info.add_child(iv)
	info_title = Label.new()
	info_title.add_theme_font_size_override("font_size", 18)
	info_title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
	iv.add_child(info_title)
	info_body = RichTextLabel.new()
	info_body.bbcode_enabled = true
	info_body.fit_content = true
	info_body.scroll_active = false
	info_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_body.add_theme_font_size_override("normal_font_size", 14)
	iv.add_child(info_body)
	queue_box = HBoxContainer.new()
	queue_box.add_theme_constant_override("separation", 4)
	iv.add_child(queue_box)

	var gridp := _panel(Color(0.11, 0.12, 0.15, 1.0))
	bh.add_child(gridp)
	var grid := GridContainer.new()
	grid.columns = GRID_COLS
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	gridp.add_child(grid)
	for i in range(GRID_COLS * GRID_ROWS):
		var b := Button.new()
		b.custom_minimum_size = Vector2(124, 74)
		b.add_theme_font_size_override("font_size", 10)
		b.visible = false
		b.clip_text = false
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.pressed.connect(_on_grid.bind(i))
		grid.add_child(b)
		# requirement / status line drawn as a wrapping label over the bottom of the button
		var wl := Label.new()
		wl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		wl.offset_left = 3
		wl.offset_right = -3
		wl.offset_top = -19
		wl.offset_bottom = -4
		wl.grow_vertical = Control.GROW_DIRECTION_BEGIN
		wl.clip_text = true
		wl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		wl.add_theme_font_size_override("font_size", 10)
		wl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
		wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wl.visible = false
		b.add_child(wl)
		grid_why.append(wl)
		grid_buttons.append(b)
		grid_actions.append(null)

	# modal above the command bar (bar was added after it)
	move_child(promo_backdrop, -1)
	move_child(promo_panel.get_parent(), -1)

	# ---- pause menu ----
	pause_backdrop = ColorRect.new()
	pause_backdrop.color = Color(0, 0, 0, 0.5)
	pause_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_backdrop.visible = false
	add_child(pause_backdrop)
	var pause_center := CenterContainer.new()
	pause_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pause_center)
	pause_panel = _panel(Color(0.07, 0.08, 0.11, 0.98))
	pause_panel.visible = false
	pause_panel.custom_minimum_size = Vector2(420, 0)
	pause_center.add_child(pause_panel)
	pause_box = VBoxContainer.new()
	pause_box.add_theme_constant_override("separation", 8)
	pause_panel.add_child(pause_box)
	_build_pause_menu()
	paused_label = Label.new()
	paused_label.text = "PAUSED"
	paused_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	paused_label.position = Vector2(-100, 60)
	paused_label.size = Vector2(200, 40)
	paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paused_label.add_theme_font_size_override("font_size", 30)
	paused_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	paused_label.visible = false
	add_child(paused_label)

	# ---- game over / report ----
	var go_center := CenterContainer.new()
	go_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	go_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(go_center)
	gameover_panel = _panel(Color(0.05, 0.05, 0.07, 0.96))
	gameover_panel.visible = false
	go_center.add_child(gameover_panel)
	var gv := VBoxContainer.new()
	gv.name = "Box"
	gv.add_theme_constant_override("separation", 12)
	gameover_panel.add_child(gv)
	gameover_label = Label.new()
	gameover_label.add_theme_font_size_override("font_size", 36)
	gameover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gv.add_child(gameover_label)

func is_mouse_over_ui(p: Vector2) -> bool:
	var vs := get_viewport().get_visible_rect().size
	if p.y >= vs.y - BAR_H:
		return true
	if promo_panel.visible and promo_panel.get_global_rect().has_point(p):
		return true
	for c in [powers_box.get_parent(), cash_label.get_parent().get_parent()]:
		if (c as Control).get_global_rect().has_point(p):
			return true
	return false

# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------
func _process(dt: float) -> void:
	var st: Dictionary = view.pstate
	if not st.is_empty():
		cash_label.text = "$ %d" % int(st.get("cash", 0))
		var pp := int(st.get("pp", 0))
		var pu := int(st.get("pu", 0))
		power_label.text = "POWER %d / %d" % [pp, pu]
		power_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if st.get("low", false) else Color(0.5, 1.0, 0.5))
		var nxt := int(st.get("next", -1))
		rank_label.text = "General %s  (%d%s xp)" % ["★".repeat(int(st.get("rank", 1))), int(st.get("xp", 0)), "/%d" % nxt if nxt > 0 else ""]
		var pts := int(st.get("points", 0))
		promo_btn.visible = pts > 0
		promo_btn.text = "Promotion (%d)" % pts
		var t := int(st.get("time", 0.0))
		time_label.text = "%d:%02d" % [t / 60, t % 60]
		var sw: Dictionary = st.get("sw", {})
		var parts := []
		for p in sw:
			var rem := float(sw[p])
			var who := "Your" if int(p) == view.my_index else "ENEMY"
			parts.append("%s Particle Cannon: %s" % [who, "READY" if rem <= 0.0 else "%d:%02d" % [int(rem) / 60, int(rem) % 60]])
		sw_label.text = "   ".join(parts)
		_update_powers(st)
	_update_queue()
	minimap_t -= dt
	if minimap_t <= 0.0:
		minimap_t = 0.1
		minimap.queue_redraw()
	overlay.queue_redraw()
	hint_label.text = ctl.hint_text()
	# expire messages
	var now := Time.get_ticks_msec() / 1000.0
	for m in msgs.duplicate():
		if now > m["until"]:
			m["label"].queue_free()
			msgs.erase(m)
		elif now > m["until"] - 1.0:
			m["label"].modulate.a = m["until"] - now
	if last_sel_sig != ctl.selection_signature():
		refresh_selection()

func add_message(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 1, 0.85))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	msg_box.add_child(l)
	msgs.append({"label": l, "until": Time.get_ticks_msec() / 1000.0 + 6.0})
	while msgs.size() > 6:
		var m: Dictionary = msgs.pop_front()
		m["label"].queue_free()

func show_gameover(text: String, rep: Array = []) -> void:
	gameover_label.text = text
	var gv: VBoxContainer = gameover_panel.get_node("Box")
	for c in gv.get_children():
		if c != gameover_label:
			c.queue_free()
	if not rep.is_empty():
		var t := int(rep[0].get("time", 0))
		var sub := Label.new()
		sub.text = "Match time %d:%02d" % [t / 60, t % 60]
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.modulate = Color(0.75, 0.75, 0.75)
		gv.add_child(sub)
		var grid := GridContainer.new()
		grid.columns = 9
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 4)
		gv.add_child(grid)
		for h in ["Player", "Team", "Result", "Rank", "Units built", "Units lost", "Units killed", "Structures built / lost / killed", "Cash earned"]:
			var l := Label.new()
			l.text = h
			l.add_theme_font_size_override("font_size", 12)
			l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
			grid.add_child(l)
		for i in range(rep.size()):
			var r: Dictionary = rep[i]
			var col: Color = Data.TEAM_COLORS[i % Data.TEAM_COLORS.size()]
			var vals := [r.get("name", "?"), "Team %d" % (int(r.get("team", i)) + 1), "Defeated" if r.get("defeated", false) else "Survived",
				"★".repeat(int(r.get("rank", 1))), str(r.get("units_built", 0)), str(r.get("units_lost", 0)), str(r.get("units_killed", 0)),
				"%d / %d / %d" % [r.get("bld_built", 0), r.get("bld_lost", 0), r.get("bld_killed", 0)], "$%d" % int(r.get("cash_earned", 0))]
			for k in range(vals.size()):
				var l := Label.new()
				l.text = str(vals[k])
				l.add_theme_font_size_override("font_size", 13)
				if k == 0:
					l.add_theme_color_override("font_color", col)
				elif k == 2:
					l.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if r.get("defeated", false) else Color(0.5, 0.9, 0.6))
				grid.add_child(l)
	var back := Button.new()
	back.text = "Return to menu"
	back.pressed.connect(func() -> void: Main.I.return_to_menu())
	gv.add_child(back)
	gameover_panel.visible = true
	pause_panel.visible = false
	pause_backdrop.visible = false

# ---------------------------------------------------------------------------
# Pause menu / settings
# ---------------------------------------------------------------------------
func _build_pause_menu() -> void:
	var title := Label.new()
	title.text = "GAME MENU"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_box.add_child(title)
	var resume := Button.new()
	resume.text = "Resume  (Esc)"
	resume.pressed.connect(toggle_pause_menu)
	pause_box.add_child(resume)
	var settings_hdr := Label.new()
	settings_hdr.text = "SETTINGS"
	settings_hdr.add_theme_font_size_override("font_size", 12)
	settings_hdr.modulate = Color(0.7, 0.75, 0.8)
	pause_box.add_child(settings_hdr)
	settings_box = VBoxContainer.new()
	pause_box.add_child(settings_box)
	var cfg := Settings.load_cfg()
	for pair in [["Master volume", "master"], ["Sound effects", "sfx"], ["Voices", "voice"], ["Music", "music"]]:
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = pair[0]
		l.custom_minimum_size = Vector2(150, 0)
		h.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(cfg.get(pair[1], 1.0))
		sl.custom_minimum_size = Vector2(200, 0)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = pair[1]
		sl.value_changed.connect(func(v: float) -> void:
			Settings.set_value(key, v)
			Settings.apply())
		h.add_child(sl)
		settings_box.add_child(h)
	var edge := CheckButton.new()
	edge.text = "Edge scrolling"
	edge.button_pressed = bool(cfg.get("edge_scroll", true))
	edge.toggled.connect(func(on: bool) -> void:
		Settings.set_value("edge_scroll", on)
		Settings.apply()
		view.camera.edge_scroll = on)
	settings_box.add_child(edge)
	var leave := Button.new()
	leave.text = "Leave match"
	leave.pressed.connect(func() -> void: Main.I.return_to_menu())
	pause_box.add_child(leave)
	var quit := Button.new()
	quit.text = "Quit to desktop"
	quit.pressed.connect(func() -> void: get_tree().quit())
	pause_box.add_child(quit)

func toggle_pause_menu() -> void:
	if gameover_panel.visible:
		return
	var open := not pause_panel.visible
	pause_panel.visible = open
	pause_backdrop.visible = open
	view.camera.enabled = not open
	# single-player: actually freeze the simulation
	view.send({"t": "pause", "on": open})

func set_paused(on: bool) -> void:
	sim_paused = on
	paused_label.visible = on

func close_promo() -> void:
	promo_panel.visible = false
	promo_backdrop.visible = false

# ---------------------------------------------------------------------------
# Selection / command grid
# ---------------------------------------------------------------------------
func refresh_selection() -> void:
	last_sel_sig = ctl.selection_signature()
	var sel: Array = ctl.selected_puppets()
	for i in range(grid_buttons.size()):
		grid_buttons[i].visible = false
		grid_actions[i] = null
	for c in queue_box.get_children():
		c.queue_free()
	if sel.is_empty():
		info_title.text = ""
		info_body.text = "[color=#889]Left-drag: select   Right-click: move / attack   Ctrl+right-click or X: force attack   A: attack-move   S: stop   G: guard area\nN: next Dozer   B / F / I / C / Y: Barracks / War Factory / Airfield / Command Center / Supply Center   Ctrl+1-9: groups   H: home\nArrows / edge / middle-drag: scroll   Wheel: zoom   Q / E: rotate camera[/color]"
		return
	var mine: bool = sel[0].team == view.my_index
	if sel.size() == 1:
		var p: Puppet = sel[0]
		var d := p.def
		info_title.text = "%s%s" % [d["name"], "" if mine else "  (%s)" % (Data.TEAM_NAMES[p.team] if p.team >= 0 else "neutral")]
		var hp := ""
		var hpd: Dictionary = view.pstate.get("hp", {})
		if hpd.has(p.id):
			hp = "HP %d / %d" % [hpd[p.id][0], hpd[p.id][1]]
		else:
			hp = "HP %d%%" % int(p.hp_frac * 100)
		var lines := [hp]
		if p.level > 0:
			lines.append(["", "Veteran", "Elite", "Heroic"][p.level])
		if p.is_building and not p.complete:
			lines.append("Under construction: %d%%" % p.aux)
		if p.type == "supply_dock":
			var docks: Dictionary = view.pstate.get("docks", {})
			lines.append("Supplies: $%d" % (int(docks.get(p.id, p.boxes)) * Data.BOX_VALUE))
		if p.cat == "air" and p.def.get("jet", false):
			lines.append("Ammo: %d" % p.aux)
		if p.type == "chinook" and (p.flags & 32) != 0:
			lines.append("Carrying %d boxes" % p.aux)
		if p.is_building and p.aux > 100:
			lines.append("BEING CAPTURED %d%%" % (p.aux - 100))
		lines.append("[color=#aab]%s[/color]" % d.get("desc", ""))
		info_body.text = "\n".join(lines)
	else:
		var counts := {}
		for p in sel:
			counts[p.type] = counts.get(p.type, 0) + 1
		var parts := []
		for t in counts:
			parts.append("%d× %s" % [counts[t], Data.def(t)["name"]])
		info_title.text = "%d units selected" % sel.size()
		info_body.text = ", ".join(parts)
	if not mine:
		return
	var actions := []
	var single: Puppet = sel[0] if sel.size() == 1 else null
	var all_units := true
	for p in sel:
		if p.is_building:
			all_units = false
	if single != null and single.is_building and single.complete:
		var d := single.def
		for ut in d.get("produces", []):
			var ud: Dictionary = Data.UNITS[ut]
			actions.append({"label": "%s\n$%d" % [ud["name"], ud["cost"]], "icon": ut, "tip": "%s\n%s\nBuild time %ds" % [ud["name"], ud.get("desc", ""), int(ud["time"])],
				"cb": func() -> void: ctl.produce(single.id, ut), "enabled": view.can_afford(ud["cost"]) and view.unit_prereq_text(ut) == "", "why": view.unit_prereq_text(ut)})
		for uid in d.get("upgrades", []):
			var ud: Dictionary = Data.UPGRADES[uid]
			var done: bool = view.has_upgrade(uid, single.id)
			var researching: bool = view.is_researching(uid)
			var lbl := "$%d" % ud["cost"]
			if done:
				lbl = "DONE"
			elif researching:
				lbl = "researching"
			actions.append({"label": "%s\n%s" % [ud["name"], lbl], "icon": uid, "tip": "%s\n%s" % [ud["name"], ud["desc"]],
				"cb": func() -> void: ctl.upgrade(single.id, uid), "enabled": not done and not researching and view.can_afford(ud["cost"])})
		if d.has("superweapon"):
			var ready: bool = view.sw_ready(single.team)
			actions.append({"label": "FIRE\nParticle Cannon", "tip": "Select a target for the beam. Steer it with the mouse while it fires.", "cb": func() -> void: ctl.sw_mode(single.id), "enabled": ready})
		if d.has("produces"):
			actions.append({"label": "Set rally", "tip": "Click where new units should gather", "cb": func() -> void: ctl.rally_mode(single.id), "enabled": true})
		actions.append({"label": "Sell\n+$%d" % int(d["cost"] * Data.REFUND), "tip": "Sell this structure for half its cost", "cb": func() -> void: ctl.sell(single.id), "enabled": true})
	elif single != null and single.is_building and not single.complete:
		actions.append({"label": "Cancel\n+$%d" % int(single.def["cost"] * (1.0 - single.aux / 100.0)), "tip": "Cancel construction (refund unspent cost)", "cb": func() -> void: ctl.sell(single.id), "enabled": true})
	elif all_units:
		var has_builder := false
		for p in sel:
			if p.def.get("builder", false):
				has_builder = true
		if has_builder:
			for bt in Data.BUILDINGS:
				var bd: Dictionary = Data.BUILDINGS[bt]
				if bd.get("neutral", false):
					continue
				var why: String = view.building_prereq_text(bt)
				actions.append({"label": "%s\n$%d" % [bd["name"], bd["cost"]], "icon": bt, "tip": "%s\n%s\nPower %+d  ·  %ds" % [bd["name"], bd.get("desc", ""), bd.get("power", 0), int(bd["time"])],
					"cb": func() -> void: ctl.begin_place(bt), "enabled": why == "" and view.can_afford(bd["cost"]), "why": why})
		else:
			actions.append({"label": "Attack-move (A)", "tip": "Move and engage anything on the way", "cb": func() -> void: ctl.amove_mode(), "enabled": true})
			actions.append({"label": "Force attack (X)", "tip": "Fire at a position or at anything, including neutral or own structures (Ctrl+right-click)", "cb": func() -> void: ctl.force_mode(), "enabled": true})
			actions.append({"label": "Stop (S)", "tip": "Halt", "cb": func() -> void: ctl.stop(), "enabled": true})
			actions.append({"label": "Guard (G)", "tip": "Hold here and engage anything that comes close, returning afterwards. Aircraft loiter overhead and go home to rearm.", "cb": func() -> void: ctl.guard(), "enabled": true})
			var has_ranger := false
			for p in sel:
				if p.type == "ranger":
					has_ranger = true
			if has_ranger:
				var can: bool = view.has_upgrade("capture")
				actions.append({"label": "Capture", "icon": "capture", "tip": "Rangers take over an enemy or neutral structure (20 s next to it)." + ("" if can else "\nRequires the Capture Building upgrade at the Barracks."), "cb": func() -> void: ctl.capture_mode(), "enabled": can})
	for i in range(mini(actions.size(), grid_buttons.size())):
		var a: Dictionary = actions[i]
		var b := grid_buttons[i]
		b.visible = true
		b.text = a["label"]
		b.icon = view.icons.get_icon(a["icon"]) if a.has("icon") else null
		var why: String = a.get("why", "")
		b.tooltip_text = a["tip"] + (("\n" + why) if why != "" else "")
		b.disabled = not a["enabled"]
		grid_why[i].visible = why != ""
		grid_why[i].text = why
		if why != "":
			b.text = a["label"] + "\n "
			b.add_theme_color_override("font_disabled_color", Color(0.8, 0.6, 0.55))
		elif not a["enabled"]:
			b.add_theme_color_override("font_disabled_color", Color(0.95, 0.8, 0.3))
		else:
			b.remove_theme_color_override("font_disabled_color")
		grid_actions[i] = a["cb"]

func _on_grid(i: int) -> void:
	var cb = grid_actions[i]
	if cb != null:
		Audio.I.ui("ui_click", -8.0)
		cb.call()

func _update_queue() -> void:
	var sel: Array = ctl.selected_puppets()
	if sel.size() != 1 or not sel[0].is_building:
		if queue_box.get_child_count() > 0:
			for c in queue_box.get_children():
				c.queue_free()
		return
	var bid: int = sel[0].id
	var queues: Dictionary = view.pstate.get("queues", {})
	var research: Dictionary = view.pstate.get("research", {})
	var q: Array = queues.get(bid, [])
	var want := q.size() + (1 if research.has(bid) else 0)
	if queue_box.get_child_count() != want:
		for c in queue_box.get_children():
			c.queue_free()
		for i in range(q.size()):
			var b := Button.new()
			b.custom_minimum_size = Vector2(90, 40)
			b.add_theme_font_size_override("font_size", 11)
			b.tooltip_text = "Click to cancel"
			b.pressed.connect(func() -> void: ctl.cancel(bid, i))
			queue_box.add_child(b)
		if research.has(bid):
			var b := Button.new()
			b.custom_minimum_size = Vector2(110, 40)
			b.add_theme_font_size_override("font_size", 11)
			b.tooltip_text = "Click to cancel research"
			b.pressed.connect(func() -> void: ctl.cancel_upgrade(bid))
			queue_box.add_child(b)
	var kids := queue_box.get_children()
	for i in range(q.size()):
		if i < kids.size():
			(kids[i] as Button).text = "%s\n%d%%" % [Data.UNITS[q[i][0]]["name"], int(q[i][1] * 100)]
	if research.has(bid) and kids.size() > q.size():
		var r: Array = research[bid]
		(kids[q.size()] as Button).text = "%s\n%d%%" % [Data.UPGRADES[r[0]]["name"], int(r[1] * 100)]

# ---------------------------------------------------------------------------
# General's powers
# ---------------------------------------------------------------------------
func _update_powers(st: Dictionary) -> void:
	var owned: Dictionary = st.get("powers", {})
	var cds: Dictionary = st.get("cds", {})
	for pid in Data.POWERS:
		var pd: Dictionary = Data.POWERS[pid]
		if pd["kind"] != "ability":
			continue
		var have := int(owned.get(pid, 0)) > 0
		if not have:
			if power_buttons.has(pid):
				power_buttons[pid].queue_free()
				power_buttons.erase(pid)
			continue
		if not power_buttons.has(pid):
			var b := Button.new()
			b.custom_minimum_size = Vector2(170, 40)
			b.add_theme_font_size_override("font_size", 12)
			b.tooltip_text = pd["desc"]
			b.icon = view.icons.get_icon(pid)
			b.expand_icon = true
			b.pressed.connect(func() -> void: ctl.power_mode(pid))
			powers_box.add_child(b)
			power_buttons[pid] = b
		var b: Button = power_buttons[pid]
		var rem := float(cds.get(pid, 0.0))
		var lvl := int(owned.get(pid, 1))
		var name: String = pd["name"] + (" %d" % lvl if int(pd.get("levels", 1)) > 1 else "")
		if rem > 0.0:
			b.text = "%s  %d:%02d" % [name, int(rem) / 60, int(rem) % 60]
			b.disabled = true
		else:
			b.text = "%s  READY" % name
			b.disabled = false
	if promo_panel.visible:
		var key := str([st.get("rank", 1), st.get("points", 0), st.get("powers", {})])
		if key != promo_key:
			_fill_promo(st)
		elif is_instance_valid(promo_xp):
			promo_xp.text = _promo_xp_text(st)

func _toggle_promo() -> void:
	promo_panel.visible = not promo_panel.visible
	promo_backdrop.visible = promo_panel.visible
	if promo_panel.visible:
		promo_key = ""
		_fill_promo(view.pstate)

## Tech-tree style promotion screen: one row per rank tier, cards with icons,
## unlocked / available / locked states.
func _fill_promo(st: Dictionary) -> void:
	for c in promo_list.get_children():
		promo_list.remove_child(c)
		c.queue_free()
	var rank := int(st.get("rank", 1))
	var pts := int(st.get("points", 0))
	var owned: Dictionary = st.get("powers", {})
	var title := Label.new()
	title.text = "GENERAL'S PROMOTION  —  rank %d %s  —  %d point%s to spend" % [rank, "★".repeat(rank), pts, "" if pts == 1 else "s"]
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	promo_list.add_child(title)
	promo_key = str([st.get("rank", 1), st.get("points", 0), st.get("powers", {})])
	var xp_l := Label.new()
	promo_xp = xp_l
	xp_l.text = _promo_xp_text(st)
	xp_l.add_theme_font_size_override("font_size", 12)
	xp_l.modulate = Color(0.75, 0.75, 0.75)
	promo_list.add_child(xp_l)
	for tier in [1, 3, 5]:
		var hdr := Label.new()
		hdr.text = "RANK %d%s" % [tier, "  ✓" if rank >= tier else "  (locked)"]
		hdr.add_theme_font_size_override("font_size", 13)
		hdr.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6) if rank >= tier else Color(0.55, 0.55, 0.6))
		promo_list.add_child(hdr)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		promo_list.add_child(row)
		for pid in Data.POWERS:
			var pd: Dictionary = Data.POWERS[pid]
			if int(pd["rank"]) != tier:
				continue
			var lvl := int(owned.get(pid, 0))
			var maxl := int(pd.get("levels", 1))
			var unlocked := lvl >= maxl
			var can: bool = rank >= tier and pts > 0 and not unlocked and not pd.get("auto", false)
			var card := _panel(Color(0.14, 0.17, 0.22, 1.0) if unlocked else (Color(0.12, 0.13, 0.16, 1.0) if rank >= tier else Color(0.09, 0.09, 0.1, 1.0)))
			card.custom_minimum_size = Vector2(150, 0)
			var cv := VBoxContainer.new()
			card.add_child(cv)
			var ic := TextureRect.new()
			ic.texture = view.icons.get_icon(pid)
			ic.custom_minimum_size = Vector2(48, 48)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.modulate = Color.WHITE if rank >= tier else Color(0.45, 0.45, 0.45)
			cv.add_child(ic)
			var nm := Label.new()
			nm.text = pd["name"] + ((" %d/%d" % [lvl, maxl]) if maxl > 1 else "")
			nm.add_theme_font_size_override("font_size", 12)
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cv.add_child(nm)
			var ds := Label.new()
			ds.text = pd["desc"]
			ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ds.add_theme_font_size_override("font_size", 10)
			ds.modulate = Color(0.75, 0.75, 0.75)
			ds.custom_minimum_size = Vector2(134, 34)
			cv.add_child(ds)
			var st_l := Label.new()
			st_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			st_l.add_theme_font_size_override("font_size", 12)
			if pd.get("auto", false):
				st_l.text = "Granted at rank 5" if not unlocked else "UNLOCKED ✓"
				st_l.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6) if unlocked else Color(0.7, 0.7, 0.5))
				cv.add_child(st_l)
			elif unlocked:
				st_l.text = "UNLOCKED ✓"
				st_l.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
				cv.add_child(st_l)
			elif can:
				var b := Button.new()
				b.text = "Unlock (1 pt)" if lvl == 0 else "Upgrade (1 pt)"
				b.pressed.connect(func() -> void:
					Audio.I.ui("ui_click", -6.0)
					ctl.buy_power(pid))
				cv.add_child(b)
			else:
				st_l.text = "Needs rank %d" % tier if rank < tier else "No points left"
				st_l.add_theme_color_override("font_color", Color(0.9, 0.45, 0.4))
				cv.add_child(st_l)
			row.add_child(card)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void:
		promo_panel.visible = false
		promo_backdrop.visible = false)
	promo_list.add_child(close)
	_fit_promo.call_deferred()

func _promo_xp_text(st: Dictionary) -> String:
	var nxt := int(st.get("next", -1))
	return "%d xp%s  ·  earn experience by destroying enemy units and structures" % [int(st.get("xp", 0)), ("  (next rank at %d)" % nxt) if nxt > 0 else "  (max rank)"]

## Size the scroll area to its content but never taller than the screen, so the
## modal stays centred and the last rank row is reachable (scrolls if needed).
func _fit_promo() -> void:
	if not is_instance_valid(promo_scroll):
		return
	var want: float = promo_list.get_combined_minimum_size().y + 4.0
	var cap: float = get_viewport().get_visible_rect().size.y - 90.0
	promo_scroll.custom_minimum_size = Vector2(800, clampf(want, 200.0, cap))
	promo_panel.reset_size()

# ---------------------------------------------------------------------------
# Minimap
# ---------------------------------------------------------------------------
func _mm_scale() -> float:
	return minimap.size.x / float(view.map["size"])

func _draw_minimap() -> void:
	var s := _mm_scale()
	var sz := minimap.size
	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.55, 0.47, 0.33))
	var mv: MapView = view.map_view
	# fog: explored / visible
	var fc: int = mv.fog_cells
	var cs := sz.x / fc
	for y in range(fc):
		for x in range(fc):
			var i := y * fc + x
			if mv.explored[i] == 0:
				minimap.draw_rect(Rect2(x * cs, y * cs, cs + 0.5, cs + 0.5), Color(0, 0, 0))
			elif mv.visible_cells[i] == 0:
				minimap.draw_rect(Rect2(x * cs, y * cs, cs + 0.5, cs + 0.5), Color(0, 0, 0, 0.45))
	for pr in view.map["props"]:
		var fp: Vector2i = pr["fp"]
		if fp == Vector2i.ZERO:
			continue
		var p: Vector2 = pr["p"]
		var col := Color(0.35, 0.3, 0.25) if pr.get("kind", "") != "tree" else Color(0.2, 0.4, 0.2)
		minimap.draw_rect(Rect2((p - Vector2(fp) * 1.0) * s, Vector2(fp) * 2.0 * s), col)
	for pu in view.puppets.values():
		var p: Puppet = pu
		if p.ghost and not p.is_building:
			continue
		var col := Color(0.8, 0.8, 0.6)
		if p.team >= 0:
			col = Data.TEAM_COLORS[p.team]
		elif p.type == "supply_dock":
			col = Color(1.0, 0.85, 0.2)
		elif p.type == "oil_derrick":
			col = Color(0.3, 0.3, 0.3)
		var pt := Vector2(p.cur_pos.x, p.cur_pos.z) * s
		if p.is_building:
			var fp: Vector2 = Data.footprint_size(p.type) * s
			minimap.draw_rect(Rect2(pt - fp * 0.5, fp), col)
		else:
			minimap.draw_rect(Rect2(pt - Vector2(1.5, 1.5), Vector2(3, 3)), col)
	# alerts
	var now := Time.get_ticks_msec() / 1000.0
	for a in view.alerts:
		if now - a["t"] < 4.0:
			var r := 4.0 + fmod(now * 2.0, 1.0) * 8.0
			minimap.draw_arc(a["p"] * s, r, 0, TAU, 16, Color(1, 0.3, 0.2), 1.5)
	# camera view: a rectangle around the camera target, rotated with the camera
	var cam: RtsCamera = view.camera
	var half := Vector2(cam.height * 0.95, cam.height * 0.62)
	var centre := Vector2(cam.target.x, cam.target.z)
	var pts := PackedVector2Array()
	for c in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		pts.append(((centre + c.rotated(-cam.yaw)) * s).clamp(Vector2.ZERO, sz))
	pts.append(pts[0])
	minimap.draw_polyline(pts, Color(1, 1, 1, 0.85), 1.0)
	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.3, 0.35, 0.4), false, 1.0)

func _minimap_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton or (ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0):
		var pos: Vector2 = ev.position / _mm_scale()
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if not mb.pressed:
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				view.camera.jump_to(pos)
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				ctl.minimap_command(pos)
		else:
			view.camera.jump_to(pos)

# ---------------------------------------------------------------------------
# Overlay: selection box, health bars, rally lines
# ---------------------------------------------------------------------------
func _draw_overlay() -> void:
	var cam: RtsCamera = view.camera
	if cam == null:
		return
	var box: Rect2 = ctl.drag_rect()
	if box.size != Vector2.ZERO:
		overlay.draw_rect(box, Color(0.5, 1.0, 0.5, 0.12))
		overlay.draw_rect(box, Color(0.5, 1.0, 0.5, 0.9), false, 1.0)
	var vs := overlay.size
	for pu in view.puppets.values():
		var p: Puppet = pu
		if p.ghost and not p.is_building:
			continue
		var has_ammo: bool = p.team == view.my_index and ((p.cat == "air" and p.def.get("jet", false)) or p.type == "comanche")
		var show: bool = p.selected or p.hovered or (p.hp_frac < 0.999 and (p.team == view.my_index or p.selected)) or (p.is_building and not p.complete) or has_ammo
		if not show:
			continue
		var top := p.cur_pos + Vector3(0, float(p.def.get("height", 3.0)) if p.is_building else float(p.def.get("length", 2.0)) * 0.5 + 1.0, 0)
		if cam.is_behind(top):
			continue
		var sp := cam.to_screen(top)
		if sp.x < -50 or sp.y < -50 or sp.x > vs.x + 50 or sp.y > vs.y - BAR_H:
			continue
		var w := 44.0 if not p.is_building else 70.0
		var r := Rect2(sp.x - w * 0.5, sp.y - 6, w, 5)
		overlay.draw_rect(r, Color(0, 0, 0, 0.7))
		var f := p.hp_frac
		var c := Color(0.2, 0.9, 0.2)
		if f < 0.33:
			c = Color(0.95, 0.2, 0.15)
		elif f < 0.66:
			c = Color(0.95, 0.8, 0.2)
		overlay.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2((w - 2) * f, 3)), c)
		if p.is_building and not p.complete:
			overlay.draw_rect(Rect2(r.position + Vector2(0, 6), Vector2(w * p.aux / 100.0, 3)), Color(0.4, 0.7, 1.0))
		elif p.is_building and p.aux > 100:
			overlay.draw_rect(Rect2(r.position + Vector2(0, 6), Vector2(w * (p.aux - 100) / 100.0, 3)), Color(1.0, 0.4, 0.9))
		if p.level > 0 and not p.is_building:
			overlay.draw_string(ThemeDB.fallback_font, sp + Vector2(w * 0.5 + 3, 0), "★".repeat(p.level), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.3))
		# ammo pips: jets (aux = missiles left), Comanche rocket pods (aux2)
		var pips := -1
		var pip_max := 0
		if p.cat == "air" and p.def.get("jet", false):
			pips = p.aux
			pip_max = int(Data.WEAPONS[p.def["weapons"][0]].get("clip", 0))
		elif p.type == "comanche" and view.has_upgrade("rocket_pods"):
			pips = p.aux2
			pip_max = int(Data.WEAPONS["comanche_rockets"].get("clip", 0))
		if pips >= 0 and pip_max > 0 and p.team == view.my_index:
			var shown := mini(pip_max, 20)
			var pw := (w - 2.0) / shown
			for k in range(shown):
				var filled := k < int(round(float(pips) / pip_max * shown))
				overlay.draw_rect(Rect2(r.position + Vector2(1 + k * pw, 10), Vector2(maxf(pw - 1.0, 1.0), 3)), Color(0.3, 0.8, 1.0) if filled else Color(0.15, 0.15, 0.2, 0.8))
	# guard areas of selected units
	var guard: Dictionary = view.pstate.get("guard", {})
	for p in ctl.selected_puppets():
		if not p.is_building and guard.has(p.id):
			var g: Array = guard[p.id]
			var ring := PackedVector2Array()
			var ok := true
			for i in range(25):
				var a := TAU * i / 24.0
				var wp := Vector3(g[0] + cos(a) * g[2], 0.3, g[1] + sin(a) * g[2])
				if cam.is_behind(wp):
					ok = false
					break
				ring.append(cam.to_screen(wp))
			if ok:
				overlay.draw_polyline(ring, Color(0.4, 0.9, 1.0, 0.6), 1.5)
	# rally points for selected buildings
	var rally: Dictionary = view.pstate.get("rally", {})
	for p in ctl.selected_puppets():
		if p.is_building and rally.has(p.id):
			var rp: Array = rally[p.id]
			var a := cam.to_screen(p.cur_pos + Vector3(0, 1, 0))
			var b := cam.to_screen(Vector3(rp[0], 0.5, rp[1]))
			if not cam.is_behind(Vector3(rp[0], 0.5, rp[1])):
				overlay.draw_line(a, b, Color(0.4, 1.0, 0.5, 0.7), 1.5)
				overlay.draw_circle(b, 4.0, Color(0.4, 1.0, 0.5))
