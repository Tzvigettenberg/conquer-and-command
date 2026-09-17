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
const GLASS := Color(0.3, 0.55, 0.8)
const RUBBER := Color(0.12, 0.12, 0.13)
const SKIN := Color(0.85, 0.68, 0.55)
const UNIFORM := Color(0.36, 0.4, 0.3)

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
		_:
			box(root, Vector3(l * 0.5, l * 0.3, l), Vector3(0, l * 0.15, 0), tc)
	return root

# ---------------------------------------------------------------------------
# Ground vehicles
# ---------------------------------------------------------------------------
static func _dozer(root: Node3D, tc: Color, l: float) -> void:
	var w := l * 0.55
	tracks(root, l * 0.7, w * 0.25, 0.7, w * 0.42)
	box(root, Vector3(w * 0.7, 0.7, l * 0.62), Vector3(0, 1.0, -0.2), BODY)
	box(root, Vector3(w * 0.72, 0.16, l * 0.3), Vector3(0, 1.4, -0.9), tc)     # team-colour rear deck
	# cab with glass
	box(root, Vector3(w * 0.5, 0.9, l * 0.28), Vector3(0, 1.8, -0.35), BODY_DARK)
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

static func _tank(root: Node3D, tc: Color, l: float, heavy: bool) -> void:
	var w := l * 0.62
	tracks(root, l * 0.95, w * 0.26, 0.75, w * 0.4)
	box(root, Vector3(w * 0.62, 0.55, l * 0.9), Vector3(0, 1.0, 0), BODY)                       # hull
	prism(root, Vector3(w * 0.62, 0.35, l * 0.25), Vector3(0, 1.45, l * 0.35), BODY_DARK, Vector3(-PI * 0.5, 0, 0))  # glacis
	box(root, Vector3(w * 0.64, 0.1, l * 0.5), Vector3(0, 1.3, -0.2), BODY_DARK)
	if heavy:
		for sx in [-1.0, 1.0]:
			box(root, Vector3(0.1, 0.5, l * 0.8), Vector3(sx * w * 0.55, 0.95, 0), BODY_DARK)  # side skirts
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.3, -0.15)
	root.add_child(turret)
	var tw := w * 0.5 if not heavy else w * 0.58
	box(turret, Vector3(tw, 0.55, l * 0.4), Vector3(0, 0.28, 0), BODY)
	prism(turret, Vector3(tw, 0.25, l * 0.2), Vector3(0, 0.65, l * 0.1), BODY_DARK, Vector3(-PI * 0.5, 0, 0))
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
	box(root, Vector3(0.1, 0.1, 0.7), Vector3(0, 1.05, l * 0.32), DARK)   # chin gun

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
	var body := Color(0.2, 0.2, 0.22) if dark else Color(0.55, 0.57, 0.6)
	var body2 := Color(0.14, 0.14, 0.16) if dark else Color(0.42, 0.44, 0.48)
	var w := l * 0.12
	# fuselage + nose
	box(root, Vector3(w, w * 0.9, l * 0.55), Vector3(0, 1.0, 0), body)
	prism(root, Vector3(w, w * 0.8, l * 0.28), Vector3(0, 0.98, l * 0.41), body2, Vector3(-PI * 0.5, 0, 0))
	box(root, Vector3(w * 0.7, w * 0.45, l * 0.16), Vector3(0, 1.0 + w * 0.55, l * 0.12), GLASS if not dark else Color(0.25, 0.3, 0.35))
	var span := l * 0.75 if kind != "aurora" else l * 0.6
	match kind:
		"raptor":
			# one wide wing slab (swept look from a narrower leading-edge slab), twin canted fins, two engines
			box(root, Vector3(span, 0.08, l * 0.22), Vector3(0, 0.95, -l * 0.12), body)
			box(root, Vector3(span * 0.6, 0.09, l * 0.16), Vector3(0, 0.95, l * 0.02), body)
			box(root, Vector3(span * 0.9, 0.06, l * 0.08), Vector3(0, 0.95, -l * 0.3), body2)   # tailplane
			for sx in [-1.0, 1.0]:
				var fin := box(root, Vector3(0.06, l * 0.11, l * 0.14), Vector3(sx * w * 0.45, 1.0 + l * 0.07, -l * 0.26), tc)
				fin.rotation.z = -sx * 0.35
				cyl(root, w * 0.22, w * 0.26, l * 0.2, Vector3(sx * w * 0.28, 0.95, -l * 0.3), DARK, Vector3(PI * 0.5, 0, 0), 8).name = "Engine%d" % int(sx + 1)
		"stealth":
			# faceted arrowhead: wide slab tapering to the nose, V-tail
			box(root, Vector3(span, 0.08, l * 0.3), Vector3(0, 0.95, -l * 0.14), body)
			box(root, Vector3(span * 0.55, 0.1, l * 0.24), Vector3(0, 0.95, l * 0.06), body)
			box(root, Vector3(span * 0.25, 0.12, l * 0.2), Vector3(0, 0.95, l * 0.22), body2)
			for sx in [-1.0, 1.0]:
				var fin := box(root, Vector3(0.06, l * 0.1, l * 0.12), Vector3(sx * w * 0.5, 1.0 + l * 0.04, -l * 0.26), tc)
				fin.rotation.z = -sx * 0.7
		"aurora":
			# sleek dart: slim swept wing far back, single fin, big engine
			box(root, Vector3(span, 0.06, l * 0.18), Vector3(0, 0.95, -l * 0.2), body)
			box(root, Vector3(span * 0.5, 0.07, l * 0.14), Vector3(0, 0.95, -l * 0.06), body)
			box(root, Vector3(0.06, l * 0.1, l * 0.14), Vector3(0, 1.0 + l * 0.06, -l * 0.28), tc)
			cyl(root, w * 0.35, w * 0.4, l * 0.22, Vector3(0, 0.9, -l * 0.3), DARK, Vector3(PI * 0.5, 0, 0), 8).name = "Engine"
	# landing gear (visible when parked; small)
	for p in [Vector3(0, 0.45, l * 0.25), Vector3(-w * 0.35, 0.45, -l * 0.1), Vector3(w * 0.35, 0.45, -l * 0.1)]:
		box(root, Vector3(0.06, 0.6, 0.06), p, METAL).name = "Gear"
		cyl(root, 0.14, 0.14, 0.1, p - Vector3(0, 0.3, 0), RUBBER, Vector3(0, 0, PI * 0.5), 8).name = "GearWheel"

# ---------------------------------------------------------------------------
# Infantry: simple blocky soldier with swinging limbs
# ---------------------------------------------------------------------------
static func _soldier(root: Node3D, tc: Color, type: String) -> void:
	var uni := UNIFORM
	if type == "pathfinder":
		uni = Color(0.3, 0.34, 0.24)
	elif type == "burton":
		uni = Color(0.15, 0.15, 0.17)
	var s := 1.0
	box(root, Vector3(0.5 * s, 0.6 * s, 0.3 * s), Vector3(0, 1.15 * s, 0), uni)          # torso
	box(root, Vector3(0.52 * s, 0.2 * s, 0.32 * s), Vector3(0, 1.0 * s, 0), tc)           # belt / team band
	Buildings.sphere(root, 0.17 * s, Vector3(0, 1.62 * s, 0), SKIN)                       # head
	box(root, Vector3(0.4 * s, 0.14 * s, 0.4 * s), Vector3(0, 1.74 * s, 0), uni.darkened(0.2))   # helmet
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
		"missile_defender":
			cyl(gun, 0.09, 0.09, 1.0, Vector3(0.1, 0.35, -0.2), DARK, Vector3(PI * 0.5, 0, 0), 8)   # launcher tube on the shoulder
		"pathfinder", "burton":
			box(gun, Vector3(0.06, 0.08, 1.0), Vector3(0, 0, 0.2), DARK)
			cyl(gun, 0.03, 0.03, 0.2, Vector3(0, 0.06, 0.1), METAL, Vector3(PI * 0.5, 0, 0), 6)
		_:
			box(gun, Vector3(0.06, 0.1, 0.6), Vector3(0, 0, 0.1), DARK)
