class_name Buildings
extends RefCounted
## Procedural low-poly structure models built from primitives, sized exactly to
## the sim footprints and painted with the owner's colour. Each model carries
## meta "anim": [{node, kind, speed}] for idle animation (radar spin, launcher
## sweep, gun traverse, pump-jack nod, steam).

const CONCRETE := Color(0.58, 0.57, 0.53)
# China: grey concrete, red trim, pagoda roofs
const CN_WALL := Color(0.52, 0.53, 0.5)
const CN_WALL_DARK := Color(0.38, 0.39, 0.37)
const CN_RED := Color(0.55, 0.15, 0.12)
# GLA: adobe, rust, tarps
const GLA_WALL := Color(0.72, 0.62, 0.44)
const GLA_WALL_DARK := Color(0.56, 0.47, 0.33)
const GLA_ROOF := Color(0.45, 0.36, 0.25)
const GLA_TARP := Color(0.35, 0.45, 0.3)
const GLA_PALACE := Color(0.8, 0.72, 0.55)
const GLA_UNIFORM := Color(0.5, 0.42, 0.3)
const CONCRETE_DARK := Color(0.42, 0.41, 0.39)
const METAL := Color(0.36, 0.38, 0.42)
const METAL_DARK := Color(0.22, 0.23, 0.26)
const ROOF := Color(0.3, 0.32, 0.33)
const GLASS := Color(0.35, 0.55, 0.75)
const WARN := Color(0.9, 0.75, 0.15)
const RUST := Color(0.5, 0.32, 0.2)

static func _m(c: Color) -> StandardMaterial3D:
	return Visuals.flat_mat(c, false)

static func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _m(c)
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	return mi

static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, c: Color, segs := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	mi.mesh = cm
	mi.material_override = _m(c)
	mi.position = pos
	parent.add_child(mi)
	return mi

static func sphere(parent: Node3D, r: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = _m(c)
	mi.position = pos
	parent.add_child(mi)
	return mi

static func prism(parent: Node3D, size: Vector3, pos: Vector3, c: Color, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = _m(c)
	mi.position = pos
	mi.rotation.y = yaw
	parent.add_child(mi)
	return mi

static func team_col(team: int) -> Color:
	if team >= 0 and team < Data.TEAM_COLORS.size():
		return Data.TEAM_COLORS[team]
	return Color(0.75, 0.72, 0.65)

static func anim(root: Node3D, node: Node3D, kind: String, speed := 1.0) -> void:
	var arr: Array = root.get_meta("anim", [])
	arr.append({"node": node, "kind": kind, "speed": speed})
	root.set_meta("anim", arr)

## Team-coloured stripe band around a box building.
static func band(parent: Node3D, w: float, d: float, y: float, team: int, thick := 0.5) -> void:
	var c := team_col(team)
	box(parent, Vector3(w + 0.1, thick, d + 0.1), Vector3(0, y, 0), c)

static func make(type: String, team: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var tc := team_col(team)
	match type:
		"command_center":
			# wide two-storey block, comms tower with a spinning radar, team banner
			box(root, Vector3(11.5, 3.0, 13.0), Vector3(0, 1.5, 0), CONCRETE)
			box(root, Vector3(8.0, 3.0, 8.0), Vector3(-1.0, 4.5, 1.5), CONCRETE_DARK)
			band(root, 11.5, 13.0, 3.1, team, 0.4)
			box(root, Vector3(8.2, 0.4, 8.2), Vector3(-1.0, 6.2, 1.5), ROOF)
			box(root, Vector3(3.0, 1.2, 6.0), Vector3(3.5, 3.6, -3.5), GLASS)
			cyl(root, 0.35, 0.5, 8.0, Vector3(4.0, 7.0, 4.5), METAL, 8)
			var dish := Node3D.new()
			dish.position = Vector3(4.0, 11.2, 4.5)
			root.add_child(dish)
			var d := cyl(dish, 1.6, 0.2, 0.5, Vector3(0, 0, 0), METAL, 16)
			d.rotation.x = 0.9
			anim(root, dish, "spin", 1.2)
			box(root, Vector3(0.12, 3.0, 0.12), Vector3(-4.8, 7.5, -5.5), METAL_DARK)
			box(root, Vector3(1.6, 1.0, 0.06), Vector3(-4.0, 8.3, -5.5), tc)
			for i in range(3):
				box(root, Vector3(0.6, 2.2, 0.6), Vector3(-4.5 + i * 1.6, 1.1, 6.0), METAL_DARK)
		"power_plant":
			# reactor dome, two cooling stacks with steam, transformer yard
			cyl(root, 2.2, 2.4, 2.4, Vector3(-0.8, 1.2, 0.6), CONCRETE, 16)
			sphere(root, 2.1, Vector3(-0.8, 2.6, 0.6), CONCRETE_DARK)
			band(root, 5.0, 5.0, 0.3, team, 0.3)
			for i in range(2):
				var st := cyl(root, 0.45, 0.6, 4.5, Vector3(1.9, 2.25, -1.4 + i * 2.4), METAL, 10)
				var steam := _steam(Vector3(1.9, 4.6, -1.4 + i * 2.4))
				root.add_child(steam)
			box(root, Vector3(2.0, 1.2, 2.2), Vector3(1.8, 0.6, 1.9), METAL_DARK)
			for i in range(3):
				cyl(root, 0.15, 0.15, 1.0, Vector3(1.2 + i * 0.6, 1.7, 1.9), WARN, 6)
			var glow := sphere(root, 0.5, Vector3(-0.8, 4.7, 0.6), tc)
			anim(root, glow, "pulse", 2.0)
		"barracks":
			# long low hall, sloped roof, flagpole, sandbag entrance
			box(root, Vector3(9.5, 2.4, 6.0), Vector3(0, 1.2, -1.2), CONCRETE)
			prism(root, Vector3(9.7, 1.6, 6.3), Vector3(0, 3.2, -1.2), ROOF)
			band(root, 9.5, 6.0, 2.3, team, 0.3)
			box(root, Vector3(3.5, 1.8, 2.5), Vector3(-2.5, 0.9, 3.0), CONCRETE_DARK)
			box(root, Vector3(3.6, 0.3, 2.7), Vector3(-2.5, 1.9, 3.0), ROOF)
			for i in range(4):
				box(root, Vector3(0.8, 0.5, 0.6), Vector3(1.0 + i * 0.9, 0.25, 3.8), Color(0.55, 0.5, 0.35))
			box(root, Vector3(0.1, 4.0, 0.1), Vector3(4.2, 2.0, 3.8), METAL_DARK)
			box(root, Vector3(1.4, 0.9, 0.05), Vector3(3.5, 3.5, 3.8), tc)
			for i in range(3):
				box(root, Vector3(1.0, 0.8, 0.1), Vector3(-3.0 + i * 3.0, 1.6, 1.85), GLASS)
		"supply_center":
			# drop-off apron with a big H, small warehouse, crane, fuel tanks
			box(root, Vector3(9.6, 0.15, 9.6), Vector3(0, 0.08, 0), CONCRETE_DARK)
			box(root, Vector3(5.5, 0.05, 1.0), Vector3(1.2, 0.17, 0), WARN)
			box(root, Vector3(1.0, 0.05, 4.5), Vector3(-1.0, 0.17, 0), WARN)
			box(root, Vector3(1.0, 0.05, 4.5), Vector3(3.4, 0.17, 0), WARN)
			box(root, Vector3(2.4, 3.0, 8.5), Vector3(-3.5, 1.5, 0), CONCRETE)
			box(root, Vector3(2.5, 0.25, 8.6), Vector3(-3.5, 3.1, 0), ROOF)
			band(root, 2.4, 8.5, 2.9, team, 0.3)
			for i in range(2):
				cyl(root, 0.8, 0.8, 1.8, Vector3(3.6, 0.9, -3.4 + i * 1.6), METAL, 10)
			box(root, Vector3(0.25, 5.0, 0.25), Vector3(3.8, 2.5, 3.5), METAL)
			var arm := box(root, Vector3(3.4, 0.22, 0.22), Vector3(1.8, 5.0, 3.5), METAL)
			arm.position = Vector3(3.8, 5.0, 3.5)
			var crane := Node3D.new()
			crane.position = Vector3(3.8, 5.0, 3.5)
			root.add_child(crane)
			arm.get_parent().remove_child(arm)
			crane.add_child(arm)
			arm.position = Vector3(-1.5, 0, 0)
			anim(root, crane, "sweep", 0.3)
		"war_factory":
			_war_factory(root, team, tc, CONCRETE, METAL_DARK)
		"airfield":
			_airfield(root, team, tc, WARN)
		"china_airfield":
			_airfield(root, team, tc, Color(0.85, 0.2, 0.15))
		"strategy_center":
			# bunker with antenna farm and a rotating command dish
			box(root, Vector3(11.5, 2.2, 9.5), Vector3(0, 1.1, 0), CONCRETE_DARK)
			box(root, Vector3(7.0, 2.0, 5.0), Vector3(-1.5, 3.2, 0), CONCRETE)
			band(root, 11.5, 9.5, 2.1, team, 0.35)
			box(root, Vector3(5.0, 0.8, 0.1), Vector3(-1.5, 3.4, 2.55), GLASS)
			for i in range(3):
				cyl(root, 0.06, 0.08, 4.0, Vector3(3.5 + i * 0.9, 4.2, -2.5), METAL, 6)
			var dish := Node3D.new()
			dish.position = Vector3(3.8, 4.8, 2.0)
			root.add_child(dish)
			var d := cyl(dish, 1.3, 0.2, 0.4, Vector3(0, 0.3, 0), METAL, 14)
			d.rotation.x = 1.1
			anim(root, dish, "spin", 0.6)
			# battle-plan cannon (Bombardment): a heavy howitzer on the roof, hidden until the plan is active
			var turret := Node3D.new()
			turret.name = "Turret"
			turret.position = Vector3(3.0, 2.2, -1.5)
			root.add_child(turret)
			var cannon := Node3D.new()
			cannon.name = "Cannon"
			cannon.visible = false
			turret.add_child(cannon)
			cyl(cannon, 1.1, 1.2, 0.7, Vector3(0, 0.35, 0), METAL, 12)
			box(cannon, Vector3(1.6, 1.0, 1.8), Vector3(0, 1.1, -0.2), METAL_DARK)
			var barrel := cyl(cannon, 0.16, 0.2, 4.2, Vector3(0, 1.4, 2.2), METAL_DARK, 8)
			barrel.rotation.x = deg_to_rad(90.0 - 18.0)
			box(cannon, Vector3(0.5, 0.3, 0.3), Vector3(0, 1.2, 1.0), tc)
			# Hold the Line: sandbag ring; Search and Destroy: extra scanner mast (toggled by the puppet)
			var bags := Node3D.new()
			bags.name = "PlanHold"
			bags.visible = false
			root.add_child(bags)
			for i in range(12):
				var ang := i * TAU / 12.0
				box(bags, Vector3(1.6, 0.7, 0.8), Vector3(sin(ang) * 6.6, 0.35, cos(ang) * 5.6), Color(0.55, 0.5, 0.36), ang)
			var mast := Node3D.new()
			mast.name = "PlanSearch"
			mast.visible = false
			root.add_child(mast)
			cyl(mast, 0.08, 0.1, 6.0, Vector3(-4.5, 5.0, -3.0), METAL, 6)
			var scan := Node3D.new()
			scan.position = Vector3(-4.5, 8.2, -3.0)
			mast.add_child(scan)
			box(scan, Vector3(2.2, 0.5, 0.1), Vector3(0, 0, 0), METAL)
			anim(root, scan, "spin", 2.5)
			root.set_meta("turret", turret)
			anim(root, turret, "sweep", 0.3)
		"supply_drop_zone":
			# marked landing square with a beacon mast
			box(root, Vector3(5.6, 0.12, 5.6), Vector3(0, 0.06, 0), CONCRETE_DARK)
			box(root, Vector3(4.0, 0.04, 0.5), Vector3(0, 0.15, 0), WARN)
			box(root, Vector3(0.5, 0.04, 4.0), Vector3(0, 0.15, 0), WARN)
			box(root, Vector3(0.15, 5.0, 0.15), Vector3(2.3, 2.5, -2.3), METAL)
			var beacon := sphere(root, 0.35, Vector3(2.3, 5.2, -2.3), tc)
			anim(root, beacon, "blink", 2.0)
			for i in range(4):
				box(root, Vector3(0.4, 0.4, 0.4), Vector3(-2.3 + (i % 2) * 4.6, 0.3, -2.3 + (i / 2) * 4.6), tc)
		"patriot":
			# concrete base, rotating launcher with four missile tubes
			box(root, Vector3(3.6, 0.8, 3.6), Vector3(0, 0.4, 0), CONCRETE_DARK)
			band(root, 3.6, 3.6, 0.75, team, 0.2)
			var turret := Node3D.new()
			turret.name = "Turret"
			turret.position = Vector3(0, 0.8, 0)
			root.add_child(turret)
			cyl(turret, 1.0, 1.1, 0.6, Vector3(0, 0.3, 0), METAL, 12)
			var tilt := Node3D.new()
			tilt.position = Vector3(0, 0.8, 0)
			tilt.rotation.x = -0.6
			turret.add_child(tilt)
			for i in range(4):
				box(tilt, Vector3(0.7, 0.7, 2.6), Vector3(-0.55 + (i % 2) * 1.1, 0.4 + (i / 2) * 0.8, 0.2), METAL_DARK)
				box(tilt, Vector3(0.5, 0.5, 0.1), Vector3(-0.55 + (i % 2) * 1.1, 0.4 + (i / 2) * 0.8, 1.55), tc)
			root.set_meta("turret", turret)
			anim(root, turret, "sweep", 0.4)
		"firebase":
			# sandbag ring with a big howitzer that traverses
			for i in range(12):
				var a := TAU * i / 12.0
				box(root, Vector3(1.4, 0.8, 0.7), Vector3(cos(a) * 2.6, 0.4, sin(a) * 2.6), Color(0.55, 0.5, 0.35), -a)
			box(root, Vector3(2.4, 0.3, 2.4), Vector3(0, 0.15, 0), CONCRETE_DARK)
			var turret := Node3D.new()
			turret.name = "Turret"
			turret.position = Vector3(0, 0.3, 0)
			root.add_child(turret)
			box(turret, Vector3(1.8, 0.9, 2.0), Vector3(0, 0.45, 0), METAL)
			box(turret, Vector3(0.4, 0.3, 0.05), Vector3(0, 1.0, -1.0), tc)
			var barrel := Node3D.new()
			barrel.position = Vector3(0, 0.9, 0.4)
			barrel.rotation.x = -0.35
			turret.add_child(barrel)
			cyl(barrel, 0.16, 0.22, 3.6, Vector3(0, 0, 1.8), METAL_DARK, 8).rotation.x = PI * 0.5
			root.set_meta("turret", turret)
			anim(root, turret, "sweep", 0.25)
		"particle_cannon":
			# heavy base, three focusing rings around a central spire, side dish
			box(root, Vector3(13.5, 1.6, 7.5), Vector3(0, 0.8, 0), CONCRETE_DARK)
			band(root, 13.5, 7.5, 1.55, team, 0.4)
			cyl(root, 0.5, 1.2, 9.0, Vector3(-2.0, 6.0, 0), METAL, 10)
			for i in range(3):
				var ring := Node3D.new()
				ring.position = Vector3(-2.0, 3.5 + i * 2.2, 0)
				root.add_child(ring)
				var t := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 1.6 - i * 0.3
				tm.outer_radius = 2.0 - i * 0.3
				tm.rings = 24
				tm.ring_segments = 8
				t.mesh = tm
				t.material_override = _m(tc if i == 1 else METAL_DARK)
				ring.add_child(t)
				anim(root, ring, "spin", 0.5 + i * 0.4)
			var top := sphere(root, 0.7, Vector3(-2.0, 10.8, 0), tc)
			anim(root, top, "pulse", 1.5)
			var dish := Node3D.new()
			dish.position = Vector3(4.0, 2.6, 0)
			root.add_child(dish)
			cyl(dish, 1.8, 0.2, 0.6, Vector3(0, 0.6, 0), METAL, 16).rotation.x = 0.7
			anim(root, dish, "spin", 0.3)
			for i in range(4):
				box(root, Vector3(1.0, 1.4, 1.0), Vector3(3.0 + (i % 2) * 2.5, 2.3, -2.5 + (i / 2) * 5.0), METAL_DARK)
		# ================= China =================
		"china_cc":
			# wide block with a red pagoda roof, comms mast with radar, red star banner
			box(root, Vector3(11.5, 3.0, 13.0), Vector3(0, 1.5, 0), CN_WALL)
			box(root, Vector3(8.5, 2.6, 8.5), Vector3(-1.0, 4.3, 1.5), CN_WALL_DARK)
			band(root, 11.5, 13.0, 3.1, team, 0.4)
			_pagoda(root, Vector3(-1.0, 5.6, 1.5), 9.5, 9.5, CN_RED)
			box(root, Vector3(3.0, 1.2, 6.0), Vector3(3.5, 3.6, -3.5), GLASS)
			cyl(root, 0.3, 0.45, 8.0, Vector3(4.2, 7.0, 4.5), METAL, 8)
			var dish := Node3D.new()
			dish.position = Vector3(4.2, 11.2, 4.5)
			root.add_child(dish)
			cyl(dish, 1.5, 0.2, 0.5, Vector3.ZERO, METAL, 16).rotation.x = 0.9
			anim(root, dish, "spin", 1.0)
			_star(root, Vector3(-1.0, 8.9, 1.5), 1.2)
			for i in range(3):
				box(root, Vector3(0.6, 2.2, 0.6), Vector3(-4.5 + i * 1.6, 1.1, 6.0), METAL_DARK)
			box(root, Vector3(0.12, 3.0, 0.12), Vector3(-4.8, 7.5, -5.5), METAL_DARK)
			box(root, Vector3(1.6, 1.0, 0.06), Vector3(-4.0, 8.3, -5.5), tc)
		"china_reactor":
			# squat reactor hall, cooling tower with steam, red warning band, glowing core
			box(root, Vector3(5.5, 3.0, 5.0), Vector3(-1.0, 1.5, 1.2), CN_WALL)
			band(root, 5.5, 5.0, 3.0, team, 0.3)
			cyl(root, 1.9, 2.6, 6.5, Vector3(1.8, 3.25, -1.6), CONCRETE, 16)
			cyl(root, 1.5, 1.9, 0.6, Vector3(1.8, 6.6, -1.6), CN_RED, 16)
			root.add_child(_steam(Vector3(1.8, 6.8, -1.6)))
			sphere(root, 1.6, Vector3(-1.0, 3.6, 1.2), CN_WALL_DARK)
			var core := sphere(root, 0.6, Vector3(-1.0, 4.9, 1.2), Color(0.5, 1.0, 0.4))
			anim(root, core, "pulse", 2.5)
			_star(root, Vector3(-1.0, 2.2, 3.71), 0.7)
			for i in range(3):
				cyl(root, 0.12, 0.12, 1.0, Vector3(-3.0 + i * 0.6, 1.5, -2.0), WARN, 6)
		"china_barracks":
			# long hall with a red tiled roof, drill yard with sandbags, flag
			box(root, Vector3(9.5, 2.4, 6.0), Vector3(0, 1.2, -1.2), CN_WALL)
			_pagoda(root, Vector3(0, 2.4, -1.2), 10.0, 6.4, CN_RED)
			band(root, 9.5, 6.0, 2.3, team, 0.3)
			box(root, Vector3(3.5, 1.8, 2.5), Vector3(-2.5, 0.9, 3.0), CN_WALL_DARK)
			box(root, Vector3(3.6, 0.3, 2.7), Vector3(-2.5, 1.9, 3.0), CN_RED)
			for i in range(4):
				box(root, Vector3(0.8, 0.5, 0.6), Vector3(1.0 + i * 0.9, 0.25, 3.8), Color(0.55, 0.5, 0.35))
			box(root, Vector3(0.1, 4.0, 0.1), Vector3(4.2, 2.0, 3.8), METAL_DARK)
			box(root, Vector3(1.4, 0.9, 0.05), Vector3(3.5, 3.5, 3.8), CN_RED)
			_star(root, Vector3(3.5, 3.5, 3.84), 0.35)
			for i in range(3):
				box(root, Vector3(1.0, 0.8, 0.1), Vector3(-3.0 + i * 3.0, 1.6, 1.85), GLASS)
		"china_supply":
			# truck apron with a loading ramp, crate stacks, warehouse with red roof
			box(root, Vector3(9.6, 0.15, 9.6), Vector3(0, 0.08, 0), CONCRETE_DARK)
			box(root, Vector3(4.5, 0.05, 5.5), Vector3(1.6, 0.17, 0), WARN)
			box(root, Vector3(3.8, 0.05, 4.8), Vector3(1.6, 0.18, 0), CONCRETE_DARK)
			box(root, Vector3(2.6, 3.0, 8.5), Vector3(-3.4, 1.5, 0), CN_WALL)
			_pagoda(root, Vector3(-3.4, 3.0, 0), 3.0, 8.9, CN_RED)
			band(root, 2.6, 8.5, 2.9, team, 0.3)
			for i in range(4):
				box(root, Vector3(1.1, 1.0, 1.1), Vector3(3.6 - (i % 2) * 1.2, 0.5 + (i / 2) * 1.0, -3.4), Color(0.7, 0.55, 0.3))
			box(root, Vector3(2.6, 0.2, 2.0), Vector3(1.6, 0.6, 3.6), METAL)
			box(root, Vector3(2.6, 0.5, 0.2), Vector3(1.6, 0.35, 2.6), METAL_DARK)
		"china_factory":
			_war_factory(root, team, tc, CN_WALL, CN_RED)
			_star(root, Vector3(0, 4.8, 5.85), 0.6)
		"propaganda_center":
			# hall with a giant loudspeaker cluster on a mast, red banners, antenna
			box(root, Vector3(9.5, 3.2, 9.5), Vector3(0, 1.6, 0), CN_WALL)
			_pagoda(root, Vector3(0, 3.2, 0), 10.0, 10.0, CN_RED)
			band(root, 9.5, 9.5, 3.1, team, 0.35)
			cyl(root, 0.18, 0.25, 8.0, Vector3(0, 8.0, 0), METAL, 8)
			var horns := Node3D.new()
			horns.position = Vector3(0, 11.0, 0)
			root.add_child(horns)
			for i in range(4):
				var a := i * PI * 0.5
				var h := cyl(horns, 0.9, 0.25, 1.4, Vector3(sin(a) * 0.9, 0, cos(a) * 0.9), METAL_DARK, 10)
				h.rotation = Vector3(PI * 0.5, a, 0)
			anim(root, horns, "spin", 0.4)
			for sx in [-1.0, 1.0]:
				box(root, Vector3(0.06, 2.6, 1.6), Vector3(sx * 4.78, 1.9, 2.0), CN_RED)
				_star(root, Vector3(sx * 4.82, 2.6, 2.0), 0.45, true)
			var pulse := sphere(root, 0.5, Vector3(0, 12.3, 0), CN_RED)
			anim(root, pulse, "pulse", 3.0)
		"speaker_tower":
			# lattice mast with four horns that slowly turn
			box(root, Vector3(1.8, 0.4, 1.8), Vector3(0, 0.2, 0), CONCRETE_DARK)
			band(root, 1.8, 1.8, 0.4, team, 0.15)
			cyl(root, 0.14, 0.22, 7.0, Vector3(0, 3.7, 0), METAL, 8)
			for i in range(3):
				box(root, Vector3(1.2, 0.06, 1.2), Vector3(0, 1.5 + i * 2.0, 0), METAL_DARK)
			var horns := Node3D.new()
			horns.position = Vector3(0, 7.4, 0)
			root.add_child(horns)
			for i in range(4):
				var a := i * PI * 0.5
				var h := cyl(horns, 0.6, 0.18, 1.0, Vector3(sin(a) * 0.6, 0, cos(a) * 0.6), METAL_DARK, 10)
				h.rotation = Vector3(PI * 0.5, a, 0)
			anim(root, horns, "spin", 0.5)
			var pulse := sphere(root, 0.3, Vector3(0, 8.2, 0), CN_RED)
			anim(root, pulse, "pulse", 3.0)
		"gattling_cannon":
			# concrete base, rotating six-barrel gun in a shield
			box(root, Vector3(3.6, 0.8, 3.6), Vector3(0, 0.4, 0), CONCRETE_DARK)
			band(root, 3.6, 3.6, 0.75, team, 0.2)
			var turret := Node3D.new()
			turret.name = "Turret"
			turret.position = Vector3(0, 0.8, 0)
			root.add_child(turret)
			cyl(turret, 0.9, 1.0, 0.7, Vector3(0, 0.35, 0), METAL, 12)
			box(turret, Vector3(1.4, 1.0, 1.2), Vector3(0, 1.2, -0.2), CN_WALL_DARK)
			box(turret, Vector3(1.5, 0.15, 0.3), Vector3(0, 1.8, -0.2), CN_RED)
			var spin := Node3D.new()
			spin.name = "Barrels"
			spin.position = Vector3(0, 1.2, 0.5)
			turret.add_child(spin)
			for i in range(6):
				var a := i * TAU / 6.0
				cyl(spin, 0.08, 0.08, 2.4, Vector3(sin(a) * 0.22, cos(a) * 0.22, 1.2), METAL_DARK, 6).rotation.x = PI * 0.5
			anim(root, spin, "spinz", 8.0)
			root.set_meta("turret", turret)
			anim(root, turret, "sweep", 0.4)
		"bunker":
			# low concrete pillbox with firing slits, sandbags on the roof
			box(root, Vector3(5.4, 2.0, 5.4), Vector3(0, 1.0, 0), CONCRETE_DARK)
			box(root, Vector3(5.6, 0.3, 5.6), Vector3(0, 2.1, 0), CONCRETE)
			band(root, 5.4, 5.4, 1.95, team, 0.2)
			for i in range(4):
				var a := i * PI * 0.5
				var slit := box(root, Vector3(2.6, 0.35, 0.1), Vector3(sin(a) * 2.7, 1.3, cos(a) * 2.7), Color(0.05, 0.05, 0.06))
				slit.rotation.y = a
			for i in range(8):
				var a := i * TAU / 8.0
				box(root, Vector3(1.2, 0.5, 0.6), Vector3(sin(a) * 2.2, 2.5, cos(a) * 2.2), Color(0.55, 0.5, 0.35), a)
			box(root, Vector3(1.6, 0.9, 1.6), Vector3(0, 2.7, 0), CONCRETE)
			_star(root, Vector3(0, 1.4, 2.71), 0.4)
		"china_nuke":
			# missile silo: heavy square pad, two blast doors that stand open, warhead tip, red lights
			box(root, Vector3(11.5, 1.2, 11.5), Vector3(0, 0.6, 0), CONCRETE_DARK)
			band(root, 11.5, 11.5, 1.15, team, 0.4)
			cyl(root, 3.2, 3.2, 1.2, Vector3(0, 1.4, 0), METAL_DARK, 20)
			cyl(root, 2.6, 2.6, 0.3, Vector3(0, 2.0, 0), Color(0.05, 0.05, 0.06), 20)
			for sx in [-1.0, 1.0]:
				var door := box(root, Vector3(3.2, 0.4, 6.8), Vector3(sx * 3.6, 2.6, 0), METAL)
				door.rotation.z = -sx * 0.9
				box(root, Vector3(3.0, 0.1, 6.6), Vector3(sx * 3.6, 2.85, 0), CN_RED).rotation.z = -sx * 0.9
			var tip := cyl(root, 0.0, 0.9, 2.0, Vector3(0, 3.0, 0), Color(0.85, 0.85, 0.82), 12)
			tip.name = "Warhead"
			cyl(root, 0.9, 0.9, 1.4, Vector3(0, 1.3, 0), Color(0.85, 0.85, 0.82), 12)
			for i in range(4):
				var lamp := sphere(root, 0.22, Vector3(-4.8 + (i % 2) * 9.6, 1.5, -4.8 + (i / 2) * 9.6), CN_RED)
				anim(root, lamp, "blink", 1.5 + i * 0.25)
			box(root, Vector3(2.4, 2.6, 2.4), Vector3(4.2, 2.5, -4.2), CN_WALL)
			box(root, Vector3(2.0, 0.8, 0.1), Vector3(4.2, 2.8, -2.95), GLASS)
			_star(root, Vector3(-4.2, 1.21, 4.2), 1.0, false, true)
		# ================= GLA =================
		"gla_cc":
			# walled adobe compound: main house, tower with a tarp, antenna, banner
			box(root, Vector3(11.5, 0.9, 13.0), Vector3(0, 0.45, 0), GLA_WALL_DARK)
			box(root, Vector3(11.5, 0.5, 0.5), Vector3(0, 1.1, 6.25), GLA_WALL)
			box(root, Vector3(11.5, 0.5, 0.5), Vector3(0, 1.1, -6.25), GLA_WALL)
			box(root, Vector3(0.5, 0.5, 13.0), Vector3(5.5, 1.1, 0), GLA_WALL)
			box(root, Vector3(0.5, 0.5, 13.0), Vector3(-5.5, 1.1, 0), GLA_WALL)
			box(root, Vector3(7.5, 3.4, 6.5), Vector3(-1.2, 2.6, -1.5), GLA_WALL)
			box(root, Vector3(7.7, 0.3, 6.7), Vector3(-1.2, 4.4, -1.5), GLA_ROOF)
			band(root, 7.5, 6.5, 4.2, team, 0.35)
			box(root, Vector3(2.6, 6.0, 2.6), Vector3(3.6, 3.9, 3.6), GLA_WALL_DARK)
			box(root, Vector3(3.2, 0.15, 3.2), Vector3(3.6, 7.0, 3.6), GLA_TARP)
			cyl(root, 0.06, 0.08, 6.0, Vector3(3.6, 10.0, 3.6), METAL, 6)
			var dish := Node3D.new()
			dish.position = Vector3(-3.5, 5.2, -1.5)
			root.add_child(dish)
			cyl(dish, 1.1, 0.15, 0.4, Vector3.ZERO, METAL, 14).rotation.x = 0.8
			anim(root, dish, "spin", 0.9)
			for i in range(3):
				box(root, Vector3(1.0, 0.7, 1.0), Vector3(-3.5 + i * 1.2, 1.25, 4.5), Color(0.62, 0.5, 0.3))
			box(root, Vector3(0.1, 3.0, 0.1), Vector3(-4.6, 6.0, -4.5), METAL_DARK)
			box(root, Vector3(1.6, 1.0, 0.06), Vector3(-3.8, 6.9, -4.5), tc)
		"supply_stash":
			# tent over crate piles, a truck-tyre wall and a tarp lean-to
			box(root, Vector3(7.6, 0.14, 7.6), Vector3(0, 0.07, 0), GLA_WALL_DARK)
			for i in range(4):
				cyl(root, 0.06, 0.08, 3.4, Vector3(-2.6 + (i % 2) * 5.2, 1.7, -2.6 + (i / 2) * 5.2), METAL, 6)
			prism(root, Vector3(6.4, 1.6, 6.4), Vector3(0, 4.0, 0), GLA_TARP)
			box(root, Vector3(6.6, 0.12, 6.6), Vector3(0, 3.3, 0), GLA_TARP.darkened(0.2))
			for i in range(6):
				box(root, Vector3(1.0, 0.9, 1.0), Vector3(-1.6 + (i % 3) * 1.3, 0.55 + (i / 3) * 0.9, 0.4), Color(0.7, 0.55, 0.3))
			for i in range(3):
				cyl(root, 0.45, 0.45, 0.35, Vector3(3.0, 0.3 + i * 0.35, -2.8), Color(0.1, 0.1, 0.11), 10)
			band(root, 7.6, 7.6, 0.2, team, 0.2)
		"gla_barracks":
			# adobe hut with a tent annexe and an obstacle course
			box(root, Vector3(6.5, 2.6, 5.0), Vector3(-1.5, 1.3, -1.0), GLA_WALL)
			box(root, Vector3(6.7, 0.3, 5.2), Vector3(-1.5, 2.75, -1.0), GLA_ROOF)
			band(root, 6.5, 5.0, 2.6, team, 0.3)
			prism(root, Vector3(3.6, 1.6, 4.0), Vector3(3.0, 1.6, 0.5), GLA_TARP)
			box(root, Vector3(3.6, 0.9, 4.0), Vector3(3.0, 0.45, 0.5), GLA_TARP.darkened(0.15))
			for i in range(4):
				box(root, Vector3(0.8, 0.5, 0.6), Vector3(-3.5 + i * 0.9, 0.25, 3.5), Color(0.55, 0.5, 0.35))
			box(root, Vector3(0.1, 3.6, 0.1), Vector3(1.6, 1.8, 3.6), METAL_DARK)
			box(root, Vector3(1.2, 0.8, 0.05), Vector3(2.2, 3.1, 3.6), tc)
			for i in range(2):
				box(root, Vector3(0.9, 0.7, 0.1), Vector3(-3.0 + i * 3.0, 1.5, 1.55), Color(0.1, 0.1, 0.12))
		"arms_dealer":
			# open-fronted workshop with junk, a gantry crane and oil drums
			box(root, Vector3(11.5, 0.3, 11.5), Vector3(0, 0.15, 0), GLA_WALL_DARK)
			box(root, Vector3(11.5, 4.0, 0.5), Vector3(0, 2.0, -5.5), GLA_WALL)
			box(root, Vector3(0.5, 4.0, 11.5), Vector3(-5.5, 2.0, 0), GLA_WALL)
			box(root, Vector3(0.5, 4.0, 11.5), Vector3(5.5, 2.0, 0), GLA_WALL)
			box(root, Vector3(11.8, 0.3, 11.8), Vector3(0, 4.15, 0), RUST)
			prism(root, Vector3(11.8, 1.4, 12.0), Vector3(0, 5.0, 0), GLA_ROOF)
			band(root, 11.5, 11.5, 4.0, team, 0.4)
			var door := box(root, Vector3(6.0, 3.6, 0.3), Vector3(0, 1.8, 5.6), RUST)
			door.name = "Door"
			for i in range(2):
				var lamp := sphere(root, 0.22, Vector3(-3.6 + i * 7.2, 3.6, 5.8), Color(1.0, 0.55, 0.1))
				lamp.name = "Light%d" % i
				lamp.visible = false
			for i in range(3):
				cyl(root, 0.45, 0.45, 1.1, Vector3(-4.2, 0.85, -3.5 + i * 1.1), Color(0.75, 0.25, 0.2), 10)
			box(root, Vector3(0.2, 0.2, 9.0), Vector3(0, 3.7, 0), METAL)
			var hook := Node3D.new()
			hook.position = Vector3(0, 3.6, 1.0)
			root.add_child(hook)
			box(hook, Vector3(0.06, 1.6, 0.06), Vector3(0, -0.8, 0), METAL_DARK)
			box(hook, Vector3(1.4, 0.6, 1.0), Vector3(0, -1.9, 0), RUST)
			anim(root, hook, "nod", 0.6)
			for i in range(3):
				box(root, Vector3(0.9, 0.9, 0.9), Vector3(3.8, 0.75, -2.0 + i * 1.6), Color(0.35, 0.33, 0.3))
		"palace":
			# domed palace with four minarets, walled forecourt
			box(root, Vector3(11.5, 1.0, 11.5), Vector3(0, 0.5, 0), GLA_WALL_DARK)
			box(root, Vector3(8.5, 5.0, 8.5), Vector3(0, 3.5, 0), GLA_PALACE)
			band(root, 8.5, 8.5, 6.0, team, 0.4)
			var dome := sphere(root, 3.8, Vector3(0, 6.6, 0), Color(0.3, 0.55, 0.5))
			dome.scale = Vector3(1.0, 0.8, 1.0)
			cyl(root, 0.15, 0.3, 1.8, Vector3(0, 10.4, 0), Color(0.9, 0.75, 0.3), 8)
			for i in range(4):
				var x := -4.8 + (i % 2) * 9.6
				var z := -4.8 + (i / 2) * 9.6
				cyl(root, 0.7, 0.9, 9.0, Vector3(x, 4.5, z), GLA_PALACE, 10)
				var cap := sphere(root, 0.95, Vector3(x, 9.3, z), Color(0.3, 0.55, 0.5))
				cap.scale = Vector3(1.0, 1.2, 1.0)
			for i in range(3):
				var arch := box(root, Vector3(1.4, 2.6, 0.2), Vector3(-2.6 + i * 2.6, 1.3, 4.3), Color(0.15, 0.12, 0.1))
				arch.name = "Arch%d" % i
			for i in range(4):
				var a := i * PI * 0.5
				var slit := box(root, Vector3(2.4, 0.4, 0.12), Vector3(sin(a) * 4.3, 4.6, cos(a) * 4.3), Color(0.05, 0.05, 0.06))
				slit.rotation.y = a
		"black_market":
			# bazaar stalls under tarps, crates, a lookout with a radio mast
			box(root, Vector3(7.6, 0.14, 7.6), Vector3(0, 0.07, 0), GLA_WALL_DARK)
			for i in range(3):
				var z := -2.5 + i * 2.5
				box(root, Vector3(5.0, 0.15, 1.6), Vector3(-0.8, 2.3, z), [GLA_TARP, Color(0.7, 0.3, 0.25), Color(0.3, 0.45, 0.6)][i])
				for k in range(2):
					cyl(root, 0.05, 0.06, 2.3, Vector3(-3.2 + k * 4.8, 1.15, z), METAL, 6)
				box(root, Vector3(4.6, 0.8, 1.2), Vector3(-0.8, 0.5, z), Color(0.55, 0.42, 0.28))
				for k in range(3):
					box(root, Vector3(0.5, 0.4, 0.5), Vector3(-2.4 + k * 1.6, 1.1, z), Color(0.6 + k * 0.1, 0.5, 0.25))
			box(root, Vector3(1.6, 3.4, 1.6), Vector3(2.9, 1.7, -2.6), GLA_WALL)
			cyl(root, 0.05, 0.07, 4.0, Vector3(2.9, 5.4, -2.6), METAL, 6)
			var pulse := sphere(root, 0.25, Vector3(2.9, 7.5, -2.6), Color(1.0, 0.9, 0.3))
			anim(root, pulse, "blink", 1.2)
			band(root, 7.6, 7.6, 0.2, team, 0.2)
		"tunnel_network":
			# sandbagged hole in the ground with a rocket launcher on a post
			box(root, Vector3(3.8, 0.2, 3.8), Vector3(0, 0.1, 0), GLA_WALL_DARK)
			cyl(root, 1.3, 1.3, 0.3, Vector3(0, 0.25, 0), Color(0.05, 0.04, 0.04), 16)
			for i in range(10):
				var a := i * TAU / 10.0
				box(root, Vector3(1.1, 0.5, 0.5), Vector3(sin(a) * 1.7, 0.5, cos(a) * 1.7), Color(0.55, 0.5, 0.35), a)
			box(root, Vector3(0.6, 0.15, 1.6), Vector3(0, 0.5, 1.2), Color(0.5, 0.38, 0.25))   # ladder / planks
			var turret := Node3D.new()
			turret.name = "Turret"
			turret.position = Vector3(1.2, 0.8, -1.0)
			root.add_child(turret)
			cyl(turret, 0.12, 0.14, 1.4, Vector3(0, 0.7, 0), METAL, 8)
			var tubes := Node3D.new()
			tubes.position = Vector3(0, 1.5, 0)
			tubes.rotation.x = -0.4
			turret.add_child(tubes)
			for k in range(2):
				cyl(tubes, 0.14, 0.14, 1.6, Vector3(-0.2 + k * 0.4, 0, 0.3), METAL_DARK, 8).rotation.x = PI * 0.5
				box(tubes, Vector3(0.18, 0.18, 0.1), Vector3(-0.2 + k * 0.4, 0, 1.12), tc)
			root.set_meta("turret", turret)
			anim(root, turret, "sweep", 0.35)
		"stinger_site":
			# sandbag ring with three stinger gunners on a common mount
			for i in range(12):
				var a := TAU * i / 12.0
				box(root, Vector3(1.3, 0.8, 0.7), Vector3(cos(a) * 2.5, 0.4, sin(a) * 2.5), Color(0.55, 0.5, 0.35), -a)
			box(root, Vector3(2.2, 0.2, 2.2), Vector3(0, 0.1, 0), GLA_WALL_DARK)
			var turret := Node3D.new()
			turret.name = "Turret"
			turret.position = Vector3(0, 0.2, 0)
			root.add_child(turret)
			for k in range(3):
				var a := (k - 1) * 0.6
				var g := Node3D.new()
				g.position = Vector3(sin(a) * 0.9, 0, cos(a) * 0.9 - 0.4)
				g.rotation.y = a
				turret.add_child(g)
				box(g, Vector3(0.5, 0.6, 0.3), Vector3(0, 1.0, 0), GLA_UNIFORM)
				sphere(g, 0.17, Vector3(0, 1.5, 0), Color(0.85, 0.68, 0.55))
				box(g, Vector3(0.5, 0.2, 0.5), Vector3(0, 1.65, 0), Color(0.9, 0.85, 0.7))
				box(g, Vector3(0.36, 0.7, 0.36), Vector3(0, 0.35, 0), GLA_UNIFORM.darkened(0.2))
				var tube := cyl(g, 0.09, 0.09, 1.3, Vector3(0.3, 1.35, 0.2), METAL_DARK, 8)
				tube.rotation.x = PI * 0.5 - 0.35
			box(turret, Vector3(0.4, 0.3, 0.05), Vector3(0, 1.9, -0.9), tc)
			root.set_meta("turret", turret)
			anim(root, turret, "sweep", 0.3)
		"demo_trap":
			# barrel bomb half-buried under a tarp with a blinking detonator
			box(root, Vector3(1.6, 0.12, 1.6), Vector3(0, 0.06, 0), GLA_WALL_DARK)
			cyl(root, 0.45, 0.45, 0.7, Vector3(0, 0.35, 0), Color(0.5, 0.3, 0.15), 10)
			box(root, Vector3(1.4, 0.06, 1.4), Vector3(0, 0.75, 0), GLA_TARP)
			var lamp := sphere(root, 0.1, Vector3(0.4, 0.85, 0.4), Color(1.0, 0.2, 0.1))
			anim(root, lamp, "blink", 2.0)
		"scud_storm":
			# nine launch tubes on a concrete pad, mounted on a fuel-tank cluster
			box(root, Vector3(11.5, 1.0, 11.5), Vector3(0, 0.5, 0), CONCRETE_DARK)
			band(root, 11.5, 11.5, 0.95, team, 0.4)
			for i in range(9):
				var x := -3.4 + (i % 3) * 3.4
				var z := -3.4 + (i / 3) * 3.4
				cyl(root, 0.6, 0.7, 1.0, Vector3(x, 1.5, z), METAL_DARK, 10)
				var m := cyl(root, 0.42, 0.42, 5.0, Vector3(x, 3.6, z), Color(0.55, 0.5, 0.4), 10)
				m.name = "Scud%d" % i
				cyl(root, 0.0, 0.42, 1.0, Vector3(x, 6.6, z), Color(0.3, 0.6, 0.2), 10)
			for i in range(3):
				cyl(root, 0.6, 0.6, 1.3, Vector3(4.8, 1.65, -4.0 + i * 1.6), Color(0.35, 0.55, 0.3), 10)
			box(root, Vector3(2.0, 2.2, 2.0), Vector3(-4.6, 2.1, 4.4), GLA_WALL)
			var lamp := sphere(root, 0.25, Vector3(-4.6, 3.5, 4.4), Color(0.4, 1.0, 0.3))
			anim(root, lamp, "blink", 1.0)
		"supply_dock":
			# supply depot: concrete pad, fuel drums, a forklift-sized shed and a loading crane.
			# The crates themselves are added by Puppet (they vanish as the dock empties).
			box(root, Vector3(8.2, 0.14, 8.2), Vector3(0, 0.07, 0), CONCRETE_DARK)
			box(root, Vector3(8.2, 0.03, 0.3), Vector3(0, 0.16, 3.9), WARN)
			box(root, Vector3(8.2, 0.03, 0.3), Vector3(0, 0.16, -3.9), WARN)
			for i in range(3):
				cyl(root, 0.45, 0.45, 1.1, Vector3(-3.4, 0.7, -2.6 + i * 1.1), Color(0.75, 0.25, 0.2), 10)
				box(root, Vector3(0.95, 0.06, 0.95), Vector3(-3.4, 1.28, -2.6 + i * 1.1), Color(0.5, 0.18, 0.15))
			box(root, Vector3(0.18, 4.0, 0.18), Vector3(3.6, 2.0, -3.4), METAL)
			var arm := Node3D.new()
			arm.position = Vector3(3.6, 4.0, -3.4)
			root.add_child(arm)
			box(arm, Vector3(0.2, 0.2, 4.0), Vector3(0, 0, -1.8), METAL)
			box(arm, Vector3(0.06, 1.6, 0.06), Vector3(0, -0.8, -3.4), METAL_DARK)
			box(arm, Vector3(0.7, 0.5, 0.7), Vector3(0, -1.8, -3.4), Color(0.75, 0.6, 0.3))
			anim(root, arm, "sweep", 0.25)
		"oil_derrick":
			# pump-jack that nods, tank, gantry
			box(root, Vector3(3.6, 0.3, 5.6), Vector3(0, 0.15, 0), CONCRETE_DARK)
			cyl(root, 0.9, 0.9, 1.6, Vector3(1.0, 1.1, 1.8), RUST, 10)
			box(root, Vector3(0.5, 3.2, 0.5), Vector3(-0.6, 1.9, -0.8), METAL)
			var beam := Node3D.new()
			beam.position = Vector3(-0.6, 3.5, -0.8)
			root.add_child(beam)
			box(beam, Vector3(0.4, 0.4, 4.4), Vector3(0, 0, 0), RUST)
			box(beam, Vector3(0.9, 0.9, 0.8), Vector3(0, 0, -2.2), METAL_DARK)
			cyl(beam, 0.08, 0.08, 2.4, Vector3(0, -1.2, 2.1), METAL, 6)
			anim(root, beam, "nod", 1.2)
			cyl(root, 0.4, 0.4, 0.6, Vector3(-0.6, 0.6, 2.2), METAL_DARK, 8)
			if team >= 0:
				box(root, Vector3(0.1, 3.0, 0.1), Vector3(1.4, 1.8, -2.4), METAL_DARK)
				box(root, Vector3(1.0, 0.7, 0.05), Vector3(0.9, 3.0, -2.4), tc)
		_:
			var fp: Vector2 = Data.footprint_size(type)
			box(root, Vector3(fp.x * 0.9, 3.0, fp.y * 0.9), Vector3(0, 1.5, 0), CONCRETE)
			band(root, fp.x * 0.9, fp.y * 0.9, 2.9, team, 0.3)
	return root

## USA / China airfield: apron, runway along the front, four hangars, tower + helipad. accent = marking colour.
static func _airfield(root: Node3D, team: int, tc: Color, accent: Color) -> void:
	# apron, runway along the front (local +z row), four hangars along the back, tower + helipad at the right
	box(root, Vector3(21.5, 0.12, 15.5), Vector3(0, 0.06, 0), CONCRETE_DARK)
	box(root, Vector3(21.0, 0.05, 4.6), Vector3(0, 0.15, 4.5), Color(0.25, 0.25, 0.27))     # runway
	for i in range(8):
		box(root, Vector3(1.4, 0.03, 0.25), Vector3(-9.0 + i * 2.6, 0.2, 4.5), Color(0.9, 0.9, 0.85))
	for i in range(2):
		box(root, Vector3(21.0, 0.03, 0.2), Vector3(0, 0.2, 4.5 + (i * 2 - 1) * 2.2), accent)
	for i in range(9):
		var rl := sphere(root, 0.12, Vector3(-10.0 + i * 2.5, 0.3, 6.8), Color(1.0, 0.95, 0.6))
		anim(root, rl, "blink", 0.6 + i * 0.1)
	# taxiway from the hangars to the runway start
	box(root, Vector3(0.25, 0.03, 8.0), Vector3(-9.5, 0.2, 0.0), accent)
	box(root, Vector3(18.0, 0.03, 0.25), Vector3(-1.0, 0.2, -1.5), accent)
	for i in range(4):
		var hx := -8.0 + i * 5.3
		# hangar: two walls, roof, dark interior, open front toward +z
		box(root, Vector3(4.6, 0.04, 4.8), Vector3(hx, 0.19, -4.5), Color(0.3, 0.3, 0.32))
		box(root, Vector3(0.3, 3.2, 4.8), Vector3(hx - 2.2, 1.6, -4.7), CONCRETE)
		box(root, Vector3(0.3, 3.2, 4.8), Vector3(hx + 2.2, 1.6, -4.7), CONCRETE)
		box(root, Vector3(4.6, 0.3, 4.8), Vector3(hx, 3.3, -4.7), ROOF)
		box(root, Vector3(4.6, 3.2, 0.25), Vector3(hx, 1.6, -7.0), CONCRETE_DARK)
		prism(root, Vector3(4.9, 1.0, 4.9), Vector3(hx, 3.9, -4.7), ROOF)
		box(root, Vector3(4.6, 0.5, 0.1), Vector3(hx, 3.1, -2.3), tc)      # team-colour lintel
		var light := sphere(root, 0.16, Vector3(hx, 3.0, -2.2), Color(1.0, 0.95, 0.6))
		anim(root, light, "blink", 0.8 + i * 0.2)
	# helipad
	box(root, Vector3(5.0, 0.04, 5.0), Vector3(8.5, 0.19, 4.5), Color(0.3, 0.3, 0.32))
	box(root, Vector3(3.0, 0.03, 0.5), Vector3(8.5, 0.22, 4.5), accent)
	box(root, Vector3(0.5, 0.03, 2.4), Vector3(7.4, 0.22, 4.5), accent)
	box(root, Vector3(0.5, 0.03, 2.4), Vector3(9.6, 0.22, 4.5), accent)
	# tower
	box(root, Vector3(2.4, 2.4, 2.4), Vector3(8.6, 1.2, 0.4), CONCRETE)
	cyl(root, 0.6, 0.7, 4.0, Vector3(8.6, 4.4, 0.4), CONCRETE_DARK, 8)
	box(root, Vector3(2.4, 1.4, 2.4), Vector3(8.6, 7.1, 0.4), GLASS)
	box(root, Vector3(2.8, 0.3, 2.8), Vector3(8.6, 7.9, 0.4), ROOF)
	var radar := Node3D.new()
	radar.position = Vector3(8.6, 8.3, 0.4)
	root.add_child(radar)
	box(radar, Vector3(1.6, 0.5, 0.1), Vector3(0, 0.25, 0), METAL)
	anim(root, radar, "spin", 2.5)
	band(root, 2.4, 2.4, 2.3, team, 0.25)
	# windsock
	box(root, Vector3(0.08, 3.0, 0.08), Vector3(-10.2, 1.5, -7.2), METAL)
	var sock := cyl(root, 0.15, 0.3, 1.0, Vector3(-9.7, 2.9, -7.2), Color(1.0, 0.5, 0.1), 6)
	sock.rotation.z = -PI * 0.5
	anim(root, sock, "nod", 1.5)

## Vehicle plant: big hangar with a wide door (Door / Light0-1 animate), roof vents, fan.
static func _war_factory(root: Node3D, team: int, tc: Color, wall: Color, door_col: Color) -> void:
	# large hangar with a wide door, roof vents, side crane rail
	box(root, Vector3(11.5, 5.0, 11.5), Vector3(0, 2.5, 0), wall)
	prism(root, Vector3(11.7, 2.0, 11.8), Vector3(0, 6.0, 0), ROOF)
	band(root, 11.5, 11.5, 4.8, team, 0.4)
	var door := box(root, Vector3(6.0, 3.6, 0.3), Vector3(0, 1.8, 5.75), door_col)
	door.name = "Door"
	box(root, Vector3(6.2, 0.4, 0.4), Vector3(0, 3.8, 5.8), WARN)
	for i in range(2):
		var lamp := sphere(root, 0.22, Vector3(-3.6 + i * 7.2, 4.4, 5.9), Color(1.0, 0.55, 0.1))
		lamp.name = "Light%d" % i
		lamp.visible = false
	for i in range(3):
		box(root, Vector3(1.2, 0.8, 1.2), Vector3(-3.5 + i * 3.5, 7.2, -2.0), METAL)
	for i in range(2):
		box(root, Vector3(0.8, 0.8, 0.1), Vector3(-4.0 + i * 8.0, 3.5, 5.8), GLASS)
	var fan := cyl(root, 0.9, 0.9, 0.2, Vector3(3.5, 7.15, 2.5), METAL_DARK, 8)
	anim(root, fan, "spin", 4.0)


## Sloped Chinese roof: a flat prism with upturned eave slabs.
static func _pagoda(root: Node3D, pos: Vector3, w: float, d: float, col: Color) -> void:
	prism(root, Vector3(w + 0.6, 1.1, d + 0.6), pos + Vector3(0, 0.55, 0), col)
	for sx in [-1.0, 1.0]:
		var eave := box(root, Vector3(0.9, 0.12, d + 0.8), pos + Vector3(sx * (w * 0.5 + 0.55), 0.25, 0), col.darkened(0.1))
		eave.rotation.z = sx * 0.35
	box(root, Vector3(w * 0.4, 0.3, 0.3), pos + Vector3(0, 1.2, 0), col.darkened(0.2))

## Red star emblem (flat) on a wall or the ground.
static func _star(root: Node3D, pos: Vector3, r: float, side := false, flat := false) -> void:
	for i in range(5):
		var a := i * TAU / 5.0
		var arm := box(root, Vector3(r * 0.35, r * 1.0, 0.04), pos, Color(0.95, 0.2, 0.15))
		if flat:
			arm.rotation = Vector3(-PI * 0.5, a, 0)
		elif side:
			arm.rotation = Vector3(0, PI * 0.5, a)
		else:
			arm.rotation.z = a
		arm.position = pos

static func _steam(pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = 10
	p.lifetime = 2.2
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0.4, 0.3, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	mesh.radial_segments = 6
	mesh.rings = 3
	p.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.9, 0.9, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p.material_override = m
	return p

## Bulldozer blade + roll cage bolted onto a truck model.
static func dozer_kit(root: Node3D, team: int, length: float) -> void:
	var tc := team_col(team)
	var blade := Node3D.new()
	blade.position = Vector3(0, 0.5, length * 0.55)
	root.add_child(blade)
	var b := box(blade, Vector3(length * 0.6, 1.0, 0.25), Vector3(0, 0, 0), WARN)
	b.rotation.x = -0.25
	box(blade, Vector3(0.15, 0.6, 1.0), Vector3(-length * 0.2, 0.2, -0.5), METAL_DARK)
	box(blade, Vector3(0.15, 0.6, 1.0), Vector3(length * 0.2, 0.2, -0.5), METAL_DARK)
	box(root, Vector3(0.5, 0.3, 0.05), Vector3(0, length * 0.42, -length * 0.35), tc)
