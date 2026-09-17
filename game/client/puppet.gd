class_name Puppet
extends Node3D
## Client-side replica of one sim entity. Interpolates between snapshots and
## drives the visual: model, turret, spinning rotors / wheels, banking, tyre
## tracks, infantry animation, selection ring, construction, power state.

const INTERP_DELAY := 0.12

var id := 0
var type := ""
var def: Dictionary = {}
var team := -1
var is_building := false
var cat := ""
var radius := 1.0

var t0 := 0.0
var t1 := 0.0
var p0 := Vector3.ZERO
var p1 := Vector3.ZERO
var yaw0 := 0.0
var yaw1 := 0.0
var tyaw0 := 0.0
var tyaw1 := 0.0
var cur_pos := Vector3.ZERO
var cur_yaw := 0.0
var prev_pos := Vector3.ZERO
var prev_yaw := 0.0
var vel := Vector3.ZERO
var yaw_rate := 0.0
var hp_frac := 1.0
var flags := 0
var aux := 0
var level := 0
var complete := true
var last_update := 0.0
var selected := false
var hovered := false
var boxes := 0
var ghost := false
var aabb := AABB()

var model: Node3D
var turret: Node3D = null
var rotors: Array[Node3D] = []
var wheels: Array[Node3D] = []
var tilt: Node3D = null          # body pivot for banking / pitching
var sel_ring: MeshInstance3D
var team_ring: MeshInstance3D
var pad: MeshInstance3D = null
var anim: AnimationPlayer = null
var anim_state := ""
var stealth_alpha := 1.0
var track_dist := 0.0
var crates: Array[Node3D] = []
var blackout_mat: StandardMaterial3D = null
var blackout := false
var smoke: Node3D = null
var loop: AudioStreamPlayer3D = null
var loop_base_db := -8.0

func setup(_id: int, _type: String, _team: int, pos: Vector2, alt: float, yaw: float, extra: Dictionary, mine: bool) -> void:
	id = _id
	type = _type
	def = Data.def(_type)
	team = _team
	is_building = Data.is_building(_type)
	cat = def.get("cat", "bld")
	complete = extra.get("complete", true)
	boxes = extra.get("boxes", 0)
	if is_building:
		var fp: Vector2 = Data.footprint_size(_type)
		radius = maxf(fp.x, fp.y) * 0.5
	else:
		radius = float(def.get("radius", 1.0))
	cur_pos = Vector3(pos.x, alt, pos.y)
	prev_pos = cur_pos
	p0 = cur_pos
	p1 = cur_pos
	yaw0 = yaw
	yaw1 = yaw
	cur_yaw = yaw
	prev_yaw = yaw
	position = cur_pos
	rotation.y = yaw
	_build_visual(mine)

func _build_visual(mine: bool) -> void:
	tilt = Node3D.new()
	tilt.name = "Tilt"
	add_child(tilt)
	model = Visuals.make_model(type, team)
	tilt.add_child(model)
	aabb = Visuals.model_aabb(model)
	if model.has_meta("turret"):
		turret = model.get_meta("turret")
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var nm: String = n.name
		if "Rotor" in nm or "Blade" in nm or "Propeller" in nm:
			rotors.append(n)
			n.set_meta("axis", "x" if ("Back" in nm or "Tail" in nm) else "y")
		elif "Dish" in nm or "Radar" in nm and cat != "bld":
			rotors.append(n)
			n.set_meta("axis", "slow")
		elif "Wheel" in nm and not ("Turret" in nm or "Gear" in nm or "Cover" in nm or "Steering" in nm):
			wheels.append(n)
	if is_building:
		var fp: Vector2 = Data.footprint_size(type)
		var col := Color(0.32, 0.31, 0.3)
		if def.get("neutral", false):
			col = Color(0.4, 0.38, 0.33)
		pad = Visuals.box(Vector3(fp.x, 0.12, fp.y), col)
		pad.position.y = 0.06
		add_child(pad)
		if def.get("runway", false):
			var rw := Visuals.box(Vector3(fp.x * 0.9, 0.05, 5.0), Color(0.2, 0.2, 0.2))
			rw.position = Vector3(0, 0.14, -5.0)
			add_child(rw)
			for i in range(4):
				var m := Visuals.box(Vector3(4.0, 0.02, 4.0), Color(0.5, 0.5, 0.1, 0.6), true)
				m.position = Vector3(-7.5 + i * 5.0, 0.18, -5.0)
				add_child(m)
		if team >= 0:
			var flag := Visuals.box(Vector3(0.15, 3.0, 0.15), Color(0.3, 0.3, 0.3))
			flag.position = Vector3(fp.x * 0.5 - 0.6, 1.5, fp.y * 0.5 - 0.6)
			add_child(flag)
			var banner := Visuals.box(Vector3(1.2, 0.7, 0.05), Data.TEAM_COLORS[team], true)
			banner.position = Vector3(fp.x * 0.5 - 0.0, 2.6, fp.y * 0.5 - 0.6)
			add_child(banner)
		if type == "supply_dock":
			_build_crates()
	else:
		team_ring = Visuals.disc(radius * 0.9, Color(Data.TEAM_COLORS[team], 0.55) if team >= 0 else Color(0.5, 0.5, 0.5, 0.5))
		add_child(team_ring)
	sel_ring = Visuals.ring(radius * (1.15 if not is_building else 0.75), Color(0.3, 1.0, 0.3) if mine else Color(1.0, 0.9, 0.3))
	sel_ring.visible = false
	add_child(sel_ring)
	if cat == "inf":
		_setup_anim()
	_setup_loop()
	_apply_construction()

func _setup_loop() -> void:
	var name := ""
	match type:
		"crusader", "paladin", "tomahawk", "avenger":
			name = "tank_engine"
		"dozer":
			name = "truck_engine"
		"humvee", "ambulance":
			name = "humvee_engine"
		"comanche":
			name = "helicopter_loop"
		"chinook":
			name = "chinook_loop"
		"raptor", "stealth_fighter", "aurora":
			name = "jet_loop"
	if is_building and not complete:
		name = "construction"
	if name == "":
		return
	loop = Audio.I.make_loop(name, -10.0)
	if loop != null:
		loop_base_db = -10.0
		add_child(loop)

## Supply dock: a grid of crate stacks that empties as boxes are hauled away.
func _build_crates() -> void:
	# hide the placeholder model; the crates ARE the dock
	model.visible = false
	var ps := Visuals.prefab("Props/Military/SM_Prop_Crate_Stack_01.tscn")
	var fp: Vector2 = Data.footprint_size(type)
	var cols := 4
	var rows := 4
	for r in range(rows):
		for c in range(cols):
			var n: Node3D
			if ps != null:
				n = Node3D.new()
				var inst := ps.instantiate()
				Visuals.strip_physics(inst)
				var a := Visuals.local_aabb(inst)
				var s := 1.7 / maxf(maxf(a.size.x, a.size.z), 0.01)
				inst.scale = Vector3.ONE * s
				var cen := a.get_center()
				inst.position = Vector3(-cen.x * s, -a.position.y * s, -cen.z * s)
				n.add_child(inst)
			else:
				n = Visuals.box(Vector3(1.5, 1.4, 1.5), Color(0.75, 0.6, 0.3))
				n.position.y = 0.7
				var holder := Node3D.new()
				holder.add_child(n)
				n = holder
			n.position = Vector3(-fp.x * 0.5 + 1.2 + c * (fp.x - 2.4) / (cols - 1), 0.12, -fp.y * 0.5 + 1.2 + r * (fp.y - 2.4) / (rows - 1))
			n.rotation.y = (r * 3 + c) * 0.4
			add_child(n)
			crates.append(n)
	set_crates(boxes)

func set_crates(count: int) -> void:
	boxes = count
	var full: int = int(def.get("boxes", 400))
	var visible_n := int(ceil(float(crates.size()) * clampf(float(count) / maxf(full, 1), 0.0, 1.0)))
	for i in range(crates.size()):
		crates[i].visible = i < visible_n

func _setup_anim() -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel: Skeleton3D = skels[0]
	for p in model.find_children("*", "AnimationPlayer", true, false):
		p.stop()
		p.active = false
	if not is_inside_tree():
		return
	var libs := AnimRetarget.build_libraries(skel)
	if libs.is_empty() or libs["full"].get_animation_list().is_empty():
		return
	anim = AnimationPlayer.new()
	skel.add_child(anim)
	anim.root_node = NodePath("..")
	anim.add_animation_library("f", libs["full"])
	_play("idle")

func _play(clip: String, blend := 0.15) -> void:
	if anim == null or anim_state == clip:
		return
	if not anim.has_animation("f/" + clip):
		return
	anim.play("f/" + clip, blend)
	anim_state = clip

func apply_state(pos: Vector2, alt: float, yaw: float, tyaw: float, hpf: float, fl: int, ax: int, now: float) -> void:
	p0 = p1
	yaw0 = yaw1
	tyaw0 = tyaw1
	t0 = t1
	p1 = Vector3(pos.x, alt, pos.y)
	yaw1 = yaw
	tyaw1 = tyaw
	t1 = now
	if t0 == 0.0:
		t0 = now - 0.1
		p0 = p1
		yaw0 = yaw1
		tyaw0 = tyaw1
		cur_pos = p1
		cur_yaw = yaw1
	hp_frac = hpf
	flags = fl
	aux = ax
	level = (fl >> 6) & 3
	var was_complete := complete
	complete = (fl & 8) == 0 if is_building else true
	if is_building and was_complete != complete:
		_apply_construction()
	last_update = now
	ghost = false

func _apply_construction() -> void:
	if not is_building:
		return
	if complete:
		model.scale = Vector3.ONE
		model.position.y = 0.0
	else:
		var f := clampf(aux / 100.0, 0.02, 1.0)
		model.scale = Vector3(1, f, 1)

func _process(dt: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var rt := now - INTERP_DELAY
	var span := t1 - t0
	if span > 0.0001 and t1 > 0.0:
		var a := clampf((rt - t0) / span, 0.0, 1.25)
		cur_pos = p0.lerp(p1, a)
		cur_yaw = lerp_angle(yaw0, yaw1, minf(a, 1.0))
		if turret != null:
			turret.rotation.y = lerp_angle(tyaw0, tyaw1, minf(a, 1.0)) - cur_yaw
	if dt > 0.0:
		vel = vel.lerp((cur_pos - prev_pos) / dt, 0.3)
		yaw_rate = lerpf(yaw_rate, wrapf(cur_yaw - prev_yaw, -PI, PI) / dt, 0.3)
	prev_pos = cur_pos
	prev_yaw = cur_yaw
	position = cur_pos
	rotation.y = cur_yaw
	if is_building:
		_process_building(now)
		if loop != null and complete:
			loop.queue_free()
			loop = null
	else:
		_process_unit(dt, now)
	var want_alpha := 0.45 if (flags & 4) != 0 else 1.0
	if want_alpha != stealth_alpha:
		stealth_alpha = want_alpha
		if team_ring:
			team_ring.visible = want_alpha >= 1.0
	sel_ring.visible = selected or hovered

func _process_building(now: float) -> void:
	if not complete:
		var f := clampf(aux / 100.0, 0.02, 1.0)
		model.scale = Vector3(1, f, 1)
	var unpowered := (flags & 16) != 0 and complete
	if unpowered != blackout:
		blackout = unpowered
		_set_blackout(unpowered)
	if blackout and blackout_mat != null:
		var k := 0.5 + 0.5 * sin(now * 4.0)
		blackout_mat.albedo_color = Color(0.02, 0.03, 0.08 + 0.25 * k, 0.75)
		blackout_mat.emission = Color(0.1, 0.3, 1.0) * k * 0.6
	if hp_frac < 0.5 and complete and smoke == null:
		_add_smoke()
	elif (hp_frac >= 0.5 or not complete) and smoke != null:
		smoke.queue_free()
		smoke = null

## Unpowered structures go dark with a slow blue pulse.
func _set_blackout(on: bool) -> void:
	if on and blackout_mat == null:
		blackout_mat = StandardMaterial3D.new()
		blackout_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		blackout_mat.albedo_color = Color(0.02, 0.03, 0.1, 0.75)
		blackout_mat.emission_enabled = true
		blackout_mat.emission = Color(0.1, 0.3, 1.0) * 0.3
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = blackout_mat if on else null
	if pad:
		pad.material_override = Visuals.flat_mat(Color(0.12, 0.12, 0.18), false) if on else Visuals.flat_mat(Color(0.32, 0.31, 0.3), false)

func _add_smoke() -> void:
	var p := CPUParticles3D.new()
	p.amount = 12
	p.lifetime = 2.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.4
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0.3, 0.5, 0)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
	p.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.15, 0.15, 0.15, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = m
	p.position.y = float(def.get("height", 6.0)) * 0.5
	add_child(p)
	smoke = p

func _process_unit(dt: float, now: float) -> void:
	var moving := (flags & 1) != 0
	var speed := Vector3(vel.x, 0, vel.z).length()
	if anim != null:
		if (flags & 2) != 0:
			_play("fire", 0.05)
		elif moving or speed > 0.5:
			_play("run")
		else:
			_play("idle")
	# rotors always spin on helicopters; on jets only while airborne
	var airborne := cat == "air" and cur_pos.y > 0.3
	for r in rotors:
		if cat != "air" or airborne or not def.get("jet", false):
			match str(r.get_meta("axis", "y")):
				"x":
					r.rotate_x(dt * 45.0)
				"slow":
					r.rotate_y(dt * 1.5)
				_:
					r.rotate_y(dt * 40.0)
	# wheels spin with ground speed
	if not wheels.is_empty() and cat != "air":
		var wr := 0.4
		for wl in wheels:
			wl.rotate_x(speed * dt / wr)
	# banking / pitching
	if tilt != null:
		var roll := 0.0
		var pitch := 0.0
		if cat == "air":
			if def.get("jet", false):
				roll = clampf(-yaw_rate * 0.9, -0.9, 0.9)
				pitch = clampf(-vel.y * 0.08, -0.5, 0.5)
			else:
				var fwd := Vector3(sin(cur_yaw), 0, cos(cur_yaw))
				var right := Vector3(cos(cur_yaw), 0, -sin(cur_yaw))
				var fs := vel.dot(fwd)
				var rs := vel.dot(right)
				pitch = clampf(fs * 0.02, -0.35, 0.35)
				roll = clampf(-rs * 0.02 - yaw_rate * 0.25, -0.4, 0.4)
				# hover bob
				tilt.position.y = sin(now * 2.3 + id) * 0.15 if airborne else 0.0
		tilt.rotation.x = lerpf(tilt.rotation.x, pitch, 0.15)
		tilt.rotation.z = lerpf(tilt.rotation.z, roll, 0.15)
	if loop != null:
		if cat == "air" and def.get("jet", false):
			loop.volume_db = loop_base_db + 4.0 if airborne else -80.0
		elif cat == "air":
			loop.volume_db = loop_base_db + 2.0
		else:
			loop.volume_db = loop_base_db + (0.0 if speed > 0.5 else -8.0)
	# tyre tracks
	if cat == "veh" and speed > 0.3 and cur_pos.y < 0.5:
		track_dist += speed * dt
		if track_dist > 1.6:
			track_dist = 0.0
			var view := get_parent()
			if view != null and view.has_method("leave_track"):
				view.leave_track(cur_pos, cur_yaw, radius * 0.7, def.get("crusher", false))
	if cat == "air" and team_ring:
		team_ring.position.y = -cur_pos.y + 0.03

func is_stale(now: float) -> bool:
	return not is_building and now - last_update > 0.7

func detach_model() -> Node3D:
	if model.get_parent() != null:
		model.get_parent().remove_child(model)
	return model

## Screen-space bounding rectangle of the model (for picking).
func screen_rect(cam: RtsCamera) -> Rect2:
	var xf := global_transform * tilt.transform * model.transform
	var minv := Vector2(1e9, 1e9)
	var maxv := Vector2(-1e9, -1e9)
	for i in range(8):
		var wp := xf * aabb.get_endpoint(i)
		if cam.is_behind(wp):
			return Rect2()
		var sp := cam.to_screen(wp)
		minv = Vector2(minf(minv.x, sp.x), minf(minv.y, sp.y))
		maxv = Vector2(maxf(maxv.x, sp.x), maxf(maxv.y, sp.y))
	return Rect2(minv, maxv - minv)
