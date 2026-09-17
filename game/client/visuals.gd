class_name Visuals
extends RefCounted
## Model loading with Synty prefab lookup and primitive fallbacks. Everything is
## fitted to the simulation's footprint / length so gameplay never depends on art.

static var _cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var missing_assets := false

static func prefab(rel: String) -> PackedScene:
	if rel == "":
		return null
	if _cache.has(rel):
		return _cache[rel]
	var path := Data.PREFAB + rel
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path)
	else:
		missing_assets = true
	_cache[rel] = ps
	return ps

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
			if keys.has("composite_armor"):
				# side skirts and extra front plate
				var w := aabb.size.x
				var l := aabb.size.z
				for sx in [-1.0, 1.0]:
					Buildings.box(root, Vector3(0.18, 0.7, l * 0.75), Vector3(c.x + sx * (w * 0.5 + 0.05), aabb.position.y + 0.75, c.z), metal)
				Buildings.box(root, Vector3(w * 0.8, 0.5, 0.2), Vector3(c.x, aabb.position.y + 0.9, c.z + l * 0.5), metal)
				any = true
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
	var ps := prefab(def.get("model", ""))
	if ps != null:
		var inst := ps.instantiate()
		strip_physics(inst)
		var holder := Node3D.new()
		holder.name = "Mesh"
		holder.add_child(inst)
		root.add_child(holder)
		var aabb := local_aabb(inst)
		var size := aabb.size
		var s := 1.0
		if def.get("cat", "") == "inf":
			s = float(def.get("length", 1.8)) / maxf(size.y, 0.01)   # infantry: fit by height
		else:
			var l := float(def.get("length", 4.0))
			s = l / maxf(maxf(size.x, size.z), 0.01)
		holder.scale = Vector3.ONE * s
		var center := aabb.get_center()
		holder.position = Vector3(-center.x * s, -aabb.position.y * s, -center.z * s)
		_setup_turret(root, inst)
	else:
		root.add_child(_fallback(type, owner))
	if def.get("builder", false):
		Buildings.dozer_kit(root, owner, float(def.get("length", 4.4)))
	return root

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
	var ps := prefab(rel)
	if ps != null:
		var inst := ps.instantiate()
		strip_physics(inst)
		var pivot := Node3D.new()
		pivot.rotation.y = yaw
		pivot.add_child(inst)
		var aabb := local_aabb(pivot)
		var s := 1.0
		if fp != Vector2i.ZERO:
			var w := fp.x * 2.0
			var h := fp.y * 2.0
			s = minf(w / maxf(aabb.size.x, 0.01), h / maxf(aabb.size.z, 0.01))
			if kind == "tree":
				s = clampf(s * 1.6, 0.6, 2.5)
			elif kind == "rock":
				s = s * 1.0
			elif kind == "mountain":
				s = s * 1.0
		var holder := Node3D.new()
		holder.scale = Vector3(s, s * (0.65 if kind == "mountain" else 1.0), s)
		var c := aabb.get_center()
		holder.position = Vector3(-c.x * s, -aabb.position.y * s * (0.65 if kind == "mountain" else 1.0), -c.z * s)
		holder.add_child(pivot)
		root.add_child(holder)
	elif fp != Vector2i.ZERO:
		var col := Color(0.45, 0.42, 0.38)
		if kind == "tree":
			col = Color(0.2, 0.45, 0.2)
		elif kind == "mountain":
			col = Color(0.5, 0.42, 0.35)
		var hgt := 3.0 + fp.x * 0.5 if kind != "mountain" else 6.0 + fp.x * 0.6
		var mi := box(Vector3(fp.x * 2.0 * 0.95, hgt, fp.y * 2.0 * 0.95), col)
		mi.position.y = hgt * 0.5
		root.add_child(mi)
	else:
		root.rotation.y = yaw
	return root

## Bounding box of a model in its own space (used for click picking and icons).
static func model_aabb(model: Node3D) -> AABB:
	return local_aabb(model)

## Wreck for a destroyed unit, or a generic rubble block for a building.
static func make_wreck(type: String) -> Node3D:
	var def := Data.def(type)
	var root := Node3D.new()
	var rel: String = def.get("wreck", "")
	if rel == "" and Data.is_building(type):
		var m: String = def.get("model", "")
		var guess := m.replace(".tscn", "_Destroyed_01.tscn")
		if ResourceLoader.exists(Data.PREFAB + guess):
			rel = guess
		else:
			guess = m.replace("_01.tscn", "_Destroyed_01.tscn")
			if ResourceLoader.exists(Data.PREFAB + guess):
				rel = guess
	if not Data.is_building(type):
		# charred, squashed copy of our own model
		var m := Units.make(type, -1)
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = flat_mat(Color(0.12, 0.11, 0.1), false)
		m.scale = Vector3(1.05, 0.55, 1.05)
		m.rotation.z = 0.12
		root.add_child(m)
		return root
	var ps := prefab(rel)
	if ps != null:
		var inst := ps.instantiate()
		strip_physics(inst)
		var aabb := local_aabb(inst)
		var s := 1.0
		if Data.is_building(type):
			var fp: Vector2 = Data.footprint_size(type)
			s = minf(fp.x * 0.9 / maxf(aabb.size.x, 0.01), fp.y * 0.9 / maxf(aabb.size.z, 0.01))
		else:
			s = float(def.get("length", 4.0)) / maxf(maxf(aabb.size.x, aabb.size.z), 0.01)
		inst.scale = Vector3.ONE * s
		var c := aabb.get_center()
		inst.position = Vector3(-c.x * s, -aabb.position.y * s, -c.z * s)
		root.add_child(inst)
	else:
		var sz := Data.footprint_size(type) if Data.is_building(type) else Vector2.ONE * float(def.get("length", 4.0)) * 0.6
		var mi := box(Vector3(sz.x * 0.7, 0.8, sz.y * 0.7), Color(0.15, 0.13, 0.12))
		mi.position.y = 0.4
		root.add_child(mi)
	return root
