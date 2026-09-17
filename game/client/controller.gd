class_name Controller
extends Node
## Player input: selection, orders, building placement, targeting modes, control groups.

const DRAG_MIN := 6.0
const PICK_RADIUS := 22.0

var view: ClientView
var cam: RtsCamera
var selected: Array[int] = []
var groups: Dictionary = {}          # 1..9 -> Array[int]
var mode := ""                       # "", "place", "amove", "rally", "power", "sw", "capture"
var mode_arg = null
var place_type := ""
var ghost: Node3D = null
var ghost_mesh: MeshInstance3D = null
var drag_start := Vector2(-1, -1)
var dragging := false
var mouse_pos := Vector2.ZERO
var last_click_t := 0.0
var last_click_id := -1
var hover_id := -1
var steer_t := 0.0
var sig := ""
var place_yaw := 0.0
var place_press := Vector2(-1, -1)      # screen point where LMB went down in place mode
var place_rotating := false
var guard_ring: MeshInstance3D = null
var dozer_cycle := 0
var guard_press := Vector2(-1, -1)      # screen point where LMB went down in guard mode
var guard_centre := Vector2.ZERO        # ground point of that press
var guard_radius := World.GUARD_RADIUS
var rmb_press := Vector2(-1, -1)
var cursor_kind := ""
var rmb_dragged := false

func setup(_view: ClientView) -> void:
	view = _view
	cam = view.camera

func selected_puppets() -> Array:
	var out := []
	for id in selected:
		var p = view.puppets.get(id)
		if p != null:
			out.append(p)
	return out

func selection_signature() -> String:
	return sig

## Pointer shows what's "equipped": the mode, or attack/repair when hovering a valid target.
func _update_cursor() -> void:
	var kind := ""
	match mode:
		"place":
			kind = "build"
		"amove":
			kind = "amove"
		"guard":
			kind = "guard"
		"force":
			kind = "force"
		"capture":
			kind = "capture"
		"rally":
			kind = "rally"
		"power":
			kind = "power"
		"sw":
			kind = "sw"
		"beacon":
			kind = "beacon"
		_:
			if view.pstate.get("beam", false):
				kind = "sw"   # steering the beam: keep the reticle until it ends or you click
			var hp: Puppet = view.puppets.get(hover_id) if hover_id >= 0 else null
			var units := _own_units_selected()
			if hp != null and not units.is_empty():
				if hp.team >= 0 and not view.is_ally(hp.team):
					kind = "attack"
				elif hp.is_building and hp.team == view.my_index and hp.hp_frac < 0.999 and _first_builder() >= 0:
					kind = "repair"
	if kind != cursor_kind:
		cursor_kind = kind
		Cursors.apply(kind)

func _refresh_sig() -> void:
	_update_cursor()
	var parts := []
	for id in selected:
		var p = view.puppets.get(id)
		if p != null:
			parts.append("%d:%s:%d" % [id, str(p.complete), p.level])
	sig = ",".join(parts) + "|" + mode + "|" + str(view.pstate.get("cash", 0)) + "|" + str(view.pstate.get("beam", false))

func hint_text() -> String:
	match mode:
		"place":
			return "Place %s  ·  click to build, hold and drag to rotate, right-click / Esc to cancel" % Data.BUILDINGS[place_type]["name"]
		"amove":
			return "Attack-move: click a destination"
		"guard":
			return "Guard area: click where to guard, hold and drag to set the radius (G again = guard here)"
		"beacon":
			return "Beacon: click where your team should look"
		"force":
			return "Force attack: click a target or the ground"
		"capture":
			return "Capture: click an enemy or neutral structure"
		"rally":
			return "Click to set the rally point"
		"power":
			return "%s: click a target" % Data.POWERS[mode_arg]["name"]
		"sw":
			return "PARTICLE CANNON: click a target, then steer with the mouse"
	if view.pstate.get("beam", false):
		return "Particle beam active - click where it should crawl to next (right-click to leave it)"
	return ""

func drag_rect() -> Rect2:
	if not dragging:
		return Rect2()
	var a := drag_start
	var b := mouse_pos
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(absf(a.x - b.x), absf(a.y - b.y)))

# ---------------------------------------------------------------------------
# Selection helpers
# ---------------------------------------------------------------------------
func set_selection(ids: Array) -> void:
	for p in selected_puppets():
		p.selected = false
	selected.clear()
	for id in ids:
		if view.puppets.has(id):
			selected.append(id)
			view.puppets[id].selected = true
	if mode != "sw" and mode != "power":
		mode = ""
		_clear_ghost()
	_refresh_sig()
	if not ids.is_empty():
		Audio.I.ui("ui_select", -10.0)
		var first: Puppet = view.puppets.get(ids[0])
		if first != null and first.team == view.my_index and not first.is_building:
			Audio.I.voice(first.type, "select", true)   # always answer a click, like Generals

func _puppet_at(screen: Vector2) -> Puppet:
	var best: Puppet = null
	var best_d := PICK_RADIUS
	var best_is_unit := false
	for pu in view.puppets.values():
		var p: Puppet = pu
		if p.ghost and not p.is_building:
			continue
		var centre := p.cur_pos + Vector3(0, 0.8 if not p.is_building else 2.0, 0)
		if cam.is_behind(centre):
			continue
		var sp := cam.to_screen(centre)
		var rect := p.screen_rect(cam)
		if p.is_building:
			if rect.size != Vector2.ZERO and rect.grow(2.0).has_point(screen) and not best_is_unit:
				var d := sp.distance_to(screen)
				if best == null or best.is_building and d < best_d:
					best = p
					best_d = d
			continue
		var d := sp.distance_to(screen)
		if rect.size != Vector2.ZERO and rect.grow(3.0).has_point(screen):
			d = minf(d, PICK_RADIUS * 0.5)
		if p.team != view.my_index:
			d += 4.0
		if d < best_d or (best != null and best.is_building and d <= PICK_RADIUS):
			best_d = d
			best = p
			best_is_unit = true
	return best

func _select_box(r: Rect2, additive: bool) -> void:
	var ids := []
	if additive:
		ids = selected.duplicate()
	for pu in view.puppets.values():
		var p: Puppet = pu
		if p.team != view.my_index or p.is_building or p.ghost or p.def.get("drone", false) or p.type == "spy_drone":
			continue
		if cam.is_behind(p.cur_pos):
			continue
		var sp := cam.to_screen(p.cur_pos + Vector3(0, 0.8, 0))
		if r.has_point(sp) and not ids.has(p.id):
			ids.append(p.id)
	if ids.is_empty() and not additive:
		set_selection([])
	elif not ids.is_empty():
		set_selection(ids)

func _select_same_type_on_screen(type: String) -> void:
	var ids := []
	var vs := get_viewport().get_visible_rect().size
	for pu in view.puppets.values():
		var p: Puppet = pu
		if p.team != view.my_index or p.type != type or p.ghost:
			continue
		if cam.is_behind(p.cur_pos):
			continue
		var sp := cam.to_screen(p.cur_pos)
		if sp.x >= 0 and sp.y >= 0 and sp.x <= vs.x and sp.y <= vs.y - Hud.BAR_H:
			ids.append(p.id)
	if not ids.is_empty():
		set_selection(ids)

func _own_units_selected() -> Array:
	var out := []
	for p in selected_puppets():
		if p.team == view.my_index and not p.is_building:
			out.append(p.id)
	return out

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _unhandled_input(ev: InputEvent) -> void:
	if view.game_over:
		return
	if view.hud.pause_panel.visible and not (ev is InputEventKey and (ev.keycode == KEY_ESCAPE or ev.keycode == KEY_F10)):
		return
	if ev is InputEventMouseMotion:
		mouse_pos = ev.position
		# a release that happened outside the window never reaches us: trust the live button state
		if rmb_press.x >= 0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			rmb_press = Vector2(-1, -1)
			rmb_dragged = false
		if drag_start.x >= 0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			drag_start = Vector2(-1, -1)
			dragging = false
		if rmb_press.x >= 0:
			# right-drag scrolls the map (Generals); the order is only given if the mouse didn't move
			if rmb_dragged or mouse_pos.distance_to(rmb_press) > DRAG_MIN:
				rmb_dragged = true
				cam.pan_screen(ev.relative)
			return
		if drag_start.x >= 0 and not dragging and mouse_pos.distance_to(drag_start) > DRAG_MIN and mode == "":
			dragging = true
		if mode == "guard" and guard_press.x >= 0:
			var g := cam.ground_at(mouse_pos)
			if g.x >= 0:
				guard_radius = clampf(guard_centre.distance_to(g), 12.0, 90.0)
				if guard_centre.distance_to(g) > 3.0:
					_set_guard_ring_radius(guard_radius)
		if mode == "place" and place_press.x >= 0 and mouse_pos.distance_to(place_press) > DRAG_MIN:
			place_rotating = true
			var a := cam.ground_at(place_press)
			var b := cam.ground_at(mouse_pos)
			if a.x >= 0 and b.x >= 0 and a.distance_to(b) > 0.5:
				place_yaw = atan2(b.x - a.x, b.y - a.y)
		_update_hover()
		_update_ghost()
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		mouse_pos = mb.position
		if view.hud.is_mouse_over_ui(mb.position) and not dragging:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mode == "place":
					place_press = mb.position
					get_viewport().set_input_as_handled()
					return
				if mode == "guard":
					var g := cam.ground_at(mb.position)
					if g.x >= 0:
						guard_press = mb.position
						guard_centre = g
					get_viewport().set_input_as_handled()
					return
				if mode != "":
					_mode_click(mb.position)
					get_viewport().set_input_as_handled()
					return
				if view.pstate.get("beam", false):
					# each click gives the beam a new spot to crawl to (it is slow, like a unit on a leash)
					var g := cam.ground_at(mb.position)
					if g.x >= 0:
						view.send({"t": "sw_steer", "x": g.x, "y": g.y})
						view.fx.floating_text(Vector3(g.x, 0, g.y), "▼", Color(0.6, 0.9, 1.0))
					get_viewport().set_input_as_handled()
					return
				drag_start = mb.position
			else:
				if mode == "place" and place_press.x >= 0:
					var anchor := place_press
					place_press = Vector2(-1, -1)
					place_rotating = false
					_mode_click(anchor)
					get_viewport().set_input_as_handled()
					return
				if mode == "guard" and guard_press.x >= 0:
					var anchor := guard_press
					guard_press = Vector2(-1, -1)
					_mode_click(anchor)
					get_viewport().set_input_as_handled()
					return
				if dragging:
					_select_box(drag_rect(), mb.shift_pressed)
				elif drag_start.x >= 0:
					_click_select(mb.position, mb.shift_pressed, mb.ctrl_pressed)
				drag_start = Vector2(-1, -1)
				dragging = false
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				rmb_press = mb.position
				rmb_dragged = false
			else:
				var was_drag := rmb_dragged
				rmb_press = Vector2(-1, -1)
				rmb_dragged = false
				if not was_drag:
					if mode != "":
						cancel_mode()
					elif view.pstate.get("beam", false):
						view.send({"t": "sw_stop"})   # leave the beam where it is
					elif mb.ctrl_pressed:
						_force_attack(mb.position)
					else:
						_context_command(mb.position, mb.shift_pressed)
			get_viewport().set_input_as_handled()
		return
	if ev is InputEventKey and ev.pressed:
		var k := ev as InputEventKey
		if view.hud.chat_open():
			return
		if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			view.hud.open_chat(false)
			get_viewport().set_input_as_handled()
			return
		if k.keycode == KEY_BACKSPACE:
			view.hud.open_chat(true)
			get_viewport().set_input_as_handled()
			return
		if k.keycode == KEY_B and k.ctrl_pressed:
			beacon_mode()
			get_viewport().set_input_as_handled()
			return
		if k.keycode == KEY_ESCAPE or k.keycode == KEY_F10:
			if mode != "":
				cancel_mode()
			elif view.hud.promo_panel.visible:
				view.hud.close_promo()
			else:
				view.hud.toggle_pause_menu()
			get_viewport().set_input_as_handled()
			return
		if k.echo:
			return
		match k.keycode:
			KEY_S:
				stop()
			KEY_G:
				if mode == "guard":
					guard()
				elif not _own_units_selected().is_empty():
					guard_mode()
			KEY_A:
				if not _own_units_selected().is_empty():
					amove_mode()
			KEY_X:
				# Generals: X scatters the selection (Ctrl+X keeps the old force-fire binding)
				if k.ctrl_pressed:
					if not _own_units_selected().is_empty():
						force_mode()
				else:
					scatter()
			KEY_Q:
				# combat units on screen; tap twice for the whole map
				_select_combat(false, _double_tap(KEY_Q))
			KEY_W:
				_select_combat(true, _double_tap(KEY_W))
			KEY_E:
				_select_same_type(_double_tap(KEY_E))
			KEY_UP, KEY_DOWN:
				if k.ctrl_pressed:
					_select_next("builder", true)
			KEY_U:
				unload()
			KEY_H:
				_jump_home()
			KEY_N:
				_select_next("builder", true)
			KEY_B:
				_select_next("barracks", false)
			KEY_F:
				_select_next("factory", false)
			KEY_I:
				_select_next("airfield", false)
			KEY_C:
				_select_next("cc", false)
			KEY_Y:
				_select_next("supply", false)
			KEY_SPACE:
				if not view.alerts.is_empty():
					cam.jump_to(view.alerts[view.alerts.size() - 1]["p"])
			KEY_F1:
				view.send({"t": "cheat_cash"})
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var n := k.keycode - KEY_0
				if k.ctrl_pressed:
					groups[n] = _own_units_selected()
					view.on_msg("Group %d assigned" % n)
				elif groups.has(n):
					var ids := []
					for id in groups[n]:
						if view.puppets.has(id):
							ids.append(id)
					groups[n] = ids
					set_selection(ids)
					if k.is_command_or_control_pressed() == false and Time.get_ticks_msec() / 1000.0 - last_click_t < 0.35 and last_click_id == -n:
						if not ids.is_empty():
							cam.jump_to(Vector2(view.puppets[ids[0]].cur_pos.x, view.puppets[ids[0]].cur_pos.z))
					last_click_t = Time.get_ticks_msec() / 1000.0
					last_click_id = -n

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		rmb_press = Vector2(-1, -1)
		rmb_dragged = false
		if not dragging:
			drag_start = Vector2(-1, -1)

var drag_hover: Array = []   # puppets lit up because the drag box currently covers them

func _process(dt: float) -> void:
	if mode == "":
		_refresh_sig_if_needed()
	_update_drag_hover()

## While dragging a box, everything it would select lights up so you can see what you'll get.
func _update_drag_hover() -> void:
	var r := drag_rect()
	var inside := []
	if r.size != Vector2.ZERO:
		for pu in view.puppets.values():
			var p: Puppet = pu
			if p.team != view.my_index or p.is_building or p.ghost or cam.is_behind(p.cur_pos):
				continue
			if r.has_point(cam.to_screen(p.cur_pos + Vector3(0, 0.8, 0))):
				inside.append(p)
	for p in drag_hover:
		if is_instance_valid(p) and not inside.has(p) and p.id != hover_id:
			p.hovered = false
	for p in inside:
		p.hovered = true
	drag_hover = inside

func _refresh_sig_if_needed() -> void:
	var cash := str(view.pstate.get("cash", 0))
	if not sig.ends_with("|" + mode + "|" + cash + "|" + str(view.pstate.get("beam", false))):
		_refresh_sig()

func _update_hover() -> void:
	var p := _puppet_at(mouse_pos)
	var nid := p.id if p != null else -1
	if nid != hover_id:
		if view.puppets.has(hover_id):
			view.puppets[hover_id].hovered = false
		hover_id = nid
		if p != null:
			p.hovered = true
		_update_cursor()

func _click_select(pos: Vector2, shift: bool, _ctrl: bool) -> void:
	var p := _puppet_at(pos)
	var now := Time.get_ticks_msec() / 1000.0
	if p == null:
		if not shift:
			set_selection([])
		return
	if now - last_click_t < 0.35 and last_click_id == p.id and p.team == view.my_index and not p.is_building:
		_select_same_type_on_screen(p.type)
	elif shift and p.team == view.my_index and not p.is_building:
		var ids := selected.duplicate()
		if ids.has(p.id):
			ids.erase(p.id)
		else:
			ids.append(p.id)
		set_selection(ids)
	else:
		set_selection([p.id])
	last_click_t = now
	last_click_id = p.id

func _context_command(pos: Vector2, queue: bool) -> void:
	var ids := _own_units_selected()
	var g := cam.ground_at(pos)
	var target := _puppet_at(pos)
	if ids.is_empty():
		# building selected: right-click sets the rally point
		var sel := selected_puppets()
		if sel.size() == 1 and sel[0].is_building and sel[0].team == view.my_index and sel[0].def.has("produces") and g.x >= 0:
			view.send({"t": "rally", "id": sel[0].id, "x": g.x, "y": g.y})
		return
	if target != null:
		if target.team >= 0 and not view.is_ally(target.team):
			if target.cat == "air" and target.cur_pos.y > 0.5:
				var aa := _filter_ids(ids, func(p: Puppet) -> bool:
					for w in p.def.get("weapons", []):
						if Data.WEAPONS[w]["aa"]:
							return true
					return false)
				if aa.is_empty():
					view.on_msg("Selected units cannot attack aircraft")
					Audio.I.ui("ui_error", -6.0)
					return
			view.send({"t": "attack", "ids": ids, "tid": target.id, "q": queue})
			view.fx.floating_text(target.cur_pos, "✕", Color(1, 0.3, 0.3))
			_voice_for(ids, "attack")
			return
		if target.type == "supply_dock":
			var chinooks := _filter_ids(ids, func(p: Puppet) -> bool: return p.def.get("gatherer", 0) > 0)
			var others := _filter_ids(ids, func(p: Puppet) -> bool: return p.def.get("gatherer", 0) <= 0)
			if not chinooks.is_empty():
				view.send({"t": "gather", "ids": chinooks, "tid": target.id, "q": queue})
				_voice_for(chinooks, "gather")
			if not others.is_empty():
				view.send({"t": "move", "ids": others, "x": g.x, "y": g.y, "q": queue})
			return
		if (target.team == view.my_index or target.def.get("garrison", false)) and target.def.has("cargo") and not selected.has(target.id) and (not target.is_building or target.complete):
			# load infantry (and vehicles into a Chinook)
			var riders := _filter_ids(ids, func(p: Puppet) -> bool:
				return p.id != target.id and not p.is_building and p.cat != "air" and (p.cat == "inf" or target.def.get("cargo_veh", false)))
			if not riders.is_empty():
				view.send({"t": "load", "ids": riders, "tid": target.id})
				view.fx.floating_text(target.cur_pos, "LOAD", Color(0.5, 0.9, 1.0))
				_voice_for(riders, "move")
				return
		if target.team >= 0 and view.is_ally(target.team) and target.is_building:
			var builders := _filter_ids(ids, func(p: Puppet) -> bool: return p.def.get("builder", false))
			var others := _filter_ids(ids, func(p: Puppet) -> bool: return not p.def.get("builder", false))
			if not builders.is_empty():
				view.send({"t": "repair", "ids": builders, "tid": target.id, "q": queue})
				_voice_for(builders, "repair")
			if not others.is_empty():
				view.send({"t": "move", "ids": others, "x": g.x, "y": g.y, "q": queue})
				if target.def.has("heal") and Data.role_of(target.type) == "factory":
					view.fx.floating_text(target.cur_pos, "REPAIR", Color(0.5, 1.0, 0.5))
			return
		if target.is_building and (target.team < 0 and target.def.get("capturable", false)):
			var rangers := _filter_ids(ids, func(p: Puppet) -> bool: return p.def.get("capture", false) and (p.def.get("capture_free", false) or view.has_upgrade("capture")))
			if not rangers.is_empty():
				view.send({"t": "capture", "ids": rangers, "tid": target.id, "q": queue})
				_voice_for(rangers, "capture")
				return
	if g.x >= 0:
		view.send({"t": "move", "ids": ids, "x": g.x, "y": g.y, "q": queue})
		view.fx.floating_text(Vector3(g.x, 0, g.y), "▼", Color(0.4, 1.0, 0.5))
		_voice_for(ids, "move")

func _voice_for(ids: Array, kind: String) -> void:
	if ids.is_empty():
		return
	var p: Puppet = view.puppets.get(ids[rng_pick(ids.size())])
	if p != null:
		Audio.I.voice(p.type, kind)
		if kind == "move" or kind == "attack":
			# engines rev on the order
			var n := 0
			for id in ids:
				var q: Puppet = view.puppets.get(id)
				if q != null and q.cat == "veh":
					Audio.I.engine_ack(q.type, q.cur_pos)
					n += 1
					if n >= 2:
						break

func rng_pick(n: int) -> int:
	return randi() % maxi(n, 1)

func _filter_ids(ids: Array, pred: Callable) -> Array:
	var out := []
	for id in ids:
		var p = view.puppets.get(id)
		if p != null and pred.call(p):
			out.append(id)
	return out

func minimap_command(world: Vector2) -> void:
	var ids := _own_units_selected()
	if ids.is_empty():
		return
	view.send({"t": "move", "ids": ids, "x": world.x, "y": world.y, "q": false})
	_voice_for(ids, "move")

## Left click on the minimap while in attack-move mode (or a double click): attack-move there.
func minimap_attack_move(world: Vector2) -> void:
	var ids := _own_units_selected()
	if ids.is_empty():
		return
	view.send({"t": "amove", "ids": ids, "x": world.x, "y": world.y, "q": false})
	view.fx.floating_text(Vector3(world.x, 0, world.y), "▼", Color(1.0, 0.5, 0.3))
	_voice_for(ids, "attack")
	if mode == "amove":
		cancel_mode()

var last_tap_key := -1
var last_tap_t := -10.0
func _double_tap(key: int) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var dbl := key == last_tap_key and now - last_tap_t < 0.4
	last_tap_key = key
	last_tap_t = now
	return dbl

func _on_screen(p: Puppet) -> bool:
	if cam.is_behind(p.cur_pos):
		return false
	var vs := get_viewport().get_visible_rect().size
	var sp := cam.to_screen(p.cur_pos)
	return sp.x >= 0 and sp.y >= 0 and sp.x <= vs.x and sp.y <= vs.y - Hud.BAR_H

## Q / W: every combat unit (or every combat aircraft) on screen, or on the whole map.
func _select_combat(air_only: bool, whole_map: bool) -> void:
	var ids := []
	for pu in view.puppets.values():
		var p: Puppet = pu
		if p.team != view.my_index or p.is_building or p.ghost:
			continue
		if not p.def.has("weapons") or p.def["weapons"].is_empty() or p.def.get("builder", false) or int(p.def.get("gatherer", 0)) > 0:
			continue
		if air_only and p.cat != "air":
			continue
		if not whole_map and not _on_screen(p):
			continue
		ids.append(p.id)
	if not ids.is_empty():
		set_selection(ids)
		view.on_msg("%d %s selected%s" % [ids.size(), "aircraft" if air_only else "combat units", "" if not whole_map else " (whole map)"])

## E: everything of the same type as the selection, on screen or on the whole map.
func _select_same_type(whole_map: bool) -> void:
	var types := {}
	for p in selected_puppets():
		if p.team == view.my_index and not p.is_building:
			types[p.type] = true
	if types.is_empty():
		return
	var ids := []
	for pu in view.puppets.values():
		var p: Puppet = pu
		if p.team != view.my_index or p.is_building or p.ghost or not types.has(p.type):
			continue
		if not whole_map and not _on_screen(p):
			continue
		ids.append(p.id)
	if not ids.is_empty():
		set_selection(ids)

## X: scatter - everyone picks a random spot a few metres away.
func scatter() -> void:
	var ids := _own_units_selected()
	if ids.is_empty():
		return
	# everyone runs outward from the middle of the group (plus a random twist so lines don't form)
	var c := Vector3.ZERO
	var n := 0
	for id in ids:
		var p: Puppet = view.puppets.get(id)
		if p != null and p.cat != "air":
			c += p.cur_pos
			n += 1
	if n == 0:
		return
	c /= float(n)
	for id in ids:
		var p: Puppet = view.puppets.get(id)
		if p == null or p.cat == "air":
			continue
		var out := Vector2(p.cur_pos.x - c.x, p.cur_pos.z - c.z)
		var ang := (out.angle() if out.length() > 0.5 else randf() * TAU) + randf_range(-0.7, 0.7)
		var d := randf_range(8.0, 14.0)
		var goal := Vector2(p.cur_pos.x + cos(ang) * d, p.cur_pos.z + sin(ang) * d)
		var ms := float(view.map["size"])
		goal.x = clampf(goal.x, 2.0, ms - 2.0)
		goal.y = clampf(goal.y, 2.0, ms - 2.0)
		view.send({"t": "move", "ids": [id], "x": goal.x, "y": goal.y, "q": false})
	view.fx.floating_text(c, "SCATTER", Color(1.0, 0.85, 0.4))
	_voice_for(ids, "move")

func _jump_home() -> void:
	for pu in view.puppets.values():
		if pu.team == view.my_index and Data.role_of(pu.type) == "cc":
			cam.jump_to(Vector2(pu.cur_pos.x, pu.cur_pos.z))
			return

## Cycle through own entities of a role ("builder" for dozers / workers, or a structure role), select and centre.
func _select_next(role: String, idle_first: bool) -> void:
	var list := []
	for pu in view.puppets.values():
		if pu.team != view.my_index or pu.ghost:
			continue
		if role == "builder":
			if pu.def.get("builder", false) and not pu.is_building:
				list.append(pu)
		elif pu.is_building and Data.role_of(pu.type) == role:
			list.append(pu)
	if list.is_empty():
		view.on_msg("No %s" % ({"builder": "builder", "barracks": "Barracks", "factory": "vehicle factory", "airfield": "Airfield", "cc": "Command Center", "supply": "supply center"}.get(role, role)))
		return
	list.sort_custom(func(a: Puppet, b: Puppet) -> bool: return a.id < b.id)
	var pick: Puppet = null
	if list.size() == 1 or not selected.has(list[0].id) and not _any_selected(list):
		pick = list[0]
	else:
		for i in range(list.size()):
			if selected.has(list[i].id):
				pick = list[(i + 1) % list.size()]
				break
	if pick == null:
		pick = list[0]
	set_selection([pick.id])
	cam.jump_to(Vector2(pick.cur_pos.x, pick.cur_pos.z))

func _any_selected(list: Array) -> bool:
	for p in list:
		if selected.has(p.id):
			return true
	return false

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
func cancel_mode() -> void:
	mode = ""
	mode_arg = null
	place_press = Vector2(-1, -1)
	place_rotating = false
	guard_press = Vector2(-1, -1)
	_clear_ghost()
	if guard_ring != null:
		guard_ring.queue_free()
		guard_ring = null
	_refresh_sig()

func _mode_click(pos: Vector2) -> void:
	var g := cam.ground_at(pos)
	if g.x < 0:
		return
	match mode:
		"place":
			var fp: Vector2i = Data.BUILDINGS[place_type]["fp"]
			var snapped := PathGrid.snap_center(g, fp, place_yaw)
			if not view.placement_ok(place_type, snapped, place_yaw):
				Audio.I.ui("ui_error", -6.0)
				view.on_msg("Cannot build there")
				return   # stay in placement mode
			var dozer := _first_builder()
			if dozer >= 0:
				view.send({"t": "build", "id": dozer, "type": place_type, "x": snapped.x, "y": snapped.y, "yaw": place_yaw})
				var dp: Puppet = view.puppets.get(dozer)
				Audio.I.voice(dp.type if dp != null else "dozer", "build")
			cancel_mode()
		"amove":
			view.send({"t": "amove", "ids": _own_units_selected(), "x": g.x, "y": g.y, "q": Input.is_key_pressed(KEY_SHIFT)})
			view.fx.floating_text(Vector3(g.x, 0, g.y), "▼", Color(1.0, 0.5, 0.3))
			_voice_for(_own_units_selected(), "attack")
			cancel_mode()
		"guard":
			view.send({"t": "guard", "ids": _own_units_selected(), "x": g.x, "y": g.y, "r": guard_radius})
			_voice_for(_own_units_selected(), "move")
			cancel_mode()
		"beacon":
			view.send({"t": "beacon", "x": g.x, "y": g.y})
			cancel_mode()
		"force":
			_force_attack(pos)
			cancel_mode()
		"capture":
			var target := _puppet_at(pos)
			if target != null and target.is_building and target.team != view.my_index:
				var rangers := _filter_ids(_own_units_selected(), func(p: Puppet) -> bool: return p.def.get("capture", false))
				view.send({"t": "capture", "ids": rangers, "tid": target.id, "q": false})
				view.fx.floating_text(target.cur_pos, "CAPTURE", Color(1.0, 0.5, 0.9))
				_voice_for(rangers, "capture")
			cancel_mode()
		"rally":
			view.send({"t": "rally", "id": mode_arg, "x": g.x, "y": g.y})
			cancel_mode()
		"power":
			view.send({"t": "power", "pid": mode_arg, "x": g.x, "y": g.y})
			cancel_mode()
		"sw":
			view.send({"t": "sw", "id": mode_arg, "x": g.x, "y": g.y})
			cancel_mode()

func _force_attack(pos: Vector2) -> void:
	var ids := _own_units_selected()
	if ids.is_empty():
		return
	var target := _puppet_at(pos)
	if target != null and not (target.team == view.my_index and _all_selected(target)):
		if target.team >= 0 and view.is_ally(target.team):
			view.on_msg("Force-firing on an ally!")
		view.send({"t": "attack", "ids": ids, "tid": target.id, "force": true, "q": Input.is_key_pressed(KEY_SHIFT)})
		view.fx.floating_text(target.cur_pos, "✕", Color(1, 0.3, 0.3))
		return
	var g := cam.ground_at(pos)
	if g.x >= 0:
		view.send({"t": "attack_ground", "ids": ids, "x": g.x, "y": g.y, "q": Input.is_key_pressed(KEY_SHIFT)})
		view.fx.floating_text(Vector3(g.x, 0, g.y), "✕", Color(1, 0.3, 0.3))

func _all_selected(p: Puppet) -> bool:
	return selected.has(p.id)

func _first_builder() -> int:
	for p in selected_puppets():
		if p.team == view.my_index and p.def.get("builder", false):
			return p.id
	return -1

func begin_place(type: String) -> void:
	if _first_builder() < 0:
		return
	mode = "place"
	place_type = type
	place_yaw = 0.0
	place_press = Vector2(-1, -1)
	place_rotating = false
	_clear_ghost()
	ghost = Node3D.new()
	var fp: Vector2 = Data.footprint_size(type)
	ghost_mesh = Visuals.box(Vector3(fp.x, 0.3, fp.y), Color(0.3, 1.0, 0.4, 0.4), true)
	ghost_mesh.position.y = 0.15
	ghost.add_child(ghost_mesh)
	var model := Visuals.make_model(type, view.my_index)
	model.name = "GhostModel"
	ghost.add_child(model)
	_set_ghost_alpha(model, 0.45)
	# facing arrow: the building's front (door / exit side) is local +Z
	var arrow := Node3D.new()
	arrow.name = "Arrow"
	var stem := Visuals.box(Vector3(0.8, 0.12, 3.0), Color(1.0, 0.9, 0.2, 0.9), true)
	stem.position = Vector3(0, 0.4, fp.y * 0.5 + 1.8)
	arrow.add_child(stem)
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.6
	cone.height = 2.2
	cone.radial_segments = 3
	head.mesh = cone
	head.material_override = Visuals.flat_mat(Color(1.0, 0.9, 0.2, 0.9))
	head.rotation_degrees = Vector3(90, 0, 0)
	head.position = Vector3(0, 0.4, fp.y * 0.5 + 4.4)
	arrow.add_child(head)
	ghost.add_child(arrow)
	view.add_child(ghost)
	_update_ghost()
	_refresh_sig()

func _set_ghost_alpha(n: Node, a: float, ok := true) -> void:
	var col := Color(0.35, 0.75, 0.45, a) if ok else Color(0.8, 0.3, 0.25, a)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		(mi as MeshInstance3D).material_override = m
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _clear_ghost() -> void:
	if ghost != null:
		ghost.queue_free()
		ghost = null
		ghost_mesh = null

func _update_ghost() -> void:
	if guard_ring != null and guard_press.x < 0:
		var gg := cam.ground_at(mouse_pos)
		if gg.x >= 0:
			guard_ring.position = Vector3(gg.x, 0.2, gg.y)
	if ghost == null:
		return
	var g := cam.ground_at(place_press if place_rotating else mouse_pos)
	if g.x < 0:
		return
	var fp: Vector2i = Data.BUILDINGS[place_type]["fp"]
	var snapped := PathGrid.snap_center(g, fp, place_yaw)
	ghost.position = Vector3(snapped.x, 0, snapped.y)
	ghost.rotation.y = place_yaw
	var ok: bool = view.placement_ok(place_type, snapped, place_yaw)
	ghost_mesh.material_override = Visuals.flat_mat(Color(0.1, 0.6, 0.2, 0.55) if ok else Color(0.7, 0.1, 0.05, 0.6))
	_set_ghost_alpha(ghost.get_node("GhostModel"), 0.55, ok)

func amove_mode() -> void:
	mode = "amove"
	_refresh_sig()

func guard_mode() -> void:
	if _own_units_selected().is_empty():
		return
	mode = "guard"
	guard_radius = World.GUARD_RADIUS
	guard_press = Vector2(-1, -1)
	if guard_ring != null:
		guard_ring.queue_free()
	guard_ring = Visuals.ring(1.0, Color(0.4, 0.9, 1.0, 0.7), 0.5)
	guard_ring.material_override = Visuals.flat_mat(Color(0.4, 0.9, 1.0, 0.6))
	view.add_child(guard_ring)
	_set_guard_ring_radius(guard_radius)
	_update_ghost()
	_refresh_sig()

func _set_guard_ring_radius(r: float) -> void:
	if guard_ring != null:
		guard_ring.scale = Vector3(r, 1.0, r)
		guard_ring.position = Vector3(guard_centre.x, 0.2, guard_centre.y) if guard_press.x >= 0 else guard_ring.position

func beacon_mode() -> void:
	mode = "beacon"
	_refresh_sig()

func select_next_dozer() -> void:
	_select_next("builder", true)

func unload_building(bid: int) -> void:
	view.send({"t": "unload", "ids": [bid]})

## Let one passenger out of a transport / tunnel / garrison (the cargo icons in the info panel).
func unload_one(cid: int, uid: int) -> void:
	view.send({"t": "unload", "ids": [cid], "uid": uid})

func buy_drone(vid: int, kind: String) -> void:
	view.send({"t": "drone", "id": vid, "kind": kind})

func intel(bid: int) -> void:
	view.send({"t": "intel", "id": bid})

func set_plan(bid: int, plan: String) -> void:
	view.send({"t": "plan", "id": bid, "plan": plan})
	Audio.I.ui("ui_click", -6.0)

func force_mode() -> void:
	mode = "force"
	_refresh_sig()

func capture_mode() -> void:
	mode = "capture"
	_refresh_sig()

func rally_mode(bid: int) -> void:
	mode = "rally"
	mode_arg = bid
	_refresh_sig()

func power_mode(pid: String) -> void:
	mode = "power"
	mode_arg = pid
	_refresh_sig()

func sw_mode(bid: int) -> void:
	mode = "sw"
	mode_arg = bid
	_refresh_sig()

# ---------------------------------------------------------------------------
# Commands from HUD / keys
# ---------------------------------------------------------------------------
func stop() -> void:
	var ids := _own_units_selected()
	if not ids.is_empty():
		view.send({"t": "stop", "ids": ids})
	cancel_mode()

func guard() -> void:
	var ids := _own_units_selected()
	if not ids.is_empty():
		view.send({"t": "guard", "ids": ids})
		_voice_for(ids, "move")
		for id in ids:
			var p: Puppet = view.puppets.get(id)
			if p != null:
				view.fx.floating_text(p.cur_pos, "GUARD", Color(0.4, 0.9, 1.0))

func unload() -> void:
	var ids := []
	for p in selected_puppets():
		if (p.team == view.my_index or p.def.get("garrison", false)) and p.def.has("cargo"):
			ids.append(p.id)
	if not ids.is_empty():
		view.send({"t": "unload", "ids": ids})
		Audio.I.ui("ui_click", -6.0)

func produce(bid: int, type: String) -> void:
	view.send({"t": "produce", "id": bid, "type": type})
	Audio.I.ui("ui_click", -6.0)

func cancel(bid: int, i: int) -> void:
	view.send({"t": "cancel", "id": bid, "i": i})

func upgrade(bid: int, uid: String) -> void:
	view.send({"t": "upgrade", "id": bid, "uid": uid})

func cancel_upgrade(bid: int) -> void:
	view.send({"t": "cancel_upgrade", "id": bid})

func sell(bid: int) -> void:
	view.send({"t": "sell", "id": bid})

func buy_power(pid: String) -> void:
	view.send({"t": "buy_power", "pid": pid})
