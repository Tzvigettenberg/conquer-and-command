class_name Visuals
extends RefCounted
## All models are our own procedural low-poly pieces (Units / Buildings), fitted to the
## simulation's footprint / length so gameplay never depends on art.

static var _mat_cache: Dictionary = {}
static func team_mat(owner: int, alpha := 1.0) -> StandardMaterial3D:
	var key := "%d_%.2f" % [owner, alpha]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	var c: Color = Data.TEAM_COLORS[owner] if owner >= 0 and owner < Data.TEAM_COLORS.size() else Color(0.7, 0.7, 0.6)
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if alpha < 1.0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mat_cache[key] = m
	return m

static func flat_mat(c: Color, unshaded := true) -> StandardMaterial3D:
	var key := "c_%s_%s" % [c.to_html(), str(unshaded)]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cache[key] = m
	return m

## Recursively compute the AABB of all meshes under n, in n's local space.
static func local_aabb(n: Node, xf: Transform3D = Transform3D.IDENTITY, acc: Array = []) -> AABB:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and n.visible:
		var a: AABB = (n as MeshInstance3D).mesh.get_aabb()
		var out := AABB()
		var first := true
		for i in range(8):
			var p := t * a.get_endpoint(i)
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
		acc.append(out)
	for c in n.get_children():
		if c is Node3D and not c.visible:
			continue
		local_aabb(c, t, acc)
	if acc.is_empty():
		return AABB(Vector3.ZERO, Vector3.ONE)
	var total: AABB = acc[0]
	for i in range(1, acc.size()):
		total = total.merge(acc[i])
	return total

static func strip_physics(root: Node) -> void:
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "", true, false))
	for n in nodes:
		if n is CollisionObject3D:
			n.collision_layer = 0
			n.collision_mask = 0
		if n is CollisionShape3D or n is CollisionPolygon3D:
			n.set_deferred("disabled", true)
		if n is CharacterBody3D or n is RigidBody3D:
			n.set_physics_process(false)

## Build the visual for a sim entity type. Returns a Node3D whose origin is the
## Build the visual for a sim entity type. Returns a Node3D whose origin is the
## entity's ground position, facing +Z.
## Add-on parts for upgrades (see Puppet.set_extras). Returns null when nothing applies.
static func make_extras(type: String, keys: Array, team: int, aabb: AABB) -> Node3D:
	var root := Node3D.new()
	root.name = "Extras"
	var top := aabb.end.y
	var c := aabb.get_center()
	var tc: Color = Data.TEAM_COLORS[team % Data.TEAM_COLORS.size()] if team >= 0 else Color(0.6, 0.6, 0.6)
	var any := false
	var metal := Color(0.24, 0.25, 0.28)
	match type:
		"humvee":
			if keys.has("tow"):
				# TOW launcher box on the roof
				Buildings.box(root, Vector3(0.9, 0.45, 1.3), Vector3(c.x, top + 0.2, c.z - 0.2), metal)
				Buildings.cyl(root, 0.12, 0.12, 1.1, Vector3(c.x, top + 0.25, c.z + 0.5), Color(0.5, 0.5, 0.55), 6).rotation.x = PI * 0.5
				any = true
		"crusader", "paladin":
			pass   # composite armour is a stat-only upgrade (no bolt-on visual)
		"comanche":
			if keys.has("rocket_pods"):
				for sx in [-1.0, 1.0]:
					Buildings.cyl(root, 0.28, 0.28, 1.4, Vector3(c.x + sx * 1.1, c.y - 0.2, c.z), metal, 8).rotation.x = PI * 0.5
				any = true
		"raptor", "stealth_fighter":
			if keys.has("laser_missiles"):
				for sx in [-1.0, 1.0]:
					var tip := Buildings.sphere(root, 0.22, Vector3(c.x + sx * aabb.size.x * 0.32, c.y - 0.3, c.z + 0.6), Color(0.4, 0.8, 1.0))
					(tip.material_override as StandardMaterial3D).emission_enabled = true
					(tip.material_override as StandardMaterial3D).emission = Color(0.3, 0.7, 1.0)
				any = true
		"power_plant":
			pass   # control rods: the reactor steam turns blue (see Puppet.set_extras)
		"supply_center":
			if keys.has("supply_lines"):
				for i in range(3):
					Buildings.box(root, Vector3(1.0, 1.0, 1.0), Vector3(1.0 + i * 1.15, 0.65, -3.8), Color(0.85, 0.7, 0.3))
				any = true
		"barracks":
			if keys.has("capture"):
				Buildings.box(root, Vector3(0.1, 4.5, 0.1), Vector3(aabb.position.x + 0.6, 2.25, aabb.end.z - 0.6), metal)
				Buildings.box(root, Vector3(1.4, 0.8, 0.05), Vector3(aabb.position.x + 1.3, 4.0, aabb.end.z - 0.6), tc)
				any = true
		"china_nuke", "scud_storm":
			if keys.has("sw_ready"):
				# armed: red (nuke) / green (scud) warning beacons pulse on the pad corners
				var col := Color(1.0, 0.25, 0.15) if type == "china_nuke" else Color(0.4, 1.0, 0.3)
				for i in range(4):
					var lamp := Buildings.sphere(root, 0.45, Vector3(-4.0 + (i % 2) * 8.0, 2.4, -4.0 + (i / 2) * 8.0), col)
					(lamp.material_override as StandardMaterial3D).emission_enabled = true
					(lamp.material_override as StandardMaterial3D).emission = col
					(lamp.material_override as StandardMaterial3D).emission_energy_multiplier = 2.0
				any = true
		"particle_cannon":
			if keys.has("sw_ready"):
				# charged: a glowing orb on the spire and a halo
				var orb := Buildings.sphere(root, 1.1, Vector3(-2.0, 11.0, 0), Color(0.6, 0.9, 1.0))
				(orb.material_override as StandardMaterial3D).emission_enabled = true
				(orb.material_override as StandardMaterial3D).emission = Color(0.4, 0.8, 1.0)
				(orb.material_override as StandardMaterial3D).emission_energy_multiplier = 2.0
				var halo := Visuals.ring(2.6, Color(0.5, 0.85, 1.0, 0.5), 0.3)
				halo.position = Vector3(-2.0, 11.0, 0)
				root.add_child(halo)
				any = true
		"strategy_center":
			if keys.has("advanced_training"):
				Buildings.box(root, Vector3(1.6, 0.9, 0.05), Vector3(-1.5, 4.7, 2.6), Color(0.9, 0.75, 0.2))
				any = true
	if not any:
		root.free()
		return null
	return root

static func make_model(type: String, owner: int) -> Node3D:
	if type == "a10":
		return Units.a10(owner)
	var def := Data.def(type)
	var is_bld := Data.is_building(type)
	if is_bld:
		# structures are procedural (sized to the footprint, painted with team colour)
		return Buildings.make(type, owner)
	# units are our own blocky models (see Units)
	if def.get("cat", "") in ["inf", "veh", "air"] or def.get("builder", false):
		return Units.make(type, owner)
	var root := Node3D.new()
	root.name = "Model"
	root.add_child(_fallback(type, owner))
	if def.get("builder", false):
		Buildings.dozer_kit(root, owner, float(def.get("length", 4.4)))
	return root

## Boulder cluster filling an axis-aligned footprint (w x d cells of 2 m).
static func _rock(root: Node3D, fp: Vector2i, seed_yaw: float) -> void:
	var w := fp.x * 2.0 - 0.6
	var d := fp.y * 2.0 - 0.6
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_yaw * 1000.0) + fp.x * 31 + fp.y * 7
	var base := Color(0.45, 0.4, 0.34)
	var n := 3 + rng.randi() % 3
	for i in range(n):
		var sx := rng.randf_range(0.35, 0.7) * w
		var sz := rng.randf_range(0.35, 0.7) * d
		var sy := rng.randf_range(1.6, 2.6 + minf(w, d) * 0.35)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 7
		sm.rings = 4
		mi.mesh = sm
		mi.scale = Vector3(sx, sy, sz)
		mi.position = Vector3(rng.randf_range(-(w - sx) * 0.5, (w - sx) * 0.5), sy * 0.35, rng.randf_range(-(d - sz) * 0.5, (d - sz) * 0.5))
		mi.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2))
		mi.material_override = flat_mat(base.lightened(rng.randf_range(-0.12, 0.12)), false)
		root.add_child(mi)
	# a few pebbles around the base instead of a slab
	for i in range(4):
		var pb := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.5
		pm.height = 1.0
		pm.radial_segments = 6
		pm.rings = 3
		pb.mesh = pm
		pb.scale = Vector3(rng.randf_range(0.4, 0.9), rng.randf_range(0.25, 0.5), rng.randf_range(0.4, 0.9))
		pb.position = Vector3(rng.randf_range(-w * 0.55, w * 0.55), 0.1, rng.randf_range(-d * 0.55, d * 0.55))
		pb.material_override = flat_mat(base.lightened(rng.randf_range(-0.1, 0.15)), false)
		root.add_child(pb)

## Blocky tree in one cell: trunk + two or three canopy blocks (cactus in the desert).
static func _tree(root: Node3D, yaw: float, rel: String) -> void:
	root.rotation.y = yaw
	var rng := RandomNumberGenerator.new()
	rng.seed = int(yaw * 1000.0)
	if "Cactus" in rel:
		var g := Color(0.3, 0.5, 0.25)
		var trunk := box(Vector3(0.5, 3.0 + rng.randf() * 1.5, 0.5), g)
		trunk.position.y = trunk.mesh.size.y * 0.5
		root.add_child(trunk)
		for sx in [-1.0, 1.0]:
			var arm := box(Vector3(0.4, 1.4, 0.4), g)
			arm.position = Vector3(sx * 0.7, 2.0 + rng.randf(), 0)
			root.add_child(arm)
			var stub := box(Vector3(0.95, 0.4, 0.4), g)
			stub.position = Vector3(sx * 0.45, arm.position.y - 0.5, 0)
			root.add_child(stub)
		return
	var h := 2.2 + rng.randf() * 1.6
	var trunk := box(Vector3(0.5, h, 0.5), Color(0.4, 0.28, 0.18))
	trunk.position.y = h * 0.5
	root.add_child(trunk)
	var green := Color(0.2, 0.45, 0.2).lightened(rng.randf_range(-0.08, 0.1))
	if "Snow" in rel or "Big" in rel:
		green = Color(0.18, 0.35, 0.22)
	var layers := 2 + rng.randi() % 2
	for i in range(layers):
		var sz := 2.2 - i * 0.55
		var c := box(Vector3(sz, 1.1, sz), green.lightened(i * 0.06))
		c.position.y = h + 0.4 + i * 0.85
		c.rotation.y = i * 0.6
		root.add_child(c)

## Small ground decoration (no blocking): a low sand mound, a flat rock or a bush clump.
static func _deco(root: Node3D, yaw: float, rel: String) -> void:
	root.rotation.y = yaw
	var rng := RandomNumberGenerator.new()
	rng.seed = int(yaw * 1000.0)
	if "Dunes" in rel:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		sm.radial_segments = 8
		sm.rings = 4
		mi.mesh = sm
		mi.scale = Vector3(rng.randf_range(4.0, 7.0), 0.7, rng.randf_range(2.5, 4.0))
		mi.position.y = -0.1
		mi.material_override = flat_mat(Color(0.6, 0.55, 0.42), false)
		root.add_child(mi)
	elif "Rock" in rel:
		for i in range(2 + rng.randi() % 3):
			var r := box(Vector3(rng.randf_range(0.5, 1.2), 0.35, rng.randf_range(0.5, 1.2)), Color(0.45, 0.45, 0.48))
			r.position = Vector3(rng.randf_range(-1.5, 1.5), 0.15, rng.randf_range(-1.5, 1.5))
			r.rotation.y = rng.randf() * TAU
			root.add_child(r)
	else:
		for i in range(3 + rng.randi() % 3):
			var b := box(Vector3(0.9, 0.7, 0.9), Color(0.22, 0.4, 0.2).lightened(rng.randf() * 0.1))
			b.position = Vector3(rng.randf_range(-1.4, 1.4), 0.35, rng.randf_range(-1.4, 1.4))
			b.rotation.y = rng.randf() * TAU
			root.add_child(b)

## Ruined house: broken walls, rubble and a fallen roof piece, inside its footprint.
static func _ruin(root: Node3D, fp: Vector2i, yaw: float) -> void:
	var w := fp.x * 2.0 - 0.8
	var d := fp.y * 2.0 - 0.8
	var rng := RandomNumberGenerator.new()
	rng.seed = int(yaw * 100.0) + fp.x * 13 + fp.y
	var wall := Color(0.62, 0.58, 0.5)
	var floor_slab := box(Vector3(w, 0.2, d), Color(0.5, 0.47, 0.42))
	floor_slab.position.y = 0.1
	root.add_child(floor_slab)
	# walls of different heights, one side collapsed
	var heights := [rng.randf_range(2.0, 3.2), rng.randf_range(0.6, 1.4), rng.randf_range(1.6, 2.8), rng.randf_range(0.4, 1.0)]
	var sides := [Vector3(0, 0, -d * 0.5 + 0.15), Vector3(w * 0.5 - 0.15, 0, 0), Vector3(0, 0, d * 0.5 - 0.15), Vector3(-w * 0.5 + 0.15, 0, 0)]
	for i in range(4):
		var h: float = heights[i]
		var sz := Vector3(w, h, 0.3) if i % 2 == 0 else Vector3(0.3, h, d)
		var wl := box(sz, wall.darkened(rng.randf() * 0.15))
		wl.position = sides[i] + Vector3(0, h * 0.5 + 0.2, 0)
		root.add_child(wl)
		if h > 1.8:
			var win := box(Vector3(0.9, 0.9, 0.34) if i % 2 == 0 else Vector3(0.34, 0.9, 0.9), Color(0.1, 0.1, 0.12))
			win.position = sides[i] + Vector3(0, 1.4, 0)
			root.add_child(win)
	for i in range(5):
		var r := box(Vector3(rng.randf_range(0.4, 0.9), 0.4, rng.randf_range(0.4, 0.9)), wall.darkened(0.25))
		r.position = Vector3(rng.randf_range(-w * 0.4, w * 0.4), 0.4, rng.randf_range(-d * 0.4, d * 0.4))
		r.rotation.y = rng.randf() * TAU
		root.add_child(r)
	var roof := box(Vector3(w * 0.6, 0.15, d * 0.5), Color(0.35, 0.25, 0.18))
	roof.position = Vector3(w * 0.1, 0.8, d * 0.1)
	roof.rotation = Vector3(0.35, 0.3, 0.2)
	root.add_child(roof)

## Subtle team tint over every mesh of a unit so ownership reads at a glance.
static func tint_unit(model: Node3D, owner: int) -> void:
	if owner < 0:
		return
	var c: Color = Data.TEAM_COLORS[owner]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, 0.22)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_overlay == null:
			(mi as MeshInstance3D).material_overlay = m

static func _fallback(type: String, owner: int) -> Node3D:
	var def := Data.def(type)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	if Data.is_building(type):
		var fp: Vector2 = Data.footprint_size(type)
		var h := float(def.get("height", 6.0)) * 0.6
		var box := BoxMesh.new()
		box.size = Vector3(fp.x * 0.9, h, fp.y * 0.9)
		mi.mesh = box
		mi.position.y = h * 0.5
		mi.material_override = team_mat(owner) if owner >= 0 else flat_mat(Color(0.55, 0.5, 0.45), false)
	elif def.get("cat", "") == "inf":
		var cap := CapsuleMesh.new()
		cap.radius = 0.35
		cap.height = 1.8
		mi.mesh = cap
		mi.position.y = 0.9
		mi.material_override = team_mat(owner)
	else:
		var l := float(def.get("length", 4.0))
		var box := BoxMesh.new()
		box.size = Vector3(l * 0.5, l * 0.3, l)
		mi.mesh = box
		mi.position.y = l * 0.15
		mi.material_override = team_mat(owner)
		var nose := MeshInstance3D.new()
		var nb := BoxMesh.new()
		nb.size = Vector3(l * 0.2, l * 0.2, l * 0.4)
		nose.mesh = nb
		nose.position = Vector3(0, l * 0.35, l * 0.2)
		nose.material_override = flat_mat(Color(0.2, 0.2, 0.2), false)
		mi.add_child(nose)
	return mi

## Synty vehicle prefabs nest barrel/hatch meshes under the turret mesh, so the
## turret node itself is the pivot.
static func _setup_turret(root: Node3D, inst: Node) -> void:
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		if ("Turret" in n.name and not ("Barrel" in n.name or "Hatch" in n.name)) or n.name.ends_with("Gun_Horizontal") or n.name.ends_with("Remote_Weapon") or n.name.ends_with("Gunner"):
			root.set_meta("turret", n)
			return

static func ring(radius: float, color: Color, thickness := 0.18) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = maxf(0.05, radius - thickness)
	t.outer_radius = radius
	t.rings = 24
	t.ring_segments = 6
	mi.mesh = t
	mi.material_override = flat_mat(color)
	mi.position.y = 0.08
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func disc(radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 0.04
	c.radial_segments = 20
	mi.mesh = c
	mi.material_override = flat_mat(color)
	mi.position.y = 0.03
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func box(size: Vector3, color: Color, unshaded := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = flat_mat(color, unshaded)
	return mi

static func sphere(r: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	mi.mesh = s
	mi.material_override = flat_mat(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Generic prefab instance for map props (rocks, trees, ruins), fitted to a footprint.
## The model is rotated first and then fitted, so the art covers the blocked cells.
static func make_prop(rel: String, fp: Vector2i, yaw: float, kind: String) -> Node3D:
	var root := Node3D.new()
	# rocks and trees are our own blocky props, sized exactly to the cells they block
	if kind == "rock" and fp != Vector2i.ZERO:
		_rock(root, fp, yaw)
		return root
	if kind == "tree":
		_tree(root, yaw, rel)
		return root
	if kind == "deco":
		_deco(root, yaw, rel)
		return root
	if kind == "ruin" and fp != Vector2i.ZERO:
		_ruin(root, fp, yaw)
		return root
	_deco(root, yaw, rel)
	return root

## Bounding box of a model in its own space (used for click picking and icons).
static func model_aabb(model: Node3D) -> AABB:
	return local_aabb(model)

## Wreck for a destroyed unit, or a generic rubble block for a building.
static func make_wreck(type: String) -> Node3D:
	var def := Data.def(type)
	var root := Node3D.new()
	if not Data.is_building(type):
		# charred, squashed copy of our own model
		var m := Units.make(type, -1)
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = flat_mat(Color(0.12, 0.11, 0.1), false)
		m.scale = Vector3(1.05, 0.55, 1.05)
		m.rotation.z = 0.12
		root.add_child(m)
		return root
	# structure: burnt-out rubble sized to the footprint - broken wall stubs, slabs, a girder
	var fp: Vector2 = Data.footprint_size(type)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(type)
	var char := Color(0.16, 0.14, 0.13)
	var ash := Color(0.28, 0.26, 0.24)
	var hgt := minf(float(def.get("height", 6.0)) * 0.35, 3.5)
	for sx in [-1.0, 1.0]:
		var wall := box(Vector3(0.5, hgt * rng.randf_range(0.5, 1.0), fp.y * rng.randf_range(0.35, 0.7)), char)
		wall.position = Vector3(sx * fp.x * 0.42, wall.mesh.size.y * 0.5, rng.randf_range(-0.2, 0.2) * fp.y)
		root.add_child(wall)
		var wall2 := box(Vector3(fp.x * rng.randf_range(0.3, 0.6), hgt * rng.randf_range(0.3, 0.8), 0.5), ash)
		wall2.position = Vector3(rng.randf_range(-0.2, 0.2) * fp.x, wall2.mesh.size.y * 0.5, sx * fp.y * 0.42)
		root.add_child(wall2)
	for i in range(5):
		var slab := box(Vector3(rng.randf_range(1.0, 2.5), rng.randf_range(0.3, 0.8), rng.randf_range(1.0, 2.5)), ash if i % 2 == 0 else char)
		slab.position = Vector3(rng.randf_range(-0.35, 0.35) * fp.x, slab.mesh.size.y * 0.5, rng.randf_range(-0.35, 0.35) * fp.y)
		slab.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
		root.add_child(slab)
	var girder := box(Vector3(0.25, 0.25, minf(fp.x, fp.y) * 0.7), Color(0.3, 0.22, 0.16))
	girder.position = Vector3(0, 1.2, 0)
	girder.rotation = Vector3(0.5, 0.8, 0.3)
	root.add_child(girder)
	var floor := box(Vector3(fp.x * 0.95, 0.12, fp.y * 0.95), char)
	floor.position.y = 0.06
	root.add_child(floor)
	return root
