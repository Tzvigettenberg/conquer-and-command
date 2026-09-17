class_name Fx
extends Node3D
## Client-only effects: projectiles, impacts, explosions, wrecks, beams, strikes.

var items: Array = []     # [{node, kind, t, life, from, to, ...}]
var wrecks: Array = []

func _process(dt: float) -> void:
	_tick_pbeams(dt)
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
			"debris":
				var v: Vector3 = it["vel"]
				v.y -= 24.0 * dt
				it["vel"] = v
				n.position += v * dt
				if n.position.y < 0.1:
					n.position.y = 0.1
					it["vel"] = Vector3(v.x * 0.5, -v.y * 0.3, v.z * 0.5)
				n.rotation += it["spin"] * dt
			"marker":
				n.rotation.y += dt * 0.8
				var inner := n.get_node_or_null("Inner")
				if inner != null:
					inner.scale = Vector3.ONE * (0.6 + 0.4 * abs(sin(it["t"] * 6.0)))
				if a > 0.85:
					_fade(n, (1.0 - a) / 0.15)
			"bomb":
				var f: Vector3 = it["from"]
				var to: Vector3 = it["to"]
				var k := a * a
				n.position = f.lerp(to, k)
				n.look_at(f.lerp(to, minf(k + 0.05, 1.0)), Vector3.UP)
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
				for pr in it.get("props", []):
					(pr as Node3D).rotate_z(dt * 30.0)
			"para":
				if it.has("to"):
					var f2: Vector3 = it["from"]
					var t2: Vector3 = it["to"]
					n.position = Vector3(f2.x, lerpf(f2.y, t2.y, a), f2.z) + Vector3(sin(it["t"] * 1.5) * 0.6, 0, cos(it["t"] * 1.2) * 0.6)
					n.rotation.z = sin(it["t"] * 1.5) * 0.15
				else:
					n.position.y = lerpf(it["from"].y, 0.0, a)
			"particles":
				pass
			"beacon":
				var pulse := 0.7 + 0.3 * sin(it["t"] * 6.0)
				n.scale = Vector3(pulse, 1.0, pulse)
				if a > 0.8:
					_fade(n, (1.0 - a) / 0.2 * 0.5)
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
					burst("smoke", n.position, 0.7)
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
					burst("smoke", n.position, 0.7)
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

# ---------------------------------------------------------------------------
# Particle helpers (CPUParticles3D, unshaded billboard-ish spheres with colour ramps)
# ---------------------------------------------------------------------------
static var _pmats: Dictionary = {}
static func _pmat(add: bool) -> StandardMaterial3D:
	var key := "add" if add else "mix"
	if _pmats.has(key):
		return _pmats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pmats[key] = m
	return m

static var _pmesh: SphereMesh = null
static func _psphere() -> SphereMesh:
	if _pmesh == null:
		_pmesh = SphereMesh.new()
		_pmesh.radius = 0.5
		_pmesh.height = 1.0
		_pmesh.radial_segments = 6
		_pmesh.rings = 3
	return _pmesh

static func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for i in range(cols.size()):
		g.add_point(float(i) / maxf(cols.size() - 1, 1), cols[i])
	g.remove_point(0)
	g.remove_point(g.get_point_count() - 1)
	return g

## One-shot or continuous emitter. kind: fire | smoke | sparks | trail | dust | contrail
func particles(kind: String, pos: Vector3, size := 1.0, one_shot := true) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.mesh = _psphere()
	p.one_shot = one_shot
	p.local_coords = false
	match kind:
		"fire":
			p.amount = int(14 + 6 * size)
			p.lifetime = 0.65 + size * 0.15
			p.explosiveness = 0.9
			p.direction = Vector3.UP
			p.spread = 75.0
			p.initial_velocity_min = 1.5 + 1.0 * size
			p.initial_velocity_max = 3.5 + 2.0 * size
			p.gravity = Vector3(0, 3.0, 0)
			p.damping_min = 1.0
			p.damping_max = 2.5
			p.scale_amount_min = 0.7 + 0.35 * size
			p.scale_amount_max = 1.3 + 0.6 * size
			p.scale_amount_curve = _curve([0.8, 1.0, 0.3])
			p.color_ramp = _ramp([Color(1.0, 0.9, 0.35, 1.0), Color(1.0, 0.35, 0.05, 1.0), Color(0.3, 0.05, 0.02, 0.0)])
			p.material_override = _pmat(false)
		"smoke":
			p.amount = int(6 + 4 * size)
			p.lifetime = 1.4 + size * 0.4
			p.explosiveness = 0.85
			p.direction = Vector3.UP
			p.spread = 40.0
			p.initial_velocity_min = 1.0 + 0.8 * size
			p.initial_velocity_max = 2.0 + 1.6 * size
			p.gravity = Vector3(0.6, 1.2, 0)
			p.damping_min = 1.0
			p.damping_max = 2.0
			p.scale_amount_min = 0.5 + 0.35 * size
			p.scale_amount_max = 0.9 + 0.5 * size
			p.scale_amount_curve = _curve([0.4, 1.0, 1.3])
			p.color_ramp = _ramp([Color(0.28, 0.25, 0.22, 0.6), Color(0.22, 0.22, 0.22, 0.4), Color(0.3, 0.3, 0.3, 0.0)])
			p.material_override = _pmat(false)
		"sparks":
			p.amount = int(12 + 14 * size)
			p.lifetime = 0.7 + size * 0.15
			p.explosiveness = 1.0
			p.direction = Vector3.UP
			p.spread = 80.0
			p.initial_velocity_min = 8.0 * size
			p.initial_velocity_max = 18.0 * size
			p.gravity = Vector3(0, -22.0, 0)
			p.scale_amount_min = 0.12
			p.scale_amount_max = 0.22
			p.color_ramp = _ramp([Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.6, 0.2, 1.0), Color(0.6, 0.2, 0.05, 0.0)])
			p.material_override = _pmat(true)
		"dust":
			p.amount = int(10 + 5 * size)
			p.lifetime = 1.2 + size * 0.25
			p.explosiveness = 0.9
			p.direction = Vector3.UP
			p.spread = 88.0
			p.initial_velocity_min = 3.0 + 2.0 * size
			p.initial_velocity_max = 5.0 + 3.0 * size
			p.gravity = Vector3(0, -1.5, 0)
			p.damping_min = 3.0
			p.damping_max = 5.0
			p.scale_amount_min = 0.5 + 0.3 * size
			p.scale_amount_max = 0.9 + 0.5 * size
			p.scale_amount_curve = _curve([0.5, 1.0, 1.2])
			p.color_ramp = _ramp([Color(0.55, 0.48, 0.36, 0.6), Color(0.5, 0.45, 0.35, 0.3), Color(0.5, 0.45, 0.35, 0.0)])
			p.material_override = _pmat(false)
		"trail":
			# continuous rocket-motor smoke; attach to the projectile
			p.amount = 40
			p.lifetime = 1.1
			p.explosiveness = 0.0
			p.direction = Vector3(0, 0, -1)
			p.spread = 8.0
			p.initial_velocity_min = 0.5
			p.initial_velocity_max = 1.5
			p.gravity = Vector3(0, 0.5, 0)
			p.scale_amount_min = 0.35 * size
			p.scale_amount_max = 0.6 * size
			p.scale_amount_curve = _curve([0.4, 1.0, 1.5])
			p.color_ramp = _ramp([Color(1.0, 0.85, 0.6, 0.9), Color(0.85, 0.85, 0.85, 0.5), Color(0.8, 0.8, 0.8, 0.0)])
			p.material_override = _pmat(false)
		"contrail":
			p.amount = 30
			p.lifetime = 1.4
			p.explosiveness = 0.0
			p.direction = Vector3(0, 0, -1)
			p.spread = 3.0
			p.initial_velocity_min = 0.2
			p.initial_velocity_max = 0.6
			p.gravity = Vector3.ZERO
			p.scale_amount_min = 0.25
			p.scale_amount_max = 0.4
			p.scale_amount_curve = _curve([0.5, 1.0, 1.6])
			p.color_ramp = _ramp([Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.0)])
			p.material_override = _pmat(false)
	p.emitting = true
	return p

static func _curve(vals: Array) -> Curve:
	var c := Curve.new()
	for i in range(vals.size()):
		c.add_point(Vector2(float(i) / maxf(vals.size() - 1, 1), vals[i]))
	return c

## Fire-and-forget burst: node frees itself after lifetime.
func burst(kind: String, pos: Vector3, size := 1.0) -> void:
	var p := particles(kind, pos, size, true)
	add_child(p)
	_add(p, "particles", p.lifetime + 0.3)

func _on_finish(it: Dictionary) -> void:
	# a projectile's trail emitter lingers and fades after the missile is gone
	if it["kind"] == "proj" and it.has("trail"):
		var tr: CPUParticles3D = it["trail"]
		if is_instance_valid(tr):
			var gp := tr.global_position
			tr.get_parent().remove_child(tr)
			add_child(tr)
			tr.global_position = gp
			tr.emitting = false
			_add(tr, "particles", tr.lifetime + 0.2)
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
## Wingtip contrails: thin, faint, short-lived (fallback; jets carry their own emitters).
func contrail(a: Vector3, b: Vector3) -> void:
	for p in [a, b]:
		var sm := Visuals.sphere(0.12, Color(1, 1, 1, 0.16))
		sm.material_override = _own_mat(Color(1, 1, 1, 0.16))
		sm.position = p
		_add(sm, "puff", 0.9, {"grow": 1.6, "alpha": 0.16})

## Point-defence laser: red beam with a bright core, flash at the missile.
func laser(from: Vector3, to: Vector3) -> void:
	var b := _beam_mesh(from, to, Color(1.0, 0.15, 0.1, 0.8), 0.22)
	_add(b, "beam", 0.18)
	var core := _beam_mesh(from, to, Color(1.0, 0.8, 0.7, 1.0), 0.07)
	_add(core, "beam", 0.18)
	var p := Visuals.sphere(0.5, Color(1.0, 0.5, 0.4, 0.9))
	p.material_override = _own_mat(Color(1.0, 0.5, 0.4, 0.9))
	p.position = to
	_add(p, "flash", 0.2)

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
## Remove a projectile that was shot down; returns its current position (or (-9999,..) if unknown).
func kill_projectile(sid: int) -> Vector3:
	if sid < 0:
		return Vector3(-9999, 0, 0)
	for it in items:
		if it["kind"] == "proj" and int(it.get("sid", -1)) == sid:
			var n: Node3D = it["node"]
			var p := n.position
			it["life"] = 0.001   # ends next frame without the impact effect
			it["impact"] = false
			return p
	return Vector3(-9999, 0, 0)

func shot(from: Vector3, to: Vector3, wid: String, sid := -1) -> void:
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
			var b := _beam_mesh(from, to, Color(1.0, 0.2, 0.12, 0.85), 0.18)
			_add(b, "beam", 0.12)
			var core := _beam_mesh(from, to, Color(1.0, 0.85, 0.75, 1.0), 0.06)
			_add(core, "beam", 0.12)
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
			var extra := {"from": from, "to": to, "style": style, "arc": arc, "impact": false, "sid": sid}
			if style == "missile" or style == "cruise":
				var flame := MeshInstance3D.new()
				var s := SphereMesh.new()
				s.radius = 0.16 if style == "missile" else 0.3
				s.height = s.radius * 2.0
				flame.mesh = s
				flame.material_override = _own_mat(Color(1.0, 0.7, 0.25))
				(flame.material_override as StandardMaterial3D).emission_enabled = true
				(flame.material_override as StandardMaterial3D).emission = Color(1.0, 0.6, 0.2)
				flame.position.z = -0.45
				holder.add_child(flame)
				var light := OmniLight3D.new()
				light.light_color = Color(1.0, 0.7, 0.3)
				light.light_energy = 1.5
				light.omni_range = 6.0
				holder.add_child(light)
				var trail := particles("trail", Vector3(0, 0, -0.6), 1.0 if style == "missile" else 1.8, false)
				trail.local_coords = false
				holder.add_child(trail)
				extra["trail"] = trail
			_add(holder, "proj", life, extra)

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

## Explosion: bright core flash, a couple of fireballs, shockwave ring, debris
## chunks that arc out, dark smoke that lingers. size 1 = a tank shell, 4 = a bomb.
## Explosion: white-hot flash, fire burst, sparks, dark smoke, dust ring on the
## ground, shockwave and debris chunks. size 1 = a tank shell, 4 = a bomb, 9 = FAB.
func explosion(pos: Vector3, size: float) -> void:
	var core := Visuals.sphere(1.0, Color(1.0, 0.97, 0.8, 1.0))
	core.material_override = _own_mat(Color(1.0, 0.97, 0.8, 1.0))
	core.position = pos + Vector3(0, size * 0.5, 0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.omni_range = 12.0 * size
	light.light_energy = 10.0
	core.add_child(light)
	_add(core, "boom", 0.18 + size * 0.04, {"size": size * 0.6, "light": light})
	burst("fire", pos + Vector3(0, size * 0.3, 0), size)
	burst("sparks", pos + Vector3(0, size * 0.3, 0), size)
	burst("smoke", pos + Vector3(0, size * 0.6, 0), size)
	if pos.y < 1.5:
		burst("dust", pos + Vector3(0, 0.3, 0), size)
	var ring := Visuals.disc(1.0, Color(1.0, 0.85, 0.5, 0.5))
	ring.material_override = _own_mat(Color(1.0, 0.85, 0.5, 0.5))
	ring.position = pos + Vector3(0, 0.15, 0)
	_add(ring, "ring", 0.35 + size * 0.06, {"size": size * 1.2})
	var nd := 2 + int(size * 3.0)
	for i in range(mini(nd, 18)):
		var chunk := Visuals.box(Vector3(0.25, 0.25, 0.25) * (0.6 + randf() * size * 0.4), Color(0.12, 0.1, 0.09))
		chunk.position = pos + Vector3(0, 0.5, 0)
		var v := Vector3(randf_range(-1, 1), randf_range(1.2, 2.4), randf_range(-1, 1)) * (4.0 + size * 3.0)
		_add(chunk, "debris", 0.9 + randf() * 0.7, {"vel": v, "spin": Vector3(randf(), randf(), randf()) * 8.0})
	if size >= 3.0:
		var scorch := Visuals.disc(size * 0.9, Color(0.08, 0.06, 0.04, 0.45))
		scorch.position = pos + Vector3(0, 0.05, 0)
		_add(scorch, "track", 40.0)
		var dust := Visuals.ring(1.0, Color(0.6, 0.5, 0.35, 0.5), size * 0.8)
		dust.material_override = _own_mat(Color(0.6, 0.5, 0.35, 0.5))
		dust.position = pos + Vector3(0, 0.6, 0)
		_add(dust, "ring", 1.0, {"size": size * 1.6})
		# a second, slower column of smoke for the big ones
		burst("smoke", pos + Vector3(0, size, 0), size * 1.5)

## Supply drop: a cargo plane crosses over the drop zone and a crate parachutes
## down onto it. The sim credits the cash when the crate lands (6 s).
func supply_drop(pos: Vector3, team: int) -> void:
	var plane := Units.cargo_plane(team)
	var dir := Vector3(cos(randf() * TAU), 0, 0).normalized()
	if dir.length() < 0.1:
		dir = Vector3(1, 0, 0)
	var from := pos - dir * 190.0 + Vector3(0, 38, 0)
	var to := pos + dir * 190.0 + Vector3(0, 38, 0)
	plane.position = from
	plane.rotation.y = atan2(dir.x, dir.z)
	_add(plane, "jet", 7.2, {"from": from, "to": to, "props": plane.find_children("Propeller*", "Node3D", false, false)})
	_later(3.3, func() -> void:
		var crate := Units.supply_crate()
		crate.position = pos + Vector3(0, 36, 0)
		_add(crate, "para", 2.7, {"from": crate.position, "to": pos + Vector3(0, 0.2, 0)})
		Audio.I.sfx("plane_pass", pos + Vector3(0, 30, 0), 2.0, 0.0, 0.5))
	_later(6.0, func() -> void:
		var crate2 := Units.supply_crate()
		var ch := crate2.find_child("Chute", false, false)
		if ch != null:
			ch.visible = false
		crate2.position = pos + Vector3(0, 0.2, 0)
		_add(crate2, "track", 12.0)
		burst("dust", pos, 0.6))

## Ground target marker for an incoming strike (ring + rotating ticks + countdown pulse).
func strike_marker(pos: Vector3, seconds: float, col: Color) -> void:
	var n := Node3D.new()
	n.position = pos + Vector3(0, 0.25, 0)
	var r1 := Visuals.ring(7.0, col, 0.35)
	r1.material_override = _own_mat(col)
	n.add_child(r1)
	var r2 := Visuals.ring(2.5, col, 0.25)
	r2.material_override = _own_mat(col)
	r2.name = "Inner"
	n.add_child(r2)
	for i in range(4):
		var tick := Visuals.box(Vector3(0.4, 0.1, 3.0), col, true)
		tick.material_override = _own_mat(col)
		tick.position = Vector3(sin(i * PI * 0.5) * 8.5, 0, cos(i * PI * 0.5) * 8.5)
		tick.rotation.y = i * PI * 0.5
		n.add_child(tick)
	_add(n, "marker", seconds)

## A bomb falling from an aircraft onto pos (visual only; the sim's hit does the damage).
func bomb_drop(from: Vector3, pos: Vector3, seconds: float) -> void:
	var b := Visuals.box(Vector3(0.7, 0.7, 2.6), Color(0.25, 0.27, 0.3))
	b.position = from
	b.look_at_from_position(from, pos, Vector3.UP)
	_add(b, "bomb", seconds, {"from": from, "to": pos})

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

## Particle cannon: one continuous beam per firing cannon (kept alive by the sim's
## 4 Hz ticks and slid toward the newest target point), plus the uplink from the
## cannon spire into the sky and a ground-level scorch / explosion.
var pbeams: Dictionary = {}   # owner -> {node, core, up, target, t}
func particle_beam(pos: Vector3, owner: int, spire: Vector3) -> void:
	var key := owner
	if not pbeams.has(key):
		var outer := _beam_mesh(pos + Vector3(0, 160, 0), pos, Color(0.55, 0.85, 1.0, 0.55), 2.4)
		var core := _beam_mesh(pos + Vector3(0, 160, 0), pos, Color(1.0, 1.0, 1.0, 1.0), 0.7)
		add_child(outer)
		add_child(core)
		var up: Node3D = null
		if spire.x >= 0.0:
			up = _beam_mesh(spire, spire + Vector3(0, 160, 0), Color(0.55, 0.85, 1.0, 0.7), 1.2)
			add_child(up)
		pbeams[key] = {"outer": outer, "core": core, "up": up, "target": pos, "pos": pos, "t": 0.0, "life": 0.7}
	var pb: Dictionary = pbeams[key]
	pb["target"] = pos
	pb["life"] = 0.7
	explosion(pos, 1.6)
	var scorch := Visuals.disc(4.0, Color(0.05, 0.03, 0.02, 0.6))
	scorch.position = pos + Vector3(0, 0.06, 0)
	_add(scorch, "track", 40.0)

func _tick_pbeams(dt: float) -> void:
	if pbeams.is_empty():
		return
	var gone := []
	for key in pbeams:
		var pb: Dictionary = pbeams[key]
		pb["life"] -= dt
		pb["t"] += dt
		if pb["life"] <= 0.0:
			for k in ["outer", "core", "up"]:
				if pb[k] != null:
					pb[k].queue_free()
			gone.append(key)
			continue
		var p: Vector3 = (pb["pos"] as Vector3).move_toward(pb["target"], 12.0 * dt)
		pb["pos"] = p
		var top := p + Vector3(0, 160, 0)
		for k in ["outer", "core"]:
			var n: Node3D = pb[k]
			n.position = top
			n.look_at(p, Vector3.UP)
			var w := (2.4 if k == "outer" else 0.7) * (0.85 + 0.15 * sin(pb["t"] * 40.0))
			n.get_child(0).scale = Vector3(w / (2.4 if k == "outer" else 0.7), w / (2.4 if k == "outer" else 0.7), 1.0)
	for key in gone:
		pbeams.erase(key)

func strike(kind: String, pos: Vector3, heading: float, level: int) -> void:
	match kind:
		"a10":
			strike_marker(pos, 4.0, Color(1.0, 0.8, 0.2, 0.9))
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
			strike_marker(pos, 6.0, Color(0.4, 0.9, 1.0, 0.8))
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
			strike_marker(pos, 5.5, Color(1.0, 0.4, 0.2, 0.9))
			var plane := Visuals.make_model("aurora", -1)
			plane.scale = Vector3.ONE * 1.4
			var from := pos + Vector3(0, 45, -200)
			var to := pos + Vector3(0, 45, 200)
			plane.look_at_from_position(from, to, Vector3.UP)
			plane.rotate_y(PI)
			_add(plane, "jet", 8.0, {"from": from, "to": to})
			_later(3.9, func() -> void:
				bomb_drop(pos + Vector3(0, 44, -5), pos, 1.6)
				Audio.I.sfx("bomb_whistle", pos + Vector3(0, 20, 0), 2.0, 0.0, 0.5))
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

## Team beacon: a tall pulsing pillar visible to allies for a while.
func beacon(pos: Vector3, col: Color) -> void:
	var n := Node3D.new()
	n.position = pos
	var pillar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 1.4
	cm.height = 40.0
	pillar.mesh = cm
	pillar.material_override = _own_mat(Color(col.r, col.g, col.b, 0.35))
	pillar.position.y = 20.0
	pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(pillar)
	var ring := Visuals.ring(6.0, Color(col.r, col.g, col.b, 0.8), 0.6)
	ring.material_override = _own_mat(Color(col.r, col.g, col.b, 0.8))
	ring.position.y = 0.3
	n.add_child(ring)
	_add(n, "beacon", 25.0)

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

func placed(pos: Vector3, fp: Vector2, yaw := 0.0) -> void:
	var ring := Visuals.box(Vector3(fp.x, 0.1, fp.y), Color(0.3, 1.0, 0.4, 0.5), true)
	ring.position = pos + Vector3(0, 0.2, 0)
	ring.rotation.y = yaw
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
