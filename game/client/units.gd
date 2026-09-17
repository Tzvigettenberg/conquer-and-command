class_name Units
extends RefCounted
## Procedural low-poly unit models (blocky, Generals-flavoured). Forward is +Z,
## up is +Y, sizes are real metres (Data "length"). Node names drive the
## animation in Puppet: "Turret" (meta), "Wheel*" spin about X, "Rotor*" spin
## about Y ("RotorTail" about X), "LegL/LegR/ArmL/ArmR" swing while walking,
## "Door*"/"Light*" are used by buildings, "Exhaust" gets engine smoke.

const BODY := Color(0.56, 0.54, 0.44)       # USA desert tan
const BODY_DARK := Color(0.42, 0.41, 0.34)
const METAL := Color(0.3, 0.31, 0.34)
const DARK := Color(0.16, 0.16, 0.18)
const GLASS := Color(0.42, 0.5, 0.54)
const RUBBER := Color(0.12, 0.12, 0.13)
const SKIN := Color(0.85, 0.68, 0.55)
const UNIFORM := Color(0.36, 0.4, 0.3)
# China: olive drab with red trim.  GLA: sun-bleached khaki, rust, improvised.
const CN_BODY := Color(0.36, 0.44, 0.3)
const CN_DARK := Color(0.26, 0.32, 0.22)
const CN_RED := Color(0.8, 0.15, 0.12)
const CN_UNIFORM := Color(0.3, 0.38, 0.26)
const GLA_BODY := Color(0.64, 0.56, 0.38)
const GLA_DARK := Color(0.46, 0.4, 0.28)
const GLA_RUST := Color(0.5, 0.3, 0.18)
const GLA_UNIFORM := Color(0.5, 0.42, 0.3)

static func _tc(team: int) -> Color:
	return Data.TEAM_COLORS[team % Data.TEAM_COLORS.size()] if team >= 0 else Color(0.6, 0.6, 0.6)

static func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := Buildings.box(parent, size, pos, c)
	mi.rotation = rot
	return mi

static func cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, c: Color, rot := Vector3.ZERO, segs := 10) -> MeshInstance3D:
	var mi := Buildings.cyl(parent, r_top, r_bot, h, pos, c, segs)
	mi.rotation = rot
	return mi

static func prism(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := Buildings.prism(parent, size, pos, c)
	mi.rotation = rot
	return mi

## A wheel that Puppet can spin: Node3D named Wheel* with the cylinder inside.
static func wheel(parent: Node3D, r: float, w: float, pos: Vector3, nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	cyl(n, r, r, w, Vector3.ZERO, RUBBER, Vector3(0, 0, PI * 0.5), 12)
	cyl(n, r * 0.55, r * 0.55, w + 0.04, Vector3.ZERO, METAL, Vector3(0, 0, PI * 0.5), 8)
	return n

## Tank track: dark slab with wheel bumps, on each side.
static func tracks(root: Node3D, l: float, w: float, h: float, x: float) -> void:
	for sx in [-1.0, 1.0]:
		box(root, Vector3(w, h, l), Vector3(sx * x, h * 0.5, 0), DARK)
		box(root, Vector3(w * 1.05, h * 0.25, l * 0.96), Vector3(sx * x, h * 0.95, 0), Color(0.22, 0.22, 0.24))
		var n := int(l / 0.9)
		for i in range(n):
			var z := -l * 0.5 + 0.45 + i * 0.9
			cyl(root, h * 0.32, h * 0.32, w * 1.06, Vector3(sx * x, h * 0.45, z), METAL, Vector3(0, 0, PI * 0.5), 8)

static func make(type: String, team: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	root.set_meta("procedural", true)
	var tc := _tc(team)
	var def := Data.def(type)
	var l := float(def.get("length", 4.0))
	match type:
		"dozer":
			_dozer(root, tc, l)
		"humvee":
			_humvee(root, tc, l)
		"ambulance":
			_ambulance(root, tc, l)
		"crusader":
			_tank(root, tc, l, false)
		"paladin":
			_tank(root, tc, l, true)
		"tomahawk":
			_tomahawk(root, tc, l)
		"avenger":
			_avenger(root, tc, l)
		"comanche":
			_comanche(root, tc, l)
		"chinook":
			_chinook(root, tc, l)
		"raptor":
			_jet(root, tc, l, "raptor")
		"stealth_fighter":
			_jet(root, tc, l, "stealth")
		"aurora":
			_jet(root, tc, l, "aurora")
		"ranger", "missile_defender", "pathfinder", "burton":
			_soldier(root, tc, type)
		"scout_drone", "battle_drone", "hellfire_drone", "spy_drone":
			_drone(root, tc, type)
		"sentry_drone":
			_sentry_drone(root, tc, l)
		"microwave_tank":
			_microwave_tank(root, tc, l)
		# ---- China ----
		"china_dozer":
			_dozer(root, tc, l, CN_BODY, CN_DARK)
		"red_guard", "tank_hunter", "hacker", "black_lotus":
			_soldier(root, tc, type)
		"supply_truck":
			_supply_truck(root, tc, l)
		"battlemaster":
			_tank(root, tc, l, false, CN_BODY, CN_DARK)
		"gattling_tank":
			_gattling_tank(root, tc, l)
		"dragon_tank":
			_dragon_tank(root, tc, l)
		"troop_crawler":
			_troop_crawler(root, tc, l)
		"inferno_cannon":
			_inferno(root, tc, l)
		"overlord":
			_overlord(root, tc, l)
		"nuke_cannon":
			_nuke_cannon(root, tc, l)
		"mig":
			_jet(root, tc, l, "mig")
		"helix":
			_helix(root, tc, l)
		# ---- GLA ----
		"worker", "rebel", "rpg_trooper", "terrorist", "jarmen_kell":
			_soldier(root, tc, type)
		"technical":
			_technical(root, tc, l)
		"scorpion":
			_scorpion(root, tc, l)
		"quad_cannon":
			_quad_cannon(root, tc, l)
		"rocket_buggy":
			_rocket_buggy(root, tc, l)
		"toxin_tractor":
			_toxin_tractor(root, tc, l)
		"marauder":
			_marauder(root, tc, l)
		"scud_launcher":
			_scud_launcher(root, tc, l)
		"bomb_truck":
			_bomb_truck(root, tc, l)
		_:
			box(root, Vector3(l * 0.5, l * 0.3, l), Vector3(0, l * 0.15, 0), tc)
	return root

# ---------------------------------------------------------------------------
# Ground vehicles
# ---------------------------------------------------------------------------
static func _dozer(root: Node3D, tc: Color, l: float, body := BODY, body_dark := BODY_DARK) -> void:
	var w := l * 0.55
	tracks(root, l * 0.7, w * 0.25, 0.7, w * 0.42)
	box(root, Vector3(w * 0.7, 0.7, l * 0.62), Vector3(0, 1.0, -0.2), body)
	box(root, Vector3(w * 0.72, 0.16, l * 0.3), Vector3(0, 1.4, -0.9), tc)     # team-colour rear deck
	# cab with glass
	box(root, Vector3(w * 0.5, 0.9, l * 0.28), Vector3(0, 1.8, -0.35), body_dark)
	box(root, Vector3(w * 0.52, 0.5, l * 0.29), Vector3(0, 1.9, -0.35), GLASS)
	box(root, Vector3(w * 0.56, 0.1, l * 0.34), Vector3(0, 2.3, -0.35), tc)
	cyl(root, 0.08, 0.08, 0.9, Vector3(w * 0.28, 2.0, -0.9), DARK, Vector3.ZERO, 6).name = "Exhaust"
	# arms + blade
	for sx in [-1.0, 1.0]:
		box(root, Vector3(0.14, 0.14, l * 0.45), Vector3(sx * w * 0.42, 0.9, l * 0.3), METAL)
	var blade := box(root, Vector3(w * 1.15, 0.9, 0.18), Vector3(0, 0.6, l * 0.52), Color(0.85, 0.7, 0.2))
	blade.name = "DozerShovel"
	box(root, Vector3(w * 1.15, 0.12, 0.2), Vector3(0, 1.1, l * 0.5), METAL)

static func _humvee(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.5
	box(root, Vector3(w, 0.55, l * 0.95), Vector3(0, 0.8, 0), BODY)               # chassis/body
	box(root, Vector3(w * 0.98, 0.45, l * 0.45), Vector3(0, 1.3, -0.15), BODY)     # cabin
	box(root, Vector3(w * 0.9, 0.3, l * 0.42), Vector3(0, 1.45, -0.15), GLASS)     # windows
	box(root, Vector3(w * 1.0, 0.1, l * 0.48), Vector3(0, 1.65, -0.15), tc)        # roof, team colour
	box(root, Vector3(w * 0.95, 0.35, l * 0.3), Vector3(0, 0.95, l * 0.33), BODY_DARK)  # hood
	box(root, Vector3(w * 0.8, 0.2, 0.06), Vector3(0, 0.95, l * 0.48), DARK)      # grille
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			wheel(root, 0.42, 0.32, Vector3(sx * w * 0.5, 0.42, sz * l * 0.3), "Wheel%s%s" % ["L" if sx < 0 else "R", "F" if sz > 0 else "B"])
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.7, -0.2)
	root.add_child(turret)
	cyl(turret, 0.3, 0.3, 0.15, Vector3(0, 0.07, 0), METAL, Vector3.ZERO, 8)
	box(turret, Vector3(0.12, 0.12, 0.9), Vector3(0, 0.3, 0.45), DARK)
	box(turret, Vector3(0.3, 0.25, 0.35), Vector3(0, 0.3, 0), METAL)
	root.set_meta("turret", turret)

static func _ambulance(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.5
	box(root, Vector3(w, 0.5, l * 0.95), Vector3(0, 0.75, 0), BODY)
	box(root, Vector3(w * 1.02, 1.2, l * 0.62), Vector3(0, 1.55, -0.35), Color(0.9, 0.9, 0.88))   # white box
	box(root, Vector3(w * 0.9, 0.5, l * 0.24), Vector3(0, 1.3, l * 0.28), BODY_DARK)             # cab
	box(root, Vector3(w * 0.85, 0.3, l * 0.22), Vector3(0, 1.45, l * 0.28), GLASS)
	box(root, Vector3(w * 1.04, 0.5, 0.12), Vector3(0, 1.6, -0.35 + l * 0.31), Color(0.9, 0.2, 0.2))   # red cross front
	box(root, Vector3(0.12, 0.5, l * 0.3), Vector3(0, 1.6, -0.35 + l * 0.31 + 0.01), Color(0.9, 0.2, 0.2))
	for sx in [-1.0, 1.0]:
		box(root, Vector3(0.05, 0.5, 0.15), Vector3(sx * (w * 0.51), 1.6, -0.35), Color(0.9, 0.2, 0.2))
		box(root, Vector3(0.05, 0.15, 0.5), Vector3(sx * (w * 0.51), 1.6, -0.35), Color(0.9, 0.2, 0.2))
	box(root, Vector3(w * 0.4, 0.12, 0.3), Vector3(0, 2.2, -0.2), tc)
	var light := box(root, Vector3(0.3, 0.14, 0.2), Vector3(0, 2.25, 0.4), Color(1.0, 0.4, 0.3))
	light.name = "LightBeacon"
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			wheel(root, 0.4, 0.3, Vector3(sx * w * 0.5, 0.4, sz * l * 0.3), "Wheel%s%s" % ["L" if sx < 0 else "R", "F" if sz > 0 else "B"])

static func _tank(root: Node3D, tc: Color, l: float, heavy: bool, body := BODY, body_dark := BODY_DARK) -> void:
	var w := l * 0.62
	tracks(root, l * 0.95, w * 0.26, 0.75, w * 0.4)
	box(root, Vector3(w * 0.62, 0.55, l * 0.9), Vector3(0, 1.0, 0), body)                       # hull
	prism(root, Vector3(w * 0.62, 0.35, l * 0.25), Vector3(0, 1.45, l * 0.35), body_dark, Vector3(-PI * 0.5, 0, 0))  # glacis
	box(root, Vector3(w * 0.64, 0.1, l * 0.5), Vector3(0, 1.3, -0.2), body_dark)
	if heavy:
		for sx in [-1.0, 1.0]:
			# armour skirts hang over the tracks
			box(root, Vector3(w * 0.3, 0.42, l * 0.9), Vector3(sx * w * 0.4, 0.92, 0), body_dark)
			box(root, Vector3(w * 0.32, 0.08, l * 0.92), Vector3(sx * w * 0.4, 1.15, 0), body)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.3, -0.15)
	root.add_child(turret)
	var tw := w * 0.5 if not heavy else w * 0.58
	box(turret, Vector3(tw, 0.55, l * 0.4), Vector3(0, 0.28, 0), body)
	prism(turret, Vector3(tw, 0.25, l * 0.2), Vector3(0, 0.65, l * 0.1), body_dark, Vector3(-PI * 0.5, 0, 0))
	box(turret, Vector3(tw * 0.9, 0.08, l * 0.3), Vector3(0, 0.6, -0.05), tc)      # team-colour roof patch
	cyl(turret, 0.09, 0.11, l * 0.7, Vector3(0, 0.3, l * 0.2 + l * 0.35), DARK, Vector3(PI * 0.5, 0, 0), 8)   # barrel
	cyl(turret, 0.14, 0.14, 0.4, Vector3(0, 0.3, l * 0.2 + l * 0.66), DARK, Vector3(PI * 0.5, 0, 0), 8)      # muzzle brake
	box(turret, Vector3(0.35, 0.25, 0.35), Vector3(-tw * 0.3, 0.68, -0.2), METAL)   # hatch
	if heavy:
		var dome := Buildings.sphere(turret, 0.28, Vector3(tw * 0.3, 0.75, -0.3), Color(0.4, 0.8, 1.0))
		dome.name = "LaserDome"
	root.set_meta("turret", turret)

static func _tomahawk(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.5
	box(root, Vector3(w, 0.5, l * 0.95), Vector3(0, 0.75, 0), BODY)
	box(root, Vector3(w * 0.9, 0.55, l * 0.22), Vector3(0, 1.25, l * 0.32), BODY_DARK)   # cab
	box(root, Vector3(w * 0.85, 0.3, l * 0.2), Vector3(0, 1.4, l * 0.32), GLASS)
	for sz in [-1.0, 0.0, 1.0]:
		for sx in [-1.0, 1.0]:
			wheel(root, 0.4, 0.3, Vector3(sx * w * 0.5, 0.4, sz * l * 0.32), "Wheel%s%d" % ["L" if sx < 0 else "R", int(sz + 1)])
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.05, -0.4)
	root.add_child(turret)
	var tilt := Node3D.new()
	tilt.rotation.x = -0.5
	tilt.position = Vector3(0, 0.3, -0.6)
	turret.add_child(tilt)
	box(tilt, Vector3(w * 0.7, 0.6, l * 0.55), Vector3(0, 0.3, l * 0.2), METAL)     # launcher box
	box(tilt, Vector3(w * 0.6, 0.5, 0.06), Vector3(0, 0.3, l * 0.48), tc)
	cyl(tilt, 0.12, 0.12, l * 0.5, Vector3(0, 0.3, l * 0.2), Color(0.85, 0.85, 0.8), Vector3(PI * 0.5, 0, 0), 8)  # missile
	root.set_meta("turret", turret)

static func _avenger(root: Node3D, tc: Color, l: float) -> void:
	_humvee(root, tc, l)
	var old := root.get_meta("turret") as Node3D
	old.queue_free()
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.7, -0.3)
	root.add_child(turret)
	box(turret, Vector3(0.9, 0.5, 0.9), Vector3(0, 0.25, 0), METAL)
	for sx in [-1.0, 1.0]:
		var d := cyl(turret, 0.45, 0.15, 0.3, Vector3(sx * 0.55, 0.55, 0.2), Color(0.8, 0.85, 0.9), Vector3(-PI * 0.35, 0, 0), 12)
		d.name = "Emitter%d" % int(sx + 1)
		var em := Buildings.sphere(turret, 0.12, Vector3(sx * 0.55, 0.6, 0.35), Color(0.4, 0.8, 1.0))
		em.name = "Laser%d" % int(sx + 1)
	root.set_meta("turret", turret)

static func _star_decal(root: Node3D, pos: Vector3, r: float) -> void:
	for i in range(5):
		var arm := box(root, Vector3(r * 0.3, r * 0.02, r), pos, CN_RED, Vector3(0, i * TAU / 5.0, 0))
		arm.position = pos

## Tiny quad-rotor escort drone (scout: camera pod, battle: gun, hellfire: two missiles, spy: big lens).
static func _drone(root: Node3D, tc: Color, type: String) -> void:
	var body := box(root, Vector3(0.5, 0.22, 0.5), Vector3(0, 0.5, 0), METAL)
	box(root, Vector3(0.3, 0.06, 0.3), Vector3(0, 0.63, 0), tc)
	for i in range(4):
		var a := i * PI * 0.5 + PI * 0.25
		var arm := box(root, Vector3(0.08, 0.05, 0.55), Vector3(sin(a) * 0.35, 0.5, cos(a) * 0.35), DARK)
		arm.rotation.y = a
		_rotor(root, "Rotor%d" % i, Vector3(sin(a) * 0.62, 0.58, cos(a) * 0.62), 0.28, 2)
	match type:
		"scout_drone", "spy_drone":
			Buildings.sphere(root, 0.12 if type == "scout_drone" else 0.18, Vector3(0, 0.36, 0.2), Color(0.2, 0.5, 0.9))
		"battle_drone":
			box(root, Vector3(0.06, 0.06, 0.5), Vector3(0, 0.36, 0.3), DARK)
		"hellfire_drone":
			for sx in [-1.0, 1.0]:
				cyl(root, 0.05, 0.05, 0.45, Vector3(sx * 0.2, 0.36, 0.05), Color(0.85, 0.85, 0.8), Vector3(PI * 0.5, 0, 0), 6).name = "Missile%d" % int(sx + 1)
	body.name = "Body"

static func _sentry_drone(root: Node3D, tc: Color, l: float) -> void:
	# low six-wheeled robot with a sensor mast and a small gun
	var w := l * 0.7
	box(root, Vector3(w, 0.5, l * 0.9), Vector3(0, 0.55, 0), BODY_DARK)
	box(root, Vector3(w * 0.8, 0.12, l * 0.6), Vector3(0, 0.86, 0), tc)
	for sz in [-1.0, 0.0, 1.0]:
		for sx in [-1.0, 1.0]:
			wheel(root, 0.28, 0.2, Vector3(sx * w * 0.5, 0.28, sz * l * 0.32), "Wheel%s%d" % ["L" if sx < 0 else "R", int(sz + 1)])
	cyl(root, 0.05, 0.05, 1.2, Vector3(-w * 0.25, 1.4, -l * 0.2), METAL, Vector3.ZERO, 6)
	Buildings.sphere(root, 0.16, Vector3(-w * 0.25, 2.05, -l * 0.2), Color(0.2, 0.6, 1.0)).name = "Sensor"
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(w * 0.15, 0.85, 0.1)
	root.add_child(turret)
	box(turret, Vector3(0.3, 0.25, 0.4), Vector3(0, 0.15, 0), METAL)
	box(turret, Vector3(0.06, 0.06, 0.9), Vector3(0, 0.18, 0.5), DARK)
	root.set_meta("turret", turret)

static func _microwave_tank(root: Node3D, tc: Color, l: float) -> void:
	_tank(root, tc, l, false)
	var old := root.get_meta("turret") as Node3D
	old.queue_free()
	var w := l * 0.62
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.3, -0.1)
	root.add_child(turret)
	box(turret, Vector3(w * 0.4, 0.4, l * 0.3), Vector3(0, 0.2, 0), BODY)
	var dish := cyl(turret, 1.3, 0.3, 0.5, Vector3(0, 0.75, 0.3), Color(0.8, 0.82, 0.85), Vector3(-PI * 0.4, 0, 0), 14)
	dish.name = "Dish"
	var em := Buildings.sphere(turret, 0.2, Vector3(0, 0.95, 0.75), Color(0.6, 0.9, 1.0))
	em.name = "Emitter"
	root.set_meta("turret", turret)

# ---------------------------------------------------------------------------
# China vehicles
# ---------------------------------------------------------------------------
static func _supply_truck(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.5
	box(root, Vector3(w, 0.45, l * 0.95), Vector3(0, 0.75, 0), CN_DARK)
	box(root, Vector3(w * 0.95, 1.0, l * 0.26), Vector3(0, 1.45, l * 0.3), CN_BODY)     # cab
	box(root, Vector3(w * 0.9, 0.4, l * 0.24), Vector3(0, 1.7, l * 0.31), GLASS)
	box(root, Vector3(w * 0.98, 0.1, l * 0.28), Vector3(0, 2.0, l * 0.3), tc)
	box(root, Vector3(w * 1.0, 0.25, l * 0.55), Vector3(0, 1.1, -l * 0.15), CN_BODY)    # flatbed
	for i in range(4):
		var c := box(root, Vector3(w * 0.42, 0.55, l * 0.22), Vector3((-0.5 + (i % 2)) * w * 0.48, 1.5, -l * 0.02 - (i / 2) * l * 0.26), Color(0.72, 0.56, 0.3))
		c.name = "Crate%d" % i
	for sz in [-1.0, 0.0, 1.0]:
		for sx in [-1.0, 1.0]:
			wheel(root, 0.42, 0.3, Vector3(sx * w * 0.5, 0.42, sz * l * 0.32), "Wheel%s%d" % ["L" if sx < 0 else "R", int(sz + 1)])
	cyl(root, 0.06, 0.06, 0.8, Vector3(w * 0.45, 1.9, l * 0.15), DARK, Vector3.ZERO, 6).name = "Exhaust"

static func _gattling_tank(root: Node3D, tc: Color, l: float) -> void:
	_tank(root, tc, l, false, CN_BODY, CN_DARK)
	var old := root.get_meta("turret") as Node3D
	old.queue_free()
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.3, -0.15)
	root.add_child(turret)
	var w := l * 0.62
	box(turret, Vector3(w * 0.45, 0.5, l * 0.36), Vector3(0, 0.25, 0), CN_BODY)
	box(turret, Vector3(w * 0.4, 0.08, l * 0.28), Vector3(0, 0.55, -0.05), tc)
	var spin := Node3D.new()
	spin.name = "Barrels"
	spin.position = Vector3(0, 0.3, l * 0.2)
	turret.add_child(spin)
	for i in range(6):
		var a := i * TAU / 6.0
		cyl(spin, 0.06, 0.06, l * 0.55, Vector3(sin(a) * 0.17, cos(a) * 0.17, l * 0.27), DARK, Vector3(PI * 0.5, 0, 0), 6)
	cyl(spin, 0.22, 0.22, 0.15, Vector3(0, 0, l * 0.5), METAL, Vector3(PI * 0.5, 0, 0), 8)
	root.set_meta("turret", turret)
	root.set_meta("anim", [{"node": spin, "kind": "spinz", "speed": 10.0}])

static func _dragon_tank(root: Node3D, tc: Color, l: float) -> void:
	_tank(root, tc, l, false, CN_BODY, CN_DARK)
	var old := root.get_meta("turret") as Node3D
	old.queue_free()
	var w := l * 0.62
	# fuel tanks on the rear deck
	for sx in [-1.0, 1.0]:
		cyl(root, 0.3, 0.3, l * 0.35, Vector3(sx * w * 0.2, 1.55, -l * 0.28), Color(0.55, 0.15, 0.1), Vector3(PI * 0.5, 0, 0), 10)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.3, -0.05)
	root.add_child(turret)
	box(turret, Vector3(w * 0.42, 0.45, l * 0.32), Vector3(0, 0.22, 0), CN_BODY)
	box(turret, Vector3(w * 0.36, 0.08, l * 0.24), Vector3(0, 0.5, -0.05), tc)
	cyl(turret, 0.12, 0.12, l * 0.4, Vector3(0, 0.25, l * 0.3), DARK, Vector3(PI * 0.5, 0, 0), 8)
	var nozzle := cyl(turret, 0.2, 0.12, 0.3, Vector3(0, 0.25, l * 0.52), Color(0.9, 0.45, 0.1), Vector3(PI * 0.5, 0, 0), 8)
	nozzle.name = "Nozzle"
	root.set_meta("turret", turret)

static func _troop_crawler(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.5
	box(root, Vector3(w, 0.5, l * 0.95), Vector3(0, 0.8, 0), CN_DARK)
	box(root, Vector3(w * 1.02, 1.3, l * 0.7), Vector3(0, 1.65, -l * 0.08), CN_BODY)      # armoured box
	prism(root, Vector3(w * 1.02, 0.5, l * 0.24), Vector3(0, 1.3, l * 0.4), CN_DARK, Vector3(-PI * 0.5, 0, 0))
	box(root, Vector3(w * 0.9, 0.35, 0.1), Vector3(0, 1.75, l * 0.27), GLASS)
	box(root, Vector3(w * 1.04, 0.1, l * 0.72), Vector3(0, 2.32, -l * 0.08), tc)
	for i in range(3):
		for sx in [-1.0, 1.0]:
			box(root, Vector3(0.06, 0.3, 0.5), Vector3(sx * w * 0.52, 1.7, -l * 0.3 + i * l * 0.22), Color(0.05, 0.05, 0.06))   # firing slits
	var ramp := box(root, Vector3(w * 0.9, 0.12, 0.5), Vector3(0, 1.1, -l * 0.46), CN_DARK)
	ramp.name = "Ramp"
	for sz in [-1.0, 0.0, 1.0]:
		for sx in [-1.0, 1.0]:
			wheel(root, 0.45, 0.32, Vector3(sx * w * 0.5, 0.45, sz * l * 0.3), "Wheel%s%d" % ["L" if sx < 0 else "R", int(sz + 1)])
	_star_decal(root, Vector3(0, 2.38, 0), 0.5)

static func _inferno(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.6
	tracks(root, l * 0.9, w * 0.26, 0.7, w * 0.4)
	box(root, Vector3(w * 0.6, 0.5, l * 0.85), Vector3(0, 0.95, 0), CN_BODY)
	box(root, Vector3(w * 0.62, 0.1, l * 0.3), Vector3(0, 1.25, l * 0.25), tc)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.2, -0.3)
	root.add_child(turret)
	box(turret, Vector3(w * 0.5, 0.5, l * 0.3), Vector3(0, 0.25, 0), CN_DARK)
	var tilt := Node3D.new()
	tilt.position = Vector3(0, 0.5, 0)
	tilt.rotation.x = -0.6
	turret.add_child(tilt)
	cyl(tilt, 0.2, 0.28, l * 0.7, Vector3(0, 0, l * 0.3), DARK, Vector3(PI * 0.5, 0, 0), 10)
	cyl(tilt, 0.3, 0.2, 0.3, Vector3(0, 0, l * 0.66), Color(0.9, 0.45, 0.1), Vector3(PI * 0.5, 0, 0), 10)
	root.set_meta("turret", turret)

static func _overlord(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.66
	tracks(root, l * 0.98, w * 0.3, 1.0, w * 0.38)
	box(root, Vector3(w * 0.6, 0.8, l * 0.92), Vector3(0, 1.3, 0), CN_BODY)
	prism(root, Vector3(w * 0.6, 0.45, l * 0.22), Vector3(0, 1.9, l * 0.38), CN_DARK, Vector3(-PI * 0.5, 0, 0))
	for sx in [-1.0, 1.0]:
		box(root, Vector3(w * 0.34, 0.5, l * 0.94), Vector3(sx * w * 0.38, 1.25, 0), CN_DARK)   # skirts
		box(root, Vector3(w * 0.36, 0.08, l * 0.96), Vector3(sx * w * 0.38, 1.55, 0), CN_BODY)
		box(root, Vector3(w * 0.1, 0.09, l * 0.6), Vector3(sx * w * 0.5, 1.55, 0), CN_RED)   # thin red stripe along the edge
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.7, -0.2)
	root.add_child(turret)
	box(turret, Vector3(w * 0.58, 0.75, l * 0.42), Vector3(0, 0.38, 0), CN_BODY)
	prism(turret, Vector3(w * 0.58, 0.3, l * 0.2), Vector3(0, 0.9, l * 0.12), CN_DARK, Vector3(-PI * 0.5, 0, 0))
	box(turret, Vector3(w * 0.5, 0.08, l * 0.3), Vector3(0, 0.8, -0.05), tc)
	for sx in [-1.0, 1.0]:
		cyl(turret, 0.1, 0.13, l * 0.65, Vector3(sx * 0.32, 0.4, l * 0.2 + l * 0.32), DARK, Vector3(PI * 0.5, 0, 0), 8)
		cyl(turret, 0.16, 0.16, 0.4, Vector3(sx * 0.32, 0.4, l * 0.2 + l * 0.62), DARK, Vector3(PI * 0.5, 0, 0), 8)
	box(turret, Vector3(0.5, 0.35, 0.5), Vector3(-w * 0.15, 0.95, -0.3), METAL)
	_star_decal(root, Vector3(0, 1.76, -l * 0.35), 0.45)
	root.set_meta("turret", turret)

static func _nuke_cannon(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.58
	tracks(root, l * 0.9, w * 0.26, 0.7, w * 0.4)
	box(root, Vector3(w * 0.6, 0.55, l * 0.85), Vector3(0, 0.95, 0), CN_BODY)
	box(root, Vector3(w * 0.62, 0.1, l * 0.3), Vector3(0, 1.25, l * 0.25), tc)
	# outriggers
	for sx in [-1.0, 1.0]:
		box(root, Vector3(w * 0.5, 0.15, 0.3), Vector3(sx * w * 0.5, 0.5, -l * 0.3), METAL)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.2, -0.4)
	root.add_child(turret)
	box(turret, Vector3(w * 0.55, 0.6, l * 0.35), Vector3(0, 0.3, 0), CN_DARK)
	var tilt := Node3D.new()
	tilt.position = Vector3(0, 0.6, 0)
	tilt.rotation.x = -0.75
	turret.add_child(tilt)
	cyl(tilt, 0.16, 0.26, l * 1.1, Vector3(0, 0, l * 0.5), DARK, Vector3(PI * 0.5, 0, 0), 10)
	cyl(tilt, 0.3, 0.3, 0.5, Vector3(0, 0, l * 1.0), METAL, Vector3(PI * 0.5, 0, 0), 10)
	cyl(tilt, 0.32, 0.32, 0.5, Vector3(0, 0, l * 0.1), CN_RED, Vector3(PI * 0.5, 0, 0), 10)
	var sym := Buildings.sphere(turret, 0.22, Vector3(0, 0.75, -0.3), Color(0.9, 0.95, 0.2))
	sym.name = "RadSymbol"
	root.set_meta("turret", turret)

static func _helix(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.22
	box(root, Vector3(w, 1.5, l * 0.7), Vector3(0, 1.6, 0), CN_BODY)
	prism(root, Vector3(w, 1.2, l * 0.16), Vector3(0, 1.5, l * 0.43), CN_DARK, Vector3(-PI * 0.5, 0, 0))
	box(root, Vector3(w * 0.9, 0.5, l * 0.14), Vector3(0, 2.1, l * 0.34), GLASS)
	box(root, Vector3(w * 1.02, 0.25, l * 0.55), Vector3(0, 1.0, -0.05), tc)
	box(root, Vector3(w * 0.4, 0.5, l * 0.3), Vector3(0, 1.6, -l * 0.5), CN_BODY)     # tail boom
	box(root, Vector3(0.08, 0.9, l * 0.1), Vector3(0, 2.2, -l * 0.62), CN_RED)         # fin
	box(root, Vector3(w * 1.4, 0.06, l * 0.08), Vector3(0, 1.9, -l * 0.6), CN_DARK)
	for sx in [-1.0, 1.0]:
		box(root, Vector3(0.06, 0.5, 0.06), Vector3(sx * w * 0.42, 0.6, l * 0.15), METAL)
		box(root, Vector3(0.06, 0.5, 0.06), Vector3(sx * w * 0.42, 0.6, -l * 0.15), METAL)
		box(root, Vector3(0.06, 0.06, l * 0.5), Vector3(sx * w * 0.42, 0.35, 0), METAL)   # skids
	# coaxial rotors: two stacked rotor nodes on the same mast
	cyl(root, 0.14, 0.14, 0.9, Vector3(0, 2.8, 0), METAL, Vector3.ZERO, 6)
	_rotor(root, "RotorMain", Vector3(0, 2.75, 0), l * 0.45, 2)
	_rotor(root, "RotorTop", Vector3(0, 3.15, 0), l * 0.45, 2)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.0, l * 0.3)
	root.add_child(turret)
	cyl(turret, 0.2, 0.2, 0.25, Vector3.ZERO, METAL, Vector3.ZERO, 8)
	for i in range(3):
		var a := i * TAU / 3.0
		box(turret, Vector3(0.07, 0.07, 0.9), Vector3(sin(a) * 0.09, -0.05 + cos(a) * 0.09, 0.45), DARK)
	root.set_meta("turret", turret)
	_star_decal(root, Vector3(0, 2.36, -0.05), 0.45)

# ---------------------------------------------------------------------------
# GLA vehicles
# ---------------------------------------------------------------------------
static func _pickup(root: Node3D, tc: Color, l: float, body: Color) -> void:
	var w := l * 0.48
	box(root, Vector3(w, 0.45, l * 0.95), Vector3(0, 0.75, 0), body.darkened(0.2))
	box(root, Vector3(w * 0.96, 0.85, l * 0.3), Vector3(0, 1.35, l * 0.12), body)        # cab
	box(root, Vector3(w * 0.9, 0.4, l * 0.28), Vector3(0, 1.55, l * 0.12), GLASS)
	box(root, Vector3(w * 1.0, 0.08, l * 0.32), Vector3(0, 1.8, l * 0.12), tc)
	box(root, Vector3(w * 0.95, 0.4, l * 0.22), Vector3(0, 1.0, l * 0.38), body.darkened(0.1))   # hood
	box(root, Vector3(w * 1.0, 0.5, l * 0.4), Vector3(0, 1.05, -l * 0.28), body)          # open bed walls
	box(root, Vector3(w * 0.8, 0.3, l * 0.34), Vector3(0, 1.15, -l * 0.28), Color(0.15, 0.13, 0.11))
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			wheel(root, 0.4, 0.28, Vector3(sx * w * 0.5, 0.4, sz * l * 0.3), "Wheel%s%s" % ["L" if sx < 0 else "R", "F" if sz > 0 else "B"])

static func _technical(root: Node3D, tc: Color, l: float) -> void:
	_pickup(root, tc, l, GLA_BODY)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.4, -l * 0.24)
	root.add_child(turret)
	cyl(turret, 0.06, 0.06, 0.6, Vector3(0, 0.25, 0), METAL, Vector3.ZERO, 6)
	box(turret, Vector3(0.25, 0.22, 0.4), Vector3(0, 0.6, 0), DARK)
	box(turret, Vector3(0.08, 0.08, 1.0), Vector3(0, 0.62, 0.55), DARK)
	box(turret, Vector3(0.3, 0.12, 0.1), Vector3(0, 0.55, -0.2), tc)
	root.set_meta("turret", turret)
	# a couple of jerry cans and a spare tyre
	box(root, Vector3(0.3, 0.35, 0.2), Vector3(-l * 0.16, 1.4, -l * 0.42), Color(0.35, 0.4, 0.3))
	cyl(root, 0.35, 0.35, 0.2, Vector3(l * 0.14, 1.45, -l * 0.42), RUBBER, Vector3(PI * 0.5, 0, 0), 10)

static func _scorpion(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.6
	tracks(root, l * 0.9, w * 0.26, 0.7, w * 0.4)
	box(root, Vector3(w * 0.6, 0.5, l * 0.85), Vector3(0, 0.95, 0), GLA_BODY)
	prism(root, Vector3(w * 0.6, 0.35, l * 0.28), Vector3(0, 1.38, l * 0.32), GLA_DARK, Vector3(-PI * 0.5, 0, 0))
	# spikes / junk plating
	for i in range(3):
		box(root, Vector3(w * 0.66, 0.06, 0.3), Vector3(0, 1.22, -l * 0.3 + i * l * 0.22), GLA_RUST)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.2, -0.15)
	root.add_child(turret)
	box(turret, Vector3(w * 0.42, 0.45, l * 0.34), Vector3(0, 0.22, 0), GLA_BODY)
	box(turret, Vector3(w * 0.36, 0.08, l * 0.24), Vector3(0, 0.5, -0.05), tc)
	cyl(turret, 0.08, 0.1, l * 0.62, Vector3(0, 0.25, l * 0.17 + l * 0.31), DARK, Vector3(PI * 0.5, 0, 0), 8)
	var rocket := cyl(turret, 0.09, 0.09, 0.9, Vector3(w * 0.26, 0.42, 0.1), Color(0.85, 0.85, 0.8), Vector3(PI * 0.5, 0, 0), 6)
	rocket.name = "Missile0"
	root.set_meta("turret", turret)

static func _quad_cannon(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.5
	box(root, Vector3(w, 0.5, l * 0.95), Vector3(0, 0.75, 0), GLA_DARK)
	box(root, Vector3(w * 0.95, 0.8, l * 0.24), Vector3(0, 1.3, l * 0.33), GLA_BODY)     # cab
	box(root, Vector3(w * 0.9, 0.35, l * 0.22), Vector3(0, 1.5, l * 0.33), GLASS)
	box(root, Vector3(w * 1.0, 0.3, l * 0.5), Vector3(0, 1.15, -l * 0.18), GLA_BODY)
	for sz in [-1.0, 0.0, 1.0]:
		for sx in [-1.0, 1.0]:
			wheel(root, 0.4, 0.3, Vector3(sx * w * 0.5, 0.4, sz * l * 0.32), "Wheel%s%d" % ["L" if sx < 0 else "R", int(sz + 1)])
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.3, -l * 0.2)
	root.add_child(turret)
	cyl(turret, 0.5, 0.55, 0.3, Vector3(0, 0.15, 0), METAL, Vector3.ZERO, 10)
	var tilt := Node3D.new()
	tilt.position = Vector3(0, 0.55, 0)
	tilt.rotation.x = -0.35
	turret.add_child(tilt)
	box(tilt, Vector3(0.9, 0.5, 0.6), Vector3(0, 0, 0), GLA_DARK)
	for i in range(4):
		cyl(tilt, 0.06, 0.06, l * 0.45, Vector3(-0.3 + (i % 2) * 0.6, -0.12 + (i / 2) * 0.24, l * 0.28), DARK, Vector3(PI * 0.5, 0, 0), 6)
	box(tilt, Vector3(0.5, 0.15, 0.1), Vector3(0, 0.32, -0.2), tc)
	root.set_meta("turret", turret)

static func _rocket_buggy(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.5
	box(root, Vector3(w * 0.8, 0.35, l * 0.8), Vector3(0, 0.7, 0), GLA_BODY)
	box(root, Vector3(w * 0.6, 0.4, l * 0.3), Vector3(0, 1.05, l * 0.15), GLA_DARK)
	box(root, Vector3(w * 0.55, 0.25, l * 0.1), Vector3(0, 1.25, l * 0.22), GLASS)
	# roll cage
	for sx in [-1.0, 1.0]:
		box(root, Vector3(0.06, 0.9, 0.06), Vector3(sx * w * 0.3, 1.3, l * 0.05), METAL)
	box(root, Vector3(w * 0.66, 0.06, 0.06), Vector3(0, 1.75, l * 0.05), METAL)
	for sz in [-1.0, 1.0]:
		for sx in [-1.0, 1.0]:
			wheel(root, 0.45, 0.32, Vector3(sx * w * 0.55, 0.45, sz * l * 0.3), "Wheel%s%s" % ["L" if sx < 0 else "R", "F" if sz > 0 else "B"])
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.0, -l * 0.25)
	root.add_child(turret)
	var tilt := Node3D.new()
	tilt.position = Vector3(0, 0.35, 0)
	tilt.rotation.x = -0.55
	turret.add_child(tilt)
	box(tilt, Vector3(w * 0.7, 0.55, l * 0.4), Vector3(0, 0, 0), Color(0.22, 0.23, 0.26))
	for i in range(6):
		var m := cyl(tilt, 0.07, 0.07, l * 0.36, Vector3(-0.28 + (i % 3) * 0.28, -0.15 + (i / 3) * 0.3, l * 0.05), Color(0.85, 0.85, 0.8), Vector3(PI * 0.5, 0, 0), 6)
		m.name = "Missile%d" % i
	box(tilt, Vector3(w * 0.5, 0.1, 0.1), Vector3(0, 0.33, -0.15), tc)
	root.set_meta("turret", turret)

static func _toxin_tractor(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.5
	box(root, Vector3(w * 0.7, 0.6, l * 0.8), Vector3(0, 0.9, 0), GLA_BODY)
	box(root, Vector3(w * 0.6, 0.7, l * 0.25), Vector3(0, 1.5, l * 0.05), GLA_DARK)     # cab
	box(root, Vector3(w * 0.55, 0.3, l * 0.22), Vector3(0, 1.65, l * 0.06), GLASS)
	box(root, Vector3(w * 0.62, 0.08, l * 0.28), Vector3(0, 1.88, l * 0.05), tc)
	# toxin tank on the back
	var tank := cyl(root, 0.55, 0.55, l * 0.35, Vector3(0, 1.45, -l * 0.28), Color(0.35, 0.6, 0.25), Vector3(PI * 0.5, 0, 0), 12)
	tank.name = "ToxinTank"
	cyl(root, 0.08, 0.08, 0.5, Vector3(0, 2.1, -l * 0.28), METAL, Vector3.ZERO, 6)
	# big rear wheels, small front
	for sx in [-1.0, 1.0]:
		wheel(root, 0.7, 0.4, Vector3(sx * w * 0.5, 0.7, -l * 0.22), "Wheel%sB" % ("L" if sx < 0 else "R"))
		wheel(root, 0.35, 0.25, Vector3(sx * w * 0.45, 0.35, l * 0.33), "Wheel%sF" % ("L" if sx < 0 else "R"))
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.2, l * 0.35)
	root.add_child(turret)
	cyl(turret, 0.1, 0.1, l * 0.3, Vector3(0, 0, l * 0.12), METAL, Vector3(PI * 0.5, 0, 0), 8)
	var nozzle := cyl(turret, 0.2, 0.1, 0.3, Vector3(0, 0, l * 0.29), Color(0.5, 0.9, 0.3), Vector3(PI * 0.5, 0, 0), 8)
	nozzle.name = "Nozzle"
	root.set_meta("turret", turret)

static func _marauder(root: Node3D, tc: Color, l: float) -> void:
	_tank(root, tc, l, true, GLA_BODY, GLA_DARK)
	var w := l * 0.62
	# welded-on junk: plates and spikes
	for i in range(4):
		box(root, Vector3(0.3, 0.5, 0.25), Vector3((-0.75 + (i % 2) * 1.5) * w * 0.3, 1.5, -l * 0.3 + (i / 2) * l * 0.5), GLA_RUST)
	var t := root.get_meta("turret") as Node3D
	box(t, Vector3(w * 0.66, 0.1, 0.2), Vector3(0, 0.5, -l * 0.18), GLA_RUST)
	for i in range(3):
		var spike := cyl(t, 0.0, 0.06, 0.4, Vector3(-0.3 + i * 0.3, 0.75, -0.25), METAL, Vector3.ZERO, 5)
		spike.rotation.x = -0.4

static func _scud_launcher(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.5
	box(root, Vector3(w, 0.5, l * 0.95), Vector3(0, 0.75, 0), GLA_DARK)
	box(root, Vector3(w * 0.95, 0.8, l * 0.22), Vector3(0, 1.3, l * 0.34), GLA_BODY)     # cab
	box(root, Vector3(w * 0.9, 0.35, l * 0.2), Vector3(0, 1.5, l * 0.34), GLASS)
	box(root, Vector3(w * 1.0, 0.1, l * 0.24), Vector3(0, 1.75, l * 0.34), tc)
	for sz in [-1.0, -0.33, 0.33, 1.0]:
		for sx in [-1.0, 1.0]:
			wheel(root, 0.42, 0.3, Vector3(sx * w * 0.5, 0.42, sz * l * 0.34), "Wheel%s%d" % ["L" if sx < 0 else "R", int(sz * 1.5 + 1.5)])
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.0, -l * 0.3)
	root.add_child(turret)
	var tilt := Node3D.new()
	tilt.position = Vector3(0, 0.2, 0)
	tilt.rotation.x = -1.0
	turret.add_child(tilt)
	box(tilt, Vector3(w * 0.5, 0.4, l * 0.7), Vector3(0, 0, l * 0.25), METAL)
	var m := cyl(tilt, 0.3, 0.3, l * 0.75, Vector3(0, 0.45, l * 0.25), Color(0.55, 0.5, 0.4), Vector3(PI * 0.5, 0, 0), 10)
	m.name = "Missile0"
	cyl(tilt, 0.0, 0.3, 0.8, Vector3(0, 0.45, l * 0.65), Color(0.3, 0.6, 0.2), Vector3(PI * 0.5, 0, 0), 10)
	root.set_meta("turret", turret)

static func _bomb_truck(root: Node3D, tc: Color, l: float) -> void:
	_pickup(root, tc, l, Color(0.55, 0.5, 0.42))
	# barrels in the bed under a tarp
	for i in range(3):
		cyl(root, 0.28, 0.28, 0.6, Vector3(-0.5 + i * 0.5, 1.45, -l * 0.28), Color(0.7, 0.2, 0.15), Vector3.ZERO, 8)
	box(root, Vector3(l * 0.46, 0.06, l * 0.36), Vector3(0, 1.8, -l * 0.28), Color(0.35, 0.45, 0.3))
	var lamp := Buildings.sphere(root, 0.1, Vector3(0, 1.9, -l * 0.44), Color(1.0, 0.2, 0.1))
	lamp.name = "LightBeacon"

# ---------------------------------------------------------------------------
# Aircraft
# ---------------------------------------------------------------------------
static func _rotor(parent: Node3D, nm: String, pos: Vector3, r: float, blades: int, tail := false) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	for i in range(blades):
		var b: MeshInstance3D
		if tail:
			b = box(n, Vector3(0.06, r * 2.0, 0.16), Vector3.ZERO, DARK)
			b.rotation.x = i * PI / blades
		else:
			b = box(n, Vector3(r * 2.0, 0.05, 0.22), Vector3.ZERO, DARK)
			b.rotation.y = i * PI / blades
	Buildings.sphere(n, 0.18 if not tail else 0.1, Vector3.ZERO, METAL)
	return n

static func _comanche(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.18
	box(root, Vector3(w, 1.1, l * 0.5), Vector3(0, 1.4, l * 0.05), BODY)              # fuselage
	prism(root, Vector3(w, 0.9, l * 0.2), Vector3(0, 1.4, l * 0.4), BODY_DARK, Vector3(-PI * 0.5, 0, 0))   # nose
	box(root, Vector3(w * 0.9, 0.5, l * 0.16), Vector3(0, 1.95, l * 0.2), GLASS)     # canopy
	box(root, Vector3(w * 0.35, 0.4, l * 0.5), Vector3(0, 1.3, -l * 0.42), BODY)     # tail boom
	box(root, Vector3(0.08, 0.9, l * 0.12), Vector3(0, 1.9, -l * 0.62), tc)          # fin (team colour)
	box(root, Vector3(w * 1.6, 0.06, l * 0.1), Vector3(0, 1.6, -l * 0.6), BODY_DARK) # stabiliser
	for sx in [-1.0, 1.0]:
		box(root, Vector3(l * 0.14, 0.08, 0.5), Vector3(sx * (w * 0.5 + l * 0.07), 1.35, l * 0.05), BODY_DARK)   # stub wing
		cyl(root, 0.18, 0.18, 0.9, Vector3(sx * (w * 0.5 + l * 0.13), 1.2, l * 0.05), METAL, Vector3(PI * 0.5, 0, 0), 8).name = "Pod%d" % int(sx + 1)
		box(root, Vector3(0.06, 0.5, 0.06), Vector3(sx * w * 0.4, 0.55, l * 0.1), METAL)
		box(root, Vector3(0.06, 0.06, l * 0.4), Vector3(sx * w * 0.4, 0.3, l * 0.05), METAL)   # skids
	cyl(root, 0.12, 0.12, 0.5, Vector3(0, 2.2, l * 0.02), METAL, Vector3.ZERO, 6)
	_rotor(root, "RotorMain", Vector3(0, 2.45, l * 0.02), l * 0.42, 2)
	_rotor(root, "RotorTail", Vector3(w * 0.25, 1.9, -l * 0.62), 0.45, 3, true)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.0, l * 0.3)
	root.add_child(turret)
	cyl(turret, 0.2, 0.2, 0.25, Vector3.ZERO, METAL, Vector3.ZERO, 8)
	box(turret, Vector3(0.1, 0.1, 0.8), Vector3(0, -0.05, 0.4), DARK)   # chin gun follows the target
	root.set_meta("turret", turret)
	for i in range(4):
		var sx := -1.0 if i % 2 == 0 else 1.0
		var m := cyl(root, 0.07, 0.07, 0.6, Vector3(sx * (w * 0.5 + l * 0.13) + (0.12 if i < 2 else -0.12) * sx, 1.2 + (0.12 if i < 2 else -0.12), l * 0.05 + 0.5), Color(0.85, 0.85, 0.8), Vector3(PI * 0.5, 0, 0), 6)
		m.name = "Missile%d" % i

static func _chinook(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.2
	box(root, Vector3(w, 1.6, l * 0.75), Vector3(0, 1.6, 0), BODY)
	prism(root, Vector3(w, 1.3, l * 0.14), Vector3(0, 1.5, l * 0.44), BODY_DARK, Vector3(-PI * 0.5, 0, 0))
	box(root, Vector3(w * 0.9, 0.5, l * 0.12), Vector3(0, 2.1, l * 0.36), GLASS)
	box(root, Vector3(w * 1.02, 0.25, l * 0.6), Vector3(0, 1.0, -0.05), tc)        # team stripe low
	box(root, Vector3(w * 0.6, 0.9, l * 0.16), Vector3(0, 2.7, -l * 0.34), BODY)     # rear pylon
	box(root, Vector3(w * 0.6, 0.5, l * 0.16), Vector3(0, 2.5, l * 0.22), BODY)      # front pylon
	var ramp := box(root, Vector3(w * 0.9, 0.12, l * 0.16), Vector3(0, 0.9, -l * 0.42), BODY_DARK)
	ramp.name = "Ramp"
	for sx in [-1.0, 1.0]:
		wheel(root, 0.3, 0.25, Vector3(sx * w * 0.55, 0.35, l * 0.25), "WheelF%d" % int(sx + 1))
		wheel(root, 0.3, 0.25, Vector3(sx * w * 0.55, 0.35, -l * 0.25), "WheelB%d" % int(sx + 1))
	_rotor(root, "RotorFront", Vector3(0, 2.85, l * 0.22), l * 0.36, 3)
	_rotor(root, "RotorRear", Vector3(0, 3.25, -l * 0.34), l * 0.36, 3)

static func _jet(root: Node3D, tc: Color, l: float, kind: String) -> void:
	var dark := kind == "stealth"
	var body := Color(0.2, 0.2, 0.22) if dark else Color(0.58, 0.6, 0.63)
	var body2 := Color(0.14, 0.14, 0.16) if dark else Color(0.44, 0.46, 0.5)
	var w := l * 0.11
	var y := 1.05
	# fuselage: main tube, spine, nose cone, canopy, intakes
	box(root, Vector3(w, w * 0.8, l * 0.5), Vector3(0, y, l * 0.02), body)
	box(root, Vector3(w * 0.7, w * 0.35, l * 0.42), Vector3(0, y + w * 0.5, -l * 0.08), body2)      # spine
	prism(root, Vector3(w, w * 0.7, l * 0.3), Vector3(0, y - w * 0.05, l * 0.42), body2, Vector3(-PI * 0.5, 0, 0))   # nose
	box(root, Vector3(w * 0.6, w * 0.45, l * 0.15), Vector3(0, y + w * 0.6, l * 0.16), GLASS if not dark else Color(0.28, 0.32, 0.38))  # canopy
	prism(root, Vector3(w * 0.6, w * 0.4, l * 0.08), Vector3(0, y + w * 0.6, l * 0.27), GLASS if not dark else Color(0.28, 0.32, 0.38), Vector3(-PI * 0.5, 0, 0))
	for sx in [-1.0, 1.0]:
		box(root, Vector3(w * 0.4, w * 0.55, l * 0.22), Vector3(sx * w * 0.65, y - w * 0.1, l * 0.08), body2)   # intakes
		box(root, Vector3(w * 0.3, w * 0.35, 0.08), Vector3(sx * w * 0.65, y - w * 0.1, l * 0.19), DARK)
	var span := l * 0.78 if kind != "aurora" else l * 0.62
	if kind == "mig":
		body = CN_BODY.lightened(0.15)
		body2 = CN_DARK
	var eng_pos: Array = []
	match kind:
		"raptor":
			# trapezoid wing (two slabs), tailplane, twin canted fins, two engines
			box(root, Vector3(span, 0.09, l * 0.2), Vector3(0, y - w * 0.15, -l * 0.1), body)
			box(root, Vector3(span * 0.62, 0.1, l * 0.16), Vector3(0, y - w * 0.15, l * 0.06), body)
			box(root, Vector3(span * 0.95, 0.06, l * 0.1), Vector3(0, y - w * 0.15, -l * 0.31), body2)
			for sx in [-1.0, 1.0]:
				box(root, Vector3(span * 0.3, 0.05, l * 0.05), Vector3(sx * span * 0.3, y - w * 0.12, -l * 0.22), tc)   # team stripe on the wings
				var fin := box(root, Vector3(0.07, l * 0.12, l * 0.15), Vector3(sx * w * 0.5, y + l * 0.07, -l * 0.25), body2)
				fin.rotation.z = -sx * 0.4
				box(root, Vector3(0.09, l * 0.05, l * 0.06), Vector3(sx * w * 0.5, y + l * 0.1, -l * 0.28), tc).rotation.z = -sx * 0.4
				eng_pos.append(Vector3(sx * w * 0.3, y - w * 0.05, -l * 0.32))
		"stealth":
			# faceted arrowhead with V-tail, weapons inside
			box(root, Vector3(span, 0.1, l * 0.3), Vector3(0, y - w * 0.15, -l * 0.14), body)
			box(root, Vector3(span * 0.62, 0.12, l * 0.24), Vector3(0, y - w * 0.15, l * 0.05), body)
			box(root, Vector3(span * 0.3, 0.14, l * 0.2), Vector3(0, y - w * 0.15, l * 0.22), body2)
			for sx in [-1.0, 1.0]:
				var fin := box(root, Vector3(0.07, l * 0.1, l * 0.13), Vector3(sx * w * 0.5, y + l * 0.04, -l * 0.26), body2)
				fin.rotation.z = -sx * 0.7
				box(root, Vector3(span * 0.25, 0.05, l * 0.04), Vector3(sx * span * 0.32, y - w * 0.11, -l * 0.26), tc)
			eng_pos.append(Vector3(0, y, -l * 0.3))
		"mig":
			# swept delta wings with red tips, twin canted fins, two engines, nose intake
			box(root, Vector3(span, 0.09, l * 0.26), Vector3(0, y - w * 0.15, -l * 0.08), body)
			box(root, Vector3(span * 0.5, 0.1, l * 0.18), Vector3(0, y - w * 0.15, l * 0.1), body)
			for sx in [-1.0, 1.0]:
				box(root, Vector3(span * 0.16, 0.06, l * 0.12), Vector3(sx * span * 0.42, y - w * 0.13, -l * 0.1), CN_RED)
				var fin := box(root, Vector3(0.07, l * 0.12, l * 0.14), Vector3(sx * w * 0.45, y + l * 0.07, -l * 0.27), body2)
				fin.rotation.z = -sx * 0.25
				box(root, Vector3(0.09, l * 0.05, l * 0.06), Vector3(sx * w * 0.45, y + l * 0.1, -l * 0.3), tc).rotation.z = -sx * 0.25
				eng_pos.append(Vector3(sx * w * 0.3, y - w * 0.05, -l * 0.32))
			_star_decal(root, Vector3(0, y + w * 0.62, -l * 0.16), 0.35)
		"aurora":
			# sleek dart: slim swept wing far back, single fin, one big engine
			box(root, Vector3(span, 0.07, l * 0.18), Vector3(0, y - w * 0.15, -l * 0.2), body)
			box(root, Vector3(span * 0.5, 0.08, l * 0.14), Vector3(0, y - w * 0.15, -l * 0.06), body)
			box(root, Vector3(0.07, l * 0.11, l * 0.14), Vector3(0, y + l * 0.06, -l * 0.28), tc)
			eng_pos.append(Vector3(0, y, -l * 0.3))
	# engines + afterburner flames (Puppet scales "Afterburner*" with speed)
	for i in range(eng_pos.size()):
		var ep: Vector3 = eng_pos[i]
		var er := w * (0.24 if eng_pos.size() > 1 else 0.36)
		cyl(root, er, er * 1.1, l * 0.2, ep, DARK, Vector3(PI * 0.5, 0, 0), 8).name = "Engine%d" % i
		cyl(root, er * 0.7, er * 0.85, 0.1, ep + Vector3(0, 0, -l * 0.1), Color(0.9, 0.5, 0.2), Vector3(PI * 0.5, 0, 0), 8)
		var flame := cyl(root, er * 0.15, er * 0.75, l * 0.22, ep + Vector3(0, 0, -l * 0.2), Color(1.0, 0.6, 0.2, 0.85), Vector3(PI * 0.5, 0, 0), 8)
		flame.name = "Afterburner%d" % i
		var fm := flame.material_override as StandardMaterial3D
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.emission_enabled = true
		fm.emission = Color(1.0, 0.5, 0.15)
		fm.emission_energy_multiplier = 2.5
		flame.visible = false
	# missiles under the wings: "Missile0..n" (Puppet hides them as ammo is spent)
	var nmis := 4 if kind == "raptor" else (2 if kind == "stealth" or kind == "mig" else 1)
	for i in range(nmis):
		var sx := -1.0 if i % 2 == 0 else 1.0
		var off := (1 + i / 2) * span * 0.18
		var mp := Vector3(sx * off, y - w * 0.45, -l * 0.02) if kind != "aurora" else Vector3(0, y - w * 0.6, 0)
		var m := cyl(root, 0.1, 0.1, l * 0.16 if kind != "aurora" else l * 0.22, mp, Color(0.85, 0.85, 0.8) if kind != "mig" else Color(0.9, 0.5, 0.2), Vector3(PI * 0.5, 0, 0), 6)
		m.name = "Missile%d" % i
		if kind == "aurora":
			m.scale = Vector3(2.2, 1.0, 2.2)
	# landing gear (retracts in flight): "Gear*"
	for gp in [Vector3(0, 0.45, l * 0.25), Vector3(-w * 0.5, 0.45, -l * 0.1), Vector3(w * 0.5, 0.45, -l * 0.1)]:
		var gear := Node3D.new()
		gear.name = "Gear"
		root.add_child(gear)
		box(gear, Vector3(0.07, 0.7, 0.07), gp, METAL)
		cyl(gear, 0.16, 0.16, 0.12, gp - Vector3(0, 0.35, 0), RUBBER, Vector3(0, 0, PI * 0.5), 8)

## A-10 Warthog for the strike flyover (not a playable unit): straight wings, twin
## tail-mounted engines, twin fins, the big nose gun.
static func a10(team: int) -> Node3D:
	var root := Node3D.new()
	var tc := _tc(team)
	var l := 8.0
	var body := Color(0.45, 0.48, 0.45)
	var body2 := Color(0.32, 0.35, 0.33)
	var w := 1.1
	var y := 1.05
	box(root, Vector3(w, w * 0.9, l * 0.55), Vector3(0, y, 0), body)
	prism(root, Vector3(w, w * 0.8, l * 0.22), Vector3(0, y - 0.05, l * 0.38), body2, Vector3(-PI * 0.5, 0, 0))
	box(root, Vector3(w * 0.7, w * 0.5, l * 0.16), Vector3(0, y + w * 0.6, l * 0.14), GLASS)
	cyl(root, 0.16, 0.16, 1.8, Vector3(0, y - 0.25, l * 0.5), DARK, Vector3(PI * 0.5, 0, 0), 8).name = "Gun"
	box(root, Vector3(l * 0.95, 0.12, l * 0.16), Vector3(0, y - 0.1, 0.2), body)          # straight wing
	for sx in [-1.0, 1.0]:
		box(root, Vector3(l * 0.4, 0.05, l * 0.05), Vector3(sx * l * 0.28, y - 0.06, 0.1), tc)
		var eng := cyl(root, 0.42, 0.42, 2.2, Vector3(sx * 1.1, y + 0.7, -l * 0.28), body2, Vector3(PI * 0.5, 0, 0), 10)
		eng.name = "Engine%d" % int(sx + 1)
		cyl(root, 0.3, 0.3, 0.2, Vector3(sx * 1.1, y + 0.7, -l * 0.42), Color(0.9, 0.5, 0.2), Vector3(PI * 0.5, 0, 0), 8)
		box(root, Vector3(0.1, 1.4, l * 0.12), Vector3(sx * 1.6, y + 1.0, -l * 0.44), body2)   # twin fins
	box(root, Vector3(3.6, 0.08, l * 0.1), Vector3(0, y + 0.3, -l * 0.44), body)               # tailplane
	for i in range(4):
		var sx := -1.0 if i % 2 == 0 else 1.0
		cyl(root, 0.1, 0.1, 1.2, Vector3(sx * (1.4 + (i / 2) * 1.0), y - 0.45, 0.2), Color(0.85, 0.85, 0.8), Vector3(PI * 0.5, 0, 0), 6).name = "Missile%d" % i
	return root

## Cargo plane for the supply drop flyover (not a playable unit).
static func cargo_plane(team: int) -> Node3D:
	var root := Node3D.new()
	var tc := _tc(team)
	var l := 12.0
	var body := Color(0.5, 0.52, 0.5)
	var w := 1.6
	box(root, Vector3(w, w * 1.1, l * 0.62), Vector3(0, 1.2, 0), body)
	prism(root, Vector3(w, w * 0.9, l * 0.18), Vector3(0, 1.1, l * 0.4), body.darkened(0.15), Vector3(-PI * 0.5, 0, 0))
	box(root, Vector3(w * 0.9, 0.5, l * 0.12), Vector3(0, 1.85, l * 0.3), GLASS)
	box(root, Vector3(w * 0.5, w * 0.9, l * 0.2), Vector3(0, 1.4, -l * 0.4), body)       # tail cone
	box(root, Vector3(0.08, 2.4, l * 0.14), Vector3(0, 2.8, -l * 0.42), tc)              # fin
	box(root, Vector3(l * 0.32, 0.06, l * 0.1), Vector3(0, 3.9, -l * 0.42), body)         # T-tail
	box(root, Vector3(l * 0.95, 0.1, l * 0.14), Vector3(0, 2.0, l * 0.02), body)          # high wing
	for i in range(4):
		var x := (-1.5 + i) * l * 0.2
		var eng := cyl(root, 0.3, 0.3, 1.6, Vector3(x, 1.7, l * 0.06), DARK, Vector3(PI * 0.5, 0, 0), 8)
		eng.name = "Engine%d" % i
		var prop := Node3D.new()
		prop.name = "Propeller%d" % i
		prop.position = Vector3(x, 1.7, l * 0.13)
		root.add_child(prop)
		for k in range(3):
			var b := box(prop, Vector3(0.08, 1.4, 0.06), Vector3.ZERO, DARK)
			b.rotation.z = k * PI / 3.0
	return root

## Supply crate under a parachute.
static func supply_crate() -> Node3D:
	var root := Node3D.new()
	box(root, Vector3(1.4, 1.2, 1.4), Vector3(0, 0.6, 0), Color(0.78, 0.62, 0.3))
	box(root, Vector3(1.5, 0.15, 0.3), Vector3(0, 0.6, 0), Color(0.25, 0.25, 0.28))
	var chute := Node3D.new()
	chute.name = "Chute"
	root.add_child(chute)
	var canopy := Buildings.sphere(chute, 2.2, Vector3(0, 4.6, 0), Color(0.95, 0.95, 0.9))
	canopy.scale = Vector3(1.0, 0.55, 1.0)
	for i in range(4):
		var ang := i * PI * 0.5 + PI * 0.25
		var line := box(chute, Vector3(0.03, 3.6, 0.03), Vector3(sin(ang) * 0.9, 2.5, cos(ang) * 0.9), Color(0.85, 0.85, 0.85))
		line.rotation = Vector3(-cos(ang) * 0.3, 0, sin(ang) * 0.3)
	return root

# ---------------------------------------------------------------------------
# Infantry: simple blocky soldier with swinging limbs
# ---------------------------------------------------------------------------
static func _soldier(root: Node3D, tc: Color, type: String) -> void:
	var uni := UNIFORM
	var fac := Data.faction_of(type)
	if fac == "china":
		uni = CN_UNIFORM
	elif fac == "gla":
		uni = GLA_UNIFORM
	if type == "pathfinder":
		uni = Color(0.3, 0.34, 0.24)
	elif type == "burton" or type == "black_lotus" or type == "jarmen_kell":
		uni = Color(0.15, 0.15, 0.17)
	elif type == "hacker":
		uni = Color(0.25, 0.28, 0.35)
	elif type == "worker":
		uni = Color(0.55, 0.5, 0.42)
	var s := 1.0
	box(root, Vector3(0.5 * s, 0.6 * s, 0.3 * s), Vector3(0, 1.15 * s, 0), uni)          # torso
	box(root, Vector3(0.54 * s, 0.34 * s, 0.34 * s), Vector3(0, 1.28 * s, 0), tc)         # team-colour vest so they read at a glance
	box(root, Vector3(0.52 * s, 0.12 * s, 0.32 * s), Vector3(0, 0.98 * s, 0), DARK)      # belt
	Buildings.sphere(root, 0.17 * s, Vector3(0, 1.62 * s, 0), SKIN)                       # head
	match fac:
		"china":
			# peaked cap with a red band
			box(root, Vector3(0.4 * s, 0.14 * s, 0.4 * s), Vector3(0, 1.76 * s, 0), tc.darkened(0.25))
			box(root, Vector3(0.42 * s, 0.05 * s, 0.42 * s), Vector3(0, 1.7 * s, 0), CN_RED)
			box(root, Vector3(0.3 * s, 0.03 * s, 0.2 * s), Vector3(0, 1.7 * s, 0.25 * s), DARK)
		"gla":
			# head-wrap / shemagh
			box(root, Vector3(0.42 * s, 0.2 * s, 0.42 * s), Vector3(0, 1.7 * s, 0), Color(0.9, 0.85, 0.7) if type != "jarmen_kell" else Color(0.2, 0.2, 0.22))
			box(root, Vector3(0.44 * s, 0.05 * s, 0.44 * s), Vector3(0, 1.62 * s, 0), tc.darkened(0.2))
			if type == "terrorist":
				for sx in [-1.0, 1.0]:
					box(root, Vector3(0.1 * s, 0.35 * s, 0.1 * s), Vector3(sx * 0.15 * s, 1.25 * s, 0.2 * s), Color(0.8, 0.2, 0.1))
		_:
			box(root, Vector3(0.42 * s, 0.16 * s, 0.42 * s), Vector3(0, 1.75 * s, 0), tc.darkened(0.25))   # helmet in team colour
	for sx in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.name = "LegL" if sx < 0 else "LegR"
		leg.position = Vector3(sx * 0.13 * s, 0.85 * s, 0)
		root.add_child(leg)
		box(leg, Vector3(0.18 * s, 0.85 * s, 0.2 * s), Vector3(0, -0.42 * s, 0), uni.darkened(0.1))
		box(leg, Vector3(0.2 * s, 0.1 * s, 0.3 * s), Vector3(0, -0.85 * s, 0.05 * s), DARK)
		var arm := Node3D.new()
		arm.name = "ArmL" if sx < 0 else "ArmR"
		arm.position = Vector3(sx * 0.33 * s, 1.4 * s, 0)
		root.add_child(arm)
		box(arm, Vector3(0.14 * s, 0.6 * s, 0.16 * s), Vector3(0, -0.3 * s, 0), uni)
		Buildings.sphere(arm, 0.08 * s, Vector3(0, -0.62 * s, 0), SKIN)
	# weapon held in front
	var gun := Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0.15 * s, 1.2 * s, 0.3 * s)
	root.add_child(gun)
	match type:
		"missile_defender", "tank_hunter", "rpg_trooper":
			cyl(gun, 0.09, 0.09, 1.0, Vector3(0.1, 0.35, -0.2), DARK, Vector3(PI * 0.5, 0, 0), 8)   # launcher tube on the shoulder
		"pathfinder", "burton", "jarmen_kell":
			box(gun, Vector3(0.06, 0.08, 1.0), Vector3(0, 0, 0.2), DARK)
			cyl(gun, 0.03, 0.03, 0.2, Vector3(0, 0.06, 0.1), METAL, Vector3(PI * 0.5, 0, 0), 6)
		"hacker":
			# laptop held open in front
			box(gun, Vector3(0.45, 0.03, 0.3), Vector3(-0.15, -0.05, 0), Color(0.2, 0.2, 0.22))
			var screen := box(gun, Vector3(0.45, 0.3, 0.03), Vector3(-0.15, 0.1, 0.15), Color(0.3, 0.8, 1.0))
			screen.name = "Screen"
		"black_lotus":
			box(gun, Vector3(0.3, 0.03, 0.2), Vector3(-0.15, -0.05, 0), Color(0.2, 0.2, 0.22))
		"worker":
			# shovel over the shoulder
			cyl(gun, 0.03, 0.03, 1.1, Vector3(0.1, 0.4, -0.3), Color(0.5, 0.35, 0.2), Vector3(0.6, 0, 0), 6)
			box(gun, Vector3(0.22, 0.28, 0.03), Vector3(0.1, 0.95, -0.7), METAL)
		"terrorist":
			box(gun, Vector3(0.12, 0.12, 0.12), Vector3(0, 0, 0), Color(0.8, 0.2, 0.1))   # the trigger
		_:
			box(gun, Vector3(0.06, 0.1, 0.6), Vector3(0, 0, 0.1), DARK)
