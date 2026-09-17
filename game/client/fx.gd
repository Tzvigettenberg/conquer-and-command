class_name Fx
extends Node3D
## Client-only effects: projectiles, impacts, explosions, wrecks, beams, strikes.

var items: Array = []     # [{node, kind, t, life, from, to, ...}]
var wrecks: Array = []

func _process(dt: float) -> void:
	var keep := []
	for it in items:
		it["t"] += dt
		var a: float = it["t"] / it["life"]
		var n: Node3D = it["node"]
		if a >= 1.0:
			n.queue_free()
			_on_finish(it)
			continue
		match it["kind"]:
			"proj":
				var f: Vector3 = it["from"]
				var to: Vector3 = it["to"]
				var p := f.lerp(to, a)
				if it.get("arc", 0.0) > 0.0:
					p.y += sin(a * PI) * it["arc"]
				var look := to - f
				if it.get("arc", 0.0) > 0.0:
					var nxt := f.lerp(to, minf(a + 0.02, 1.0))
					nxt.y += sin(minf(a + 0.02, 1.0) * PI) * it["arc"]
					look = nxt - p
				n.position = p
				if look.length() > 0.01:
					n.look_at(p + look, Vector3.UP)
				if it.get("style", "") == "missile" or it.get("style", "") == "cruise":
					it["puff_t"] = float(it.get("puff_t", 0.0)) + dt
					if it["puff_t"] > 0.035:
						it["puff_t"] = 0.0
						_puff(p, 0.28 if it["style"] == "missile" else 0.5, Color(0.85, 0.85, 0.85, 0.55), 0.9)
			"flash":
				n.scale = Vector3.ONE * (1.0 + a * 1.5)
				_fade(n, 1.0 - a)
			"boom":
				var s: float = it["size"]
				n.scale = Vector3.ONE * (0.3 + a * 1.2) * s
				_fade(n, (1.0 - a) * 0.9)
				if it.has("light"):
					(it["light"] as OmniLight3D).light_energy = (1.0 - a) * 6.0
			"ring":
				n.scale = Vector3(1.0 + a * 4.0, 1.0, 1.0 + a * 4.0) * it["size"]
				_fade(n, (1.0 - a) * 0.7)
			"smoke":
				n.position.y += dt * 1.5
				n.scale = Vector3.ONE * (0.5 + a * 1.5) * it["size"]
				_fade(n, (1.0 - a) * 0.5)
			"beam":
				_fade(n, 1.0 - a)
			"jet":
				var f: Vector3 = it["from"]
				var to: Vector3 = it["to"]
				n.position = f.lerp(to, a)
			"para":
				n.position.y = lerpf(it["from"].y, 0.0, a)
			"track":
				if a > 0.6:
					_fade(n, (1.0 - a) / 0.4 * 0.55)
			"puff":
				n.scale = Vector3.ONE * (1.0 + a * it.get("grow", 2.0))
				_fade(n, (1.0 - a) * it.get("alpha", 0.5))
				n.position.y += dt * 0.4
			"crash_jet":
				var v: Vector3 = it["vel"]
				v.y -= 9.0 * dt
				it["vel"] = v
				n.position += v * dt
				n.rotate_object_local(Vector3.FORWARD, dt * 1.5)
				n.rotation.x = lerpf(n.rotation.x, -0.9, dt * 1.2)
				if fmod(it["t"], 0.08) < dt:
					_puff(n.position, 0.9, Color(0.1, 0.1, 0.1, 0.6), 1.4)
				if n.position.y <= 0.3:
					explosion(Vector3(n.position.x, 0, n.position.z), 2.2)
					Audio.I.sfx("explosion_medium", n.position, 2.0)
					it["t"] = it["life"]
			"crash_heli":
				var v: Vector3 = it["vel"]
				v.y -= 6.0 * dt
				v.x *= 0.99
				v.z *= 0.99
				it["vel"] = v
				n.position += v * dt
				n.rotate_y(dt * 9.0)
				n.rotation.z = lerpf(n.rotation.z, 0.5, dt)
				if fmod(it["t"], 0.08) < dt:
					_puff(n.position, 0.9, Color(0.1, 0.1, 0.1, 0.6), 1.4)
				if n.position.y <= 0.3:
					explosion(Vector3(n.position.x, 0, n.position.z), 2.0)
					Audio.I.sfx("explosion_medium", n.position, 2.0)
					it["t"] = it["life"]
			"text":
				n.position.y += dt * 2.0
				if n is Label3D:
					var c: Color = (n as Label3D).modulate
					(n as Label3D).modulate = Color(c.r, c.g, c.b, 1.0 - a)
		keep.append(it)
	items = keep
	var wk := []
	for w in wrecks:
		w["t"] += dt
		if w["t"] > w["life"]:
			w["node"].queue_free()
		else:
			if w["t"] > w["life"] - 3.0:
				(w["node"] as Node3D).position.y = -(w["t"] - (w["life"] - 3.0)) * 0.6
			wk.append(w)
	wrecks = wk

func _fade(n: Node3D, alpha: float) -> void:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override
		if m is StandardMaterial3D:
			var c: Color = m.albedo_color
			m.albedo_color = Color(c.r, c.g, c.b, alpha)
	if n is MeshInstance3D and n.material_override is StandardMaterial3D:
		var c: Color = n.material_override.albedo_color
		n.material_override.albedo_color = Color(c.r, c.g, c.b, alpha)

func _on_finish(it: Dictionary) -> void:
	if it["kind"] == "proj" and it.get("impact", false):
		impact(it["to"], it["style"])
	elif it["kind"] == "crash_jet" or it["kind"] == "crash_heli":
		var n: Node3D = it["node"]
		var w := Visuals.make_wreck(it["type"])
		w.position = Vector3(n.position.x, 0, n.position.z)
		w.rotation.y = n.rotation.y
		w.rotation.z = randf_range(-0.4, 0.4)
		add_child(w)
		wrecks.append({"node": w, "t": 0.0, "life": 25.0})

func _puff(pos: Vector3, size: float, color: Color, life: float, grow := 2.0) -> void:
	var sm := Visuals.sphere(size, color)
	sm.material_override = _own_mat(color)
	sm.position = pos
	_add(sm, "puff", life, {"grow": grow, "alpha": color.a})

## Wingtip vapour trails: a short thin segment per wingtip that fades and widens.
func contrail(a: Vector3, b: Vector3) -> void:
	for p in [a, b]:
		var sm := Visuals.sphere(0.22, Color(1, 1, 1, 0.45))
		sm.material_override = _own_mat(Color(1, 1, 1, 0.45))
		sm.position = p
		_add(sm, "puff", 1.6, {"grow": 3.0, "alpha": 0.45})

## Aircraft death: jets nose over along their heading, helicopters spin down. Explodes on impact.
func crash(type: String, pos: Vector3, yaw: float, model: Node3D, speed_hint := 20.0) -> void:
	if model == null:
		explosion(pos, 2.0)
		return
	add_child(model)
	model.position = pos
	model.rotation.y = yaw
	var def := Data.def(type)
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	if def.get("jet", false):
		_add(model, "crash_jet", 12.0, {"vel": fwd * maxf(speed_hint, 14.0) + Vector3(0, 2.0, 0), "type": type})
	else:
		_add(model, "crash_heli", 12.0, {"vel": fwd * 3.0 + Vector3(0, 1.0, 0), "type": type})
	explosion(pos, 0.8)

func _own_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _add(node: Node3D, kind: String, life: float, extra := {}) -> Dictionary:
	add_child(node)
	var it := {"node": node, "kind": kind, "t": 0.0, "life": life}
	it.merge(extra)
	items.append(it)
	return it

# ---------------------------------------------------------------------------
func shot(from: Vector3, to: Vector3, wid: String) -> void:
	var wd: Dictionary = Data.WEAPONS.get(wid, {})
	var style: String = wd.get("style", "bullet")
	var spd := float(wd.get("speed", 0.0))
	var d := from.distance_to(to)
	muzzle(from, to)
	match style:
		"bullet":
			var tr := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.18, 0.18, minf(7.0, d * 0.6))
			tr.mesh = bm
			tr.material_override = _own_mat(Color(1.0, 0.85, 0.4, 1.0))
			tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_add(tr, "proj", clampf(d / 160.0, 0.1, 0.35), {"from": from, "to": to, "style": style, "impact": true})
		"beam":
			var b := _beam_mesh(from, to, Color(0.4, 0.9, 1.0, 0.9), 0.12)
			_add(b, "beam", 0.12)
		"shell", "missile", "cruise", "bomb":
			var life := d / maxf(spd, 1.0)
			var arc := 0.0
			if style == "shell":
				arc = d * 0.12
			elif style == "cruise":
				arc = d * 0.35 + 8.0
			var pm := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = 0.12 if style != "cruise" else 0.3
			cap.height = 0.6 if style != "cruise" else 2.5
			pm.mesh = cap
			pm.rotation_degrees.x = 90.0
			var holder := Node3D.new()
			holder.add_child(pm)
			pm.material_override = _own_mat(Color(0.9, 0.9, 0.9) if style != "shell" else Color(0.3, 0.3, 0.3))
			if style == "missile" or style == "cruise":
				var flame := MeshInstance3D.new()
				var s := SphereMesh.new()
				s.radius = 0.18
				s.height = 0.36
				flame.mesh = s
				flame.material_override = _own_mat(Color(1.0, 0.6, 0.2))
				flame.position.z = -0.5
				holder.add_child(flame)
				var light := OmniLight3D.new()
				light.light_color = Color(1.0, 0.7, 0.3)
				light.light_energy = 1.5
				light.omni_range = 6.0
				holder.add_child(light)
			_add(holder, "proj", life, {"from": from, "to": to, "style": style, "arc": arc, "impact": false})

func _beam_mesh(from: Vector3, to: Vector3, color: Color, width: float) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var d := from.distance_to(to)
	bm.size = Vector3(width, width, d)
	mi.mesh = bm
	mi.material_override = _own_mat(color)
	mi.position.z = d * 0.5
	n.add_child(mi)
	n.position = from
	if d > 0.01:
		n.look_at(to, Vector3.UP)
	return n

func muzzle(from: Vector3, to: Vector3) -> void:
	var s := Visuals.sphere(0.35, Color(1.0, 0.85, 0.4, 0.9))
	s.material_override = _own_mat(Color(1.0, 0.85, 0.4, 0.9))
	var dir := (to - from).normalized()
	s.position = from + dir * 1.2 + Vector3(0, 0.3, 0)
	_add(s, "flash", 0.08)

func impact(pos: Vector3, style: String) -> void:
	var size := 0.5
	match style:
		"bullet":
			size = 0.25
		"shell":
			size = 1.0
		"missile":
			size = 1.2
		"cruise":
			size = 3.0
		"bomb":
			size = 4.0
		"beam":
			size = 1.5
	if style == "bullet":
		var p := Visuals.sphere(0.3, Color(1.0, 0.8, 0.5, 0.8))
		p.material_override = _own_mat(Color(1.0, 0.8, 0.5, 0.8))
		p.position = pos + Vector3(0, 0.6, 0)
		_add(p, "flash", 0.1)
		return
	explosion(pos, size)

func explosion(pos: Vector3, size: float) -> void:
	var ball := Visuals.sphere(1.0, Color(1.0, 0.55, 0.15, 0.9))
	ball.material_override = _own_mat(Color(1.0, 0.55, 0.15, 0.9))
	ball.position = pos + Vector3(0, size * 0.6, 0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.omni_range = 8.0 * size
	light.light_energy = 6.0
	ball.add_child(light)
	_add(ball, "boom", 0.45 + size * 0.1, {"size": size, "light": light})
	var ring := Visuals.disc(1.0, Color(1.0, 0.8, 0.4, 0.7))
	ring.material_override = _own_mat(Color(1.0, 0.8, 0.4, 0.7))
	ring.position = pos + Vector3(0, 0.15, 0)
	_add(ring, "ring", 0.5, {"size": size})
	for i in range(3 if size > 0.8 else 1):
		var sm := Visuals.sphere(1.0, Color(0.15, 0.15, 0.15, 0.5))
		sm.material_override = _own_mat(Color(0.2, 0.2, 0.2, 0.5))
		sm.position = pos + Vector3(randf_range(-1, 1) * size, size * 0.8 + i * 0.6 * size, randf_range(-1, 1) * size)
		_add(sm, "smoke", 1.5 + size * 0.4, {"size": size})

func death(type: String, pos: Vector3, yaw: float, model: Node3D = null) -> void:
	var def := Data.def(type)
	var size := 1.0
	if Data.is_building(type):
		size = 3.5
	elif def.get("cat", "") == "inf":
		size = 0.0
	else:
		size = 1.6
	if size > 0.0:
		explosion(pos, size)
	if def.get("cat", "") == "inf":
		if model != null:
			# play the death clip on the detached model then sink it
			add_child(model)
			model.position = pos
			model.rotation.y = yaw
			var players := model.find_children("*", "AnimationPlayer", true, false)
			var played := false
			for p in players:
				if p.has_animation("f/death"):
					p.play("f/death", 0.05)
					played = true
			if not played:
				model.rotation.x = -PI * 0.5
			wrecks.append({"node": model, "t": 0.0, "life": 8.0})
		return
	var w := Visuals.make_wreck(type)
	w.position = pos
	w.rotation.y = yaw
	if def.get("cat", "") == "air":
		w.rotation.z = randf_range(-0.4, 0.4)
	add_child(w)
	wrecks.append({"node": w, "t": 0.0, "life": 45.0 if Data.is_building(type) else 25.0})
	for i in range(2):
		var sm := Visuals.sphere(1.0, Color(0.1, 0.1, 0.1, 0.6))
		sm.material_override = _own_mat(Color(0.1, 0.1, 0.1, 0.6))
		sm.position = pos + Vector3(randf_range(-2, 2), 2.0, randf_range(-2, 2))
		_add(sm, "smoke", 6.0, {"size": size})

func particle_beam(pos: Vector3) -> void:
	var b := _beam_mesh(pos + Vector3(0, 120, 0), pos, Color(0.6, 0.9, 1.0, 0.9), 1.6)
	_add(b, "beam", 0.3)
	var core := _beam_mesh(pos + Vector3(0, 120, 0), pos, Color(1.0, 1.0, 1.0, 1.0), 0.5)
	_add(core, "beam", 0.3)
	explosion(pos, 2.0)

func strike(kind: String, pos: Vector3, heading: float, level: int) -> void:
	match kind:
		"a10":
			for i in range(maxi(1, level)):
				var jet := Visuals.make_model("raptor", -1)
				jet.scale = Vector3.ONE * 1.1
				var dir := Vector3(cos(heading), 0, sin(heading))
				var side := dir.cross(Vector3.UP) * ((i - 1) * 6.0)
				var from := pos - dir * 160.0 + Vector3(0, 30, 0) + side
				var to := pos + dir * 160.0 + Vector3(0, 30, 0) + side
				jet.look_at_from_position(from, to, Vector3.UP)
				jet.rotate_y(PI)
				_add(jet, "jet", 8.0, {"from": from, "to": to})
				# gun run at ~2.4 s (jet ~64 m short of the target), missiles at ~3.6 s
				for k in range(8):
					var delay := 2.4 + k * 0.1
					_later(delay, func() -> void:
						var jp: Vector3 = from.lerp(to, delay / 8.0)
						var gp := pos + side + dir * (-20.0 + k * 5.0)
						shot(jp, gp, "a10_gun"))
				_later(2.4, func() -> void: Audio.I.sfx("gau8", pos + Vector3(0, 20, 0), 4.0))
				for k in range(2):
					var delay := 3.4 + k * 0.25
					_later(delay, func() -> void:
						var jp: Vector3 = from.lerp(to, delay / 8.0)
						shot(jp, pos + side + dir * (k * 4.0), "a10_missile"))
		"paradrop":
			var plane := Visuals.make_model("chinook", -1)
			plane.scale = Vector3.ONE * 1.5
			var from := pos + Vector3(-150, 40, 0)
			var to := pos + Vector3(150, 40, 0)
			plane.look_at_from_position(from, to, Vector3.UP)
			plane.rotate_y(PI)
			_add(plane, "jet", 6.0, {"from": from, "to": to})
			for i in range(4):
				var chute := Visuals.sphere(1.2, Color(0.9, 0.9, 0.9, 0.9))
				chute.material_override = _own_mat(Color(0.9, 0.9, 0.9, 0.9))
				chute.position = pos + Vector3(randf_range(-4, 4), 30, randf_range(-4, 4))
				_add(chute, "para", 6.0, {"from": chute.position})
		"fuel_air_bomb":
			var plane := Visuals.make_model("aurora", -1)
			plane.scale = Vector3.ONE * 2.0
			var from := pos + Vector3(0, 45, -200)
			var to := pos + Vector3(0, 45, 200)
			plane.look_at_from_position(from, to, Vector3.UP)
			plane.rotate_y(PI)
			_add(plane, "jet", 8.0, {"from": from, "to": to})
		"spy_satellite":
			var ring := Visuals.ring(60.0, Color(0.4, 1.0, 0.6, 0.6), 0.6)
			ring.material_override = _own_mat(Color(0.4, 1.0, 0.6, 0.6))
			ring.position = pos + Vector3(0, 0.3, 0)
			_add(ring, "beam", 15.0)
		"emergency_repair":
			var ring := Visuals.ring(20.0, Color(0.4, 0.8, 1.0, 0.7), 0.5)
			ring.material_override = _own_mat(Color(0.4, 0.8, 1.0, 0.7))
			ring.position = pos + Vector3(0, 0.3, 0)
			_add(ring, "beam", 2.0)

## Tyre / track marks left behind by vehicles.
func track(pos: Vector3, yaw: float, half_w: float, tracked: bool) -> void:
	var n := Node3D.new()
	n.position = Vector3(pos.x, 0.05, pos.z)
	n.rotation.y = yaw
	var w := 0.35 if tracked else 0.22
	for side in [-1.0, 1.0]:
		var m := MeshInstance3D.new()
		var q := BoxMesh.new()
		q.size = Vector3(w, 0.01, 1.7)
		m.mesh = q
		m.material_override = _own_mat(Color(0.12, 0.09, 0.05, 0.55))
		m.position = Vector3(side * half_w, 0, 0)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(m)
	_add(n, "track", 30.0)

func _later(delay: float, cb: Callable) -> void:
	get_tree().create_timer(delay).timeout.connect(cb)

func placed(pos: Vector3, fp: Vector2) -> void:
	var ring := Visuals.box(Vector3(fp.x, 0.1, fp.y), Color(0.3, 1.0, 0.4, 0.5), true)
	ring.position = pos + Vector3(0, 0.2, 0)
	_add(ring, "beam", 0.8)

func floating_text(pos: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.font_size = 64
	l.pixel_size = 0.02
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos + Vector3(0, 4, 0)
	add_child(l)
	items.append({"node": l, "kind": "text", "t": 0.0, "life": 1.5})
