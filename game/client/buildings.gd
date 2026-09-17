class_name Buildings
extends RefCounted
## Procedural low-poly structure models built from primitives, sized exactly to
## the sim footprints and painted with the owner's colour. Each model carries
## meta "anim": [{node, kind, speed}] for idle animation (radar spin, launcher
## sweep, gun traverse, pump-jack nod, steam).

const CONCRETE := Color(0.58, 0.57, 0.53)
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
			# large hangar with a wide door, roof vents, side crane rail
			box(root, Vector3(11.5, 5.0, 11.5), Vector3(0, 2.5, 0), CONCRETE)
			prism(root, Vector3(11.7, 2.0, 11.8), Vector3(0, 6.0, 0), ROOF)
			band(root, 11.5, 11.5, 4.8, team, 0.4)
			var door := box(root, Vector3(6.0, 3.6, 0.3), Vector3(0, 1.8, 5.75), METAL_DARK)
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
		"airfield":
			# apron, runway along the front (local +z row), four hangars along the back, tower + helipad at the right
			box(root, Vector3(21.5, 0.12, 15.5), Vector3(0, 0.06, 0), CONCRETE_DARK)
			box(root, Vector3(21.0, 0.05, 4.6), Vector3(0, 0.15, 4.5), Color(0.25, 0.25, 0.27))     # runway
			for i in range(8):
				box(root, Vector3(1.4, 0.03, 0.25), Vector3(-9.0 + i * 2.6, 0.2, 4.5), Color(0.9, 0.9, 0.85))
			for i in range(2):
				box(root, Vector3(21.0, 0.03, 0.2), Vector3(0, 0.2, 4.5 + (i * 2 - 1) * 2.2), WARN)
			for i in range(9):
				var rl := sphere(root, 0.12, Vector3(-10.0 + i * 2.5, 0.3, 6.8), Color(1.0, 0.95, 0.6))
				anim(root, rl, "blink", 0.6 + i * 0.1)
			# taxiway from the hangars to the runway start
			box(root, Vector3(0.25, 0.03, 8.0), Vector3(-9.5, 0.2, 0.0), WARN)
			box(root, Vector3(18.0, 0.03, 0.25), Vector3(-1.0, 0.2, -1.5), WARN)
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
			box(root, Vector3(3.0, 0.03, 0.5), Vector3(8.5, 0.22, 4.5), WARN)
			box(root, Vector3(0.5, 0.03, 2.4), Vector3(7.4, 0.22, 4.5), WARN)
			box(root, Vector3(0.5, 0.03, 2.4), Vector3(9.6, 0.22, 4.5), WARN)
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
