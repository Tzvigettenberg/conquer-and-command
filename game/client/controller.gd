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

func _refresh_sig() -> void:
	var parts := []
	for id in selected:
		var p = view.puppets.get(id)
		if p != null:
			parts.append("%d:%s:%d" % [id, str(p.complete), p.level])
	sig = ",".join(parts) + "|" + mode + "|" + str(view.pstate.get("cash", 0))

func hint_text() -> String:
	match mode:
		"place":
			return "Place %s  ·  Left-click to build, right-click / Esc to cancel" % Data.BUILDINGS[place_type]["name"]
		"amove":
			return "Attack-move: click a destination"
		"rally":
			return "Click to set the rally point"
		"power":
			return "%s: click a target" % Data.POWERS[mode_arg]["name"]
		"sw":
			return "PARTICLE CANNON: click a target, then steer with the mouse"
	if view.pstate.get("beam", false):
		return "Steering the particle beam - move the mouse"
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

func _puppet_at(screen: Vector2) -> Puppet:
	var best: Puppet = null
	var best_d := PICK_RADIUS
	for pu in view.puppets.values():
		var p: Puppet = pu
		if p.ghost and not p.is_building:
			continue
		var centre := p.cur_pos + Vector3(0, 0.8 if not p.is_building else 2.0, 0)
		if cam.is_behind(centre):
			continue
		var sp := cam.to_screen(centre)
		var r := PICK_RADIUS
		if p.is_building:
			var fp: Vector2 = Data.footprint_size(p.type)
			# buildings: test against the projected footprint rectangle
			var half := Vector3(fp.x * 0.5, 0, fp.y * 0.5)
			var pts := []
			for c in [Vector3(-half.x, 0, -half.z), Vector3(half.x, 0, -half.z), Vector3(half.x, 0, half.z), Vector3(-half.x, 0, half.z),
					Vector3(-half.x, float(p.def.get("height", 5.0)) * 0.6, -half.z), Vector3(half.x, float(p.def.get("height", 5.0)) * 0.6, half.z)]:
				pts.append(cam.to_screen(p.cur_pos + c))
			var minx := 1e9
			var miny := 1e9
			var maxx := -1e9
			var maxy := -1e9
			for q in pts:
				minx = minf(minx, q.x)
				miny = minf(miny, q.y)
				maxx = maxf(maxx, q.x)
				maxy = maxf(maxy, q.y)
			if Rect2(minx, miny, maxx - minx, maxy - miny).has_point(screen):
				var d := sp.distance_to(screen) + 30.0   # units on top of buildings win
				if d < best_d + 40.0 and (best == null or not (not best.is_building)):
					best = p
					best_d = d
			continue
		var d := sp.distance_to(screen)
		if p.team != view.my_index:
			d += 4.0
		if d < best_d:
			best_d = d
			best = p
	return best

func _select_box(r: Rect2, additive: bool) -> void:
	var ids := []
	if additive:
		ids = selected.duplicate()
	for pu in view.puppets.values():
		var p: Puppet = pu
		if p.team != view.my_index or p.is_building or p.ghost:
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
	if ev is InputEventMouseMotion:
		mouse_pos = ev.position
		if drag_start.x >= 0 and not dragging and mouse_pos.distance_to(drag_start) > DRAG_MIN and mode == "":
			dragging = true
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
				if mode != "":
					_mode_click(mb.position)
					get_viewport().set_input_as_handled()
					return
				drag_start = mb.position
			else:
				if dragging:
					_select_box(drag_rect(), mb.shift_pressed)
				elif drag_start.x >= 0:
					_click_select(mb.position, mb.shift_pressed, mb.ctrl_pressed)
				drag_start = Vector2(-1, -1)
				dragging = false
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if mode != "":
				cancel_mode()
			else:
				_context_command(mb.position, mb.shift_pressed)
			get_viewport().set_input_as_handled()
		return
	if ev is InputEventKey and ev.pressed:
		var k := ev as InputEventKey
		if k.keycode == KEY_ESCAPE:
			if mode != "":
				cancel_mode()
			else:
				set_selection([])
			get_viewport().set_input_as_handled()
			return
		if k.echo:
			return
		match k.keycode:
			KEY_S:
				stop()
			KEY_G:
				guard()
			KEY_A:
				if not _own_units_selected().is_empty():
					amove_mode()
			KEY_H:
				_jump_home()
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

func _process(dt: float) -> void:
	if view.pstate.get("beam", false):
		steer_t -= dt
		if steer_t <= 0.0:
			steer_t = 0.2
			var g := cam.ground_at(mouse_pos)
			if g.x >= 0:
				view.send({"t": "sw_steer", "x": g.x, "y": g.y})
	if mode == "":
		_refresh_sig_if_needed()

func _refresh_sig_if_needed() -> void:
	var cash := str(view.pstate.get("cash", 0))
	if not sig.ends_with("|" + mode + "|" + cash):
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
		if target.team != view.my_index and target.team >= 0:
			view.send({"t": "attack", "ids": ids, "tid": target.id, "q": queue})
			view.fx.floating_text(target.cur_pos, "✕", Color(1, 0.3, 0.3))
			return
		if target.type == "supply_dock":
			var chinooks := _filter_ids(ids, func(p: Puppet) -> bool: return p.def.get("gatherer", 0) > 0)
			var others := _filter_ids(ids, func(p: Puppet) -> bool: return p.def.get("gatherer", 0) <= 0)
			if not chinooks.is_empty():
				view.send({"t": "gather", "ids": chinooks, "tid": target.id, "q": queue})
			if not others.is_empty():
				view.send({"t": "move", "ids": others, "x": g.x, "y": g.y, "q": queue})
			return
		if target.team == view.my_index and target.is_building:
			var builders := _filter_ids(ids, func(p: Puppet) -> bool: return p.def.get("builder", false))
			var others := _filter_ids(ids, func(p: Puppet) -> bool: return not p.def.get("builder", false))
			if not builders.is_empty():
				view.send({"t": "repair", "ids": builders, "tid": target.id, "q": queue})
			if not others.is_empty():
				view.send({"t": "move", "ids": others, "x": g.x, "y": g.y, "q": queue})
			return
		if target.is_building and (target.team < 0 and target.def.get("capturable", false)):
			var rangers := _filter_ids(ids, func(p: Puppet) -> bool: return p.type == "ranger")
			if not rangers.is_empty() and view.has_upgrade("capture"):
				view.send({"t": "capture", "ids": rangers, "tid": target.id, "q": queue})
				return
	if g.x >= 0:
		view.send({"t": "move", "ids": ids, "x": g.x, "y": g.y, "q": queue})
		view.fx.floating_text(Vector3(g.x, 0, g.y), "▼", Color(0.4, 1.0, 0.5))

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

func _jump_home() -> void:
	for pu in view.puppets.values():
		if pu.team == view.my_index and pu.type == "command_center":
			cam.jump_to(Vector2(pu.cur_pos.x, pu.cur_pos.z))
			return

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
func cancel_mode() -> void:
	mode = ""
	mode_arg = null
	_clear_ghost()
	_refresh_sig()

func _mode_click(pos: Vector2) -> void:
	var g := cam.ground_at(pos)
	if g.x < 0:
		return
	match mode:
		"place":
			var snapped := PathGrid.snap_center(g, Data.BUILDINGS[place_type]["fp"])
			var dozer := _first_builder()
			if dozer >= 0:
				view.send({"t": "build", "id": dozer, "type": place_type, "x": snapped.x, "y": snapped.y})
			cancel_mode()
		"amove":
			view.send({"t": "amove", "ids": _own_units_selected(), "x": g.x, "y": g.y, "q": Input.is_key_pressed(KEY_SHIFT)})
			view.fx.floating_text(Vector3(g.x, 0, g.y), "▼", Color(1.0, 0.5, 0.3))
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
	view.add_child(ghost)
	_update_ghost()
	_refresh_sig()

func _set_ghost_alpha(n: Node, a: float) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.6, 0.9, 1.0, a)
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
	if ghost == null:
		return
	var g := cam.ground_at(mouse_pos)
	if g.x < 0:
		return
	var fp: Vector2i = Data.BUILDINGS[place_type]["fp"]
	var snapped := PathGrid.snap_center(g, fp)
	ghost.position = Vector3(snapped.x, 0, snapped.y)
	var ok: bool = view.placement_ok(place_type, snapped)
	ghost_mesh.material_override = Visuals.flat_mat(Color(0.3, 1.0, 0.4, 0.4) if ok else Color(1.0, 0.25, 0.2, 0.5))

func amove_mode() -> void:
	mode = "amove"
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

func produce(bid: int, type: String) -> void:
	view.send({"t": "produce", "id": bid, "type": type})

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
