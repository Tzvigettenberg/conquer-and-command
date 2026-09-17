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
var aux2 := 0
var anims: Array = []
var tyaw_changed_t := 0.0
var capture_mat: StandardMaterial3D = null
var capture_loop: AudioStreamPlayer3D = null
var trail_t := 0.0

var model: Node3D
var turret: Node3D = null
var limbs: Dictionary = {}
var door_t := 0.0
var scaffold: Node3D = null
var site_label: Label3D = null
var site_bar: MeshInstance3D = null
var site_bar_bg: MeshInstance3D = null
var rev_t := 0.0
var was_moving := false
var door_node: Node3D = null
var door_y := 0.0
var door_lights: Array = []
var walk_t := 0.0
var extras_key := ""              # which upgrade / plan add-ons are shown
var extras_node: Node3D = null
var rotors: Array[Node3D] = []
var gear_nodes: Array = []
var burners: Array = []
var missiles: Array = []
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
	if model.has_meta("anim"):
		anims = model.get_meta("anim")
	if not is_building and cat != "inf" and not model.has_meta("procedural"):
		Visuals.tint_unit(model, team)
	door_node = model.find_child("Door", true, false)
	if door_node != null:
		door_y = door_node.position.y
		for n in model.find_children("Light*", "MeshInstance3D", true, false):
			door_lights.append(n)
	for nm in ["LegL", "LegR", "ArmL", "ArmR"]:
		var limb := model.find_child(nm, true, false)
		if limb != null:
			limbs[nm] = limb
	for n in model.find_children("*", "Node3D", true, false):
		var nm: String = n.name
		if "Rotor" in nm or "Blade" in nm or "Propeller" in nm:
			rotors.append(n)
			n.set_meta("axis", "x" if ("Back" in nm or "Tail" in nm) else "y")
		elif "Dish" in nm or "Radar" in nm and cat != "bld":
			rotors.append(n)
			n.set_meta("axis", "slow")
		elif "Wheel" in nm and not ("Turret" in nm or "Gear" in nm or "Cover" in nm or "Steering" in nm):
			wheels.append(n)
		elif nm == "Gear":
			gear_nodes.append(n)
		elif nm.begins_with("Afterburner"):
			burners.append(n)
		elif nm.begins_with("Missile"):
			missiles.append(n)
	missiles.sort_custom(func(a: Node, b: Node) -> bool: return a.name < b.name)
	if is_building:
		var fp: Vector2 = Data.footprint_size(type)
		var col := Color(0.32, 0.31, 0.3)
		if def.get("neutral", false):
			col = Color(0.4, 0.38, 0.33)
		pad = Visuals.box(Vector3(fp.x, 0.12, fp.y), col)
		pad.position.y = 0.06
		add_child(pad)
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
	if cat == "inf":
		name = "footsteps"
	if is_building and not complete:
		name = "construction"
	if name == "":
		return
	loop = Audio.I.make_loop(name, -6.0)
	if loop != null:
		loop_base_db = -6.0 if cat != "inf" else -9.0
		add_child(loop)

## Supply dock: a grid of crate stacks that empties as boxes are hauled away.
func _build_crates() -> void:
	# our own crate stacks on the dock pad; they disappear as the supplies run out
	var fp: Vector2 = Data.footprint_size(type)
	var cols := 3
	var rows := 3
	for r in range(rows):
		for c in range(cols):
			var stack := Node3D.new()
			var n := 2 + ((r * 3 + c) % 3)
			for k in range(n):
				var sz := 1.25 - k * 0.12
				var crate := Visuals.box(Vector3(sz, 1.0, sz), Color(0.78, 0.62, 0.3) if (k + c) % 2 == 0 else Color(0.62, 0.5, 0.26))
				crate.position = Vector3(0, 0.5 + k * 1.0, 0)
				crate.rotation.y = k * 0.35
				stack.add_child(crate)
				var strap := Visuals.box(Vector3(sz + 0.04, 0.12, 0.2), Color(0.25, 0.25, 0.28))
				strap.position = Vector3(0, 0.5 + k * 1.0, 0)
				strap.rotation.y = k * 0.35
				stack.add_child(strap)
			stack.position = Vector3(-fp.x * 0.5 + 1.9 + c * (fp.x - 3.8) / (cols - 1) - 0.6, 0.14, -fp.y * 0.5 + 1.6 + r * (fp.y - 3.2) / (rows - 1))
			stack.rotation.y = (r * 3 + c) * 0.4
			add_child(stack)
			crates.append(stack)
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

func apply_state(pos: Vector2, alt: float, yaw: float, tyaw: float, hpf: float, fl: int, ax: int, ax2: int, now: float) -> void:
	if absf(wrapf(tyaw - tyaw1, -PI, PI)) > 0.01:
		tyaw_changed_t = now
	aux2 = ax2
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
		if turret != null and not is_building:
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

## Construction site dressing: yellow scaffold posts and rails around the footprint,
## a progress bar and an UNFINISHED warning when nobody is building.
func _build_scaffold() -> void:
	scaffold = Node3D.new()
	add_child(scaffold)
	var fp: Vector2 = Data.footprint_size(type)
	var h := float(def.get("height", 6.0)) * 0.6
	var col := Color(0.95, 0.75, 0.2)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var post := Visuals.box(Vector3(0.18, h, 0.18), col)
			post.position = Vector3(sx * fp.x * 0.5, h * 0.5, sz * fp.y * 0.5)
			scaffold.add_child(post)
		var rail := Visuals.box(Vector3(fp.x, 0.12, 0.12), col)
		rail.position = Vector3(0, h, sx * fp.y * 0.5)
		scaffold.add_child(rail)
		var rail2 := Visuals.box(Vector3(0.12, 0.12, fp.y), col)
		rail2.position = Vector3(sx * fp.x * 0.5, h, 0)
		scaffold.add_child(rail2)
	site_bar_bg = Visuals.box(Vector3(fp.x * 0.8, 0.25, 0.5), Color(0.1, 0.1, 0.1, 0.9), true)
	site_bar_bg.position = Vector3(0, h + 0.8, fp.y * 0.5)
	scaffold.add_child(site_bar_bg)
	site_bar = Visuals.box(Vector3(fp.x * 0.8, 0.3, 0.55), Color(0.3, 0.95, 0.4), true)
	site_bar.position = Vector3(0, h + 0.8, fp.y * 0.5)
	scaffold.add_child(site_bar)
	site_label = Label3D.new()
	site_label.font_size = 56
	site_label.pixel_size = 0.02
	site_label.modulate = Color(1.0, 0.6, 0.2)
	site_label.outline_size = 8
	site_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	site_label.no_depth_test = true
	site_label.position = Vector3(0, h + 2.4, 0)
	scaffold.add_child(site_label)

func flash_cargo() -> void:
	var l := Label3D.new()
	l.text = "+1"
	l.font_size = 48
	l.pixel_size = 0.02
	l.modulate = Color(0.5, 0.9, 1.0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0, 3.0, 0)
	add_child(l)
	get_tree().create_timer(0.8).timeout.connect(l.queue_free)

## Factory door: slides up, lights flash, closes again after a while.
func open_door(seconds: float) -> void:
	door_t = seconds

func _door_anim(dt: float, now: float) -> void:
	if door_node == null:
		return
	var open := door_t > 0.0
	door_t = maxf(0.0, door_t - dt)
	var target := door_y + (3.2 if open else 0.0)
	door_node.position.y = move_toward(door_node.position.y, target, 5.0 * dt)
	for l in door_lights:
		l.visible = open and fmod(now * 4.0, 1.0) < 0.5

func _process_building(now: float) -> void:
	_door_anim(get_process_delta_time(), now)
	if not complete:
		var f := clampf(aux / 100.0, 0.02, 1.0)
		model.scale = Vector3(1, f, 1)
		if scaffold == null:
			_build_scaffold()
		scaffold.visible = true
		# no dozer working on it: flash the warning so half-built sites are obvious
		var idle := aux2 == 0
		site_label.visible = idle and fmod(now * 2.0, 1.0) < 0.6
		site_label.text = "UNFINISHED  %d%%" % aux
		site_bar.scale.x = maxf(f, 0.02)
		site_bar_bg.visible = true
		site_bar.visible = true
	elif scaffold != null:
		scaffold.visible = false
		site_label.visible = false
		site_bar.visible = false
		site_bar_bg.visible = false
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
	_idle_anims(now, get_process_delta_time())
	_capture_fx(now)

## Upgrade and battle-plan visuals: small add-on parts so you can see at a glance
## what a unit or structure has (TOW pod, armour skirts, control rods, the
## Strategy Center's cannon / sandbags / scanner).
func set_extras(keys: Array) -> void:
	var key := ",".join(keys)
	if key == extras_key:
		return
	extras_key = key
	if extras_node != null:
		extras_node.queue_free()
		extras_node = null
	# plan parts live in the building model itself
	if model != null:
		for nm in ["PlanHold", "PlanSearch"]:
			var n := model.find_child(nm, true, false)
			if n != null:
				n.visible = keys.has("plan_hold" if nm == "PlanHold" else "plan_search")
		var cannon := model.find_child("Cannon", true, false)
		if cannon != null:
			cannon.visible = keys.has("plan_bombardment")
		if type == "power_plant":
			# control rods: blue-white steam instead of grey
			var rods := keys.has("control_rods")
			for ps in model.find_children("*", "CPUParticles3D", true, false):
				var m := (ps as CPUParticles3D).material_override as StandardMaterial3D
				if m != null:
					m.albedo_color = Color(0.45, 0.75, 1.0, 0.5) if rods else Color(0.9, 0.9, 0.9, 0.35)
					m.emission_enabled = rods
					m.emission = Color(0.3, 0.6, 1.0)
				(ps as CPUParticles3D).amount = 18 if rods else 10
	var parts := Visuals.make_extras(type, keys, team, aabb)
	if parts != null:
		extras_node = parts
		if tilt != null:
			tilt.add_child(parts)
		else:
			add_child(parts)

## Idle life: radar spin, launcher sweep, pump-jack nod, beacon blink, glow pulse.
func _idle_anims(now: float, dt: float) -> void:
	for a in anims:
		var n: Node3D = a["node"]
		var sp: float = a["speed"]
		match a["kind"]:
			"spin":
				n.rotate_y(dt * sp)
			"sweep":
				if n == turret:
					# defensive turret: follow the sim aim while engaged, sweep lazily when idle
					if now - tyaw_changed_t < 3.0 or (flags & 2) != 0:
						n.rotation.y = lerp_angle(n.rotation.y, tyaw1 - cur_yaw, 0.2)
					else:
						n.rotation.y = lerp_angle(n.rotation.y, sin(now * sp + id) * 1.2, 0.02)
				else:
					n.rotation.y = sin(now * sp + id) * 0.9
			"nod":
				n.rotation.x = sin(now * sp + id) * 0.25
			"pulse":
				var k := 0.75 + 0.25 * sin(now * sp * 2.0)
				n.scale = Vector3.ONE * k
			"blink":
				n.visible = fmod(now * sp, 1.0) < 0.5

## Being captured: flash between our colour and the capturing player's colour, with a beeping loop.
func _capture_fx(now: float) -> void:
	var capturing := aux2 > 0 and complete
	if capturing:
		var cap_team := aux2 - 1
		if capture_mat == null:
			capture_mat = StandardMaterial3D.new()
			capture_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			capture_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			for mi in model.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_overlay = capture_mat
			capture_loop = Audio.I.make_loop("beep", -6.0)
			if capture_loop != null:
				add_child(capture_loop)
		var c: Color = Data.TEAM_COLORS[cap_team] if cap_team < Data.TEAM_COLORS.size() else Color.WHITE
		var k := 0.5 + 0.5 * sin(now * 8.0)
		capture_mat.albedo_color = Color(c.r, c.g, c.b, 0.15 + 0.45 * k)
	elif capture_mat != null:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).material_overlay == capture_mat:
				(mi as MeshInstance3D).material_overlay = blackout_mat if blackout else null
		capture_mat = null
		if capture_loop != null:
			capture_loop.queue_free()
			capture_loop = null

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
	elif not limbs.is_empty():
		# blocky soldier: swing legs and arms while walking
		if moving or speed > 0.3:
			walk_t += dt * 9.0
			var a := sin(walk_t) * 0.7
			limbs["LegL"].rotation.x = a
			limbs["LegR"].rotation.x = -a
			limbs["ArmL"].rotation.x = -a * 0.6
			limbs["ArmR"].rotation.x = a * 0.6
		else:
			for k in limbs:
				limbs[k].rotation.x = lerpf(limbs[k].rotation.x, 0.0, 0.2)
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
	# jets: gear up in flight, afterburner with speed, missiles vanish as ammo is spent
	if cat == "air":
		for g in gear_nodes:
			g.visible = cur_pos.y < 1.5
		for b in burners:
			var on := speed > 6.0
			b.visible = on
			if on:
				b.scale = Vector3(1.0, 1.0, 0.6 + minf(speed / 25.0, 1.0) + 0.15 * sin(now * 60.0 + id))
		if not missiles.is_empty() and def.get("jet", false):
			var clip: int = aux
			for i in range(missiles.size()):
				missiles[i].visible = i < clip
		elif not missiles.is_empty():
			for i in range(missiles.size()):
				missiles[i].visible = aux2 > i * 5   # each rocket shown stands for 5 in the pod
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
		var mv := speed > 0.5
		if mv and not was_moving:
			rev_t = 1.2   # engine revs up when it sets off
		was_moving = mv
		rev_t = maxf(0.0, rev_t - dt)
		if cat == "air" and def.get("jet", false):
			loop.volume_db = loop_base_db + 4.0 if airborne else (loop_base_db - 6.0 if speed > 0.2 else -80.0)
			loop.pitch_scale = 1.0 + (0.25 if airborne else 0.0)
		elif cat == "air":
			loop.volume_db = loop_base_db + 2.0
		elif cat == "inf":
			loop.volume_db = loop_base_db if mv else -80.0   # footsteps only while walking
		else:
			loop.volume_db = loop_base_db + (0.0 if mv else -9.0) + rev_t * 5.0
			loop.pitch_scale = 0.9 + minf(speed / 8.0, 1.0) * 0.25 + rev_t * 0.1
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
	# contrails from fast fixed-wing aircraft
	if cat == "air" and def.get("jet", false) and airborne and speed > 12.0:
		trail_t += dt
		if trail_t > 0.12:
			trail_t = 0.0
			var view := get_parent()
			if view != null and view.has_method("contrail"):
				var right := Vector3(cos(cur_yaw), 0, -sin(cur_yaw))
				var half := float(def.get("length", 9.0)) * 0.42
				view.contrail(cur_pos + right * half, cur_pos - right * half)

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
