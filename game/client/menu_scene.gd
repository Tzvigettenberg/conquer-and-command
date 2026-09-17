class_name MenuScene
extends Node3D
## Living backdrop behind the main menu (like Generals' shell map): a real map
## with a base, a tank column rolling down the road, a helicopter on patrol and
## a jet circling, seen from a slowly drifting camera.

var map_view: MapView
var cam: Camera3D
var t := 0.0
var movers: Array = []   # [{node, kind, ...}]

func _ready() -> void:
	var m := MapGen.build("desert4")
	map_view = MapView.new()
	add_child(map_view)
	map_view.setup(m)
	map_view.reveal_all()
	map_view.disable_fog()
	var base: Vector2 = m["starts"][0]
	# a base to look at
	var layout := [["command_center", Vector2(0, 0), 0.0], ["power_plant", Vector2(24, -4), 0.0], ["barracks", Vector2(-6, 24), 0.0],
		["war_factory", Vector2(26, 22), 0.0], ["supply_center", Vector2(-24, 6), 0.0], ["patriot", Vector2(30, -22), 0.0], ["airfield", Vector2(4, 46), 0.0]]
	for it in layout:
		var b := Visuals.make_model(it[0], 0)
		b.position = Vector3(base.x + it[1].x, 0, base.y + it[1].y)
		b.rotation.y = it[2]
		add_child(b)
		_animate_building(b)
	# tank column: along the lane between the barracks / war factory and the airfield,
	# then out toward the middle of the map (keeps clear of every structure above)
	var path: Array = [Vector3(base.x - 46, 0, base.y + 33), Vector3(base.x + 48, 0, base.y + 33), Vector3(base.x + 70, 0, base.y + 60), Vector3(base.x + 140, 0, base.y + 125)]
	var total := 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	for i in range(6):
		var typ := "crusader" if i % 3 != 2 else "humvee"
		var u := Visuals.make_model(typ, 0)
		add_child(u)
		movers.append({"node": u, "kind": "road", "path": path, "total": total, "off": i * 9.0, "side": (i % 2) * 3.4 - 1.7, "wheels": u.find_children("Wheel*", "Node3D", true, false)})
	# helicopter on patrol
	var heli := Visuals.make_model("comanche", 0)
	add_child(heli)
	movers.append({"node": heli, "kind": "orbit", "c": Vector3(base.x + 40, 16, base.y + 30), "r": 34.0, "speed": 0.25, "rotors": heli.find_children("Rotor*", "Node3D", true, false)})
	# jet high above
	var jet := Visuals.make_model("raptor", 0)
	add_child(jet)
	movers.append({"node": jet, "kind": "orbit", "c": Vector3(base.x + 60, 42, base.y + 60), "r": 90.0, "speed": 0.5, "rotors": []})
	# infantry squad idling by the barracks
	for i in range(4):
		var s := Visuals.make_model("ranger" if i < 3 else "missile_defender", 0)
		s.position = Vector3(base.x - 16 + i * 1.6, 0, base.y + 26)
		s.rotation.y = randf_range(-0.4, 0.4)
		add_child(s)
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 1.0
	cam.far = 1500.0
	add_child(cam)
	cam.current = true
	_place_camera(base)

func _animate_building(b: Node3D) -> void:
	if b.has_meta("anim"):
		set_meta("anims_%d" % b.get_instance_id(), b.get_meta("anim"))

func _place_camera(base: Vector2) -> void:
	set_meta("base", base)

func _process(dt: float) -> void:
	t += dt
	var base: Vector2 = get_meta("base", Vector2(64, 64))
	# slow drifting camera around the base
	var ang := 2.6 + t * 0.04
	var c := Vector3(base.x + 16 + cos(ang) * 44.0, 30.0 + sin(t * 0.2) * 3.0, base.y + 16 + sin(ang) * 44.0)
	cam.position = c
	cam.look_at(Vector3(base.x + 14, 2.0, base.y + 14), Vector3.UP)
	for mv in movers:
		var n: Node3D = mv["node"]
		match mv["kind"]:
			"road":
				var path: Array = mv["path"]
				var dist := fmod(t * 4.5 + float(mv["off"]), float(mv["total"]))
				var a: Vector3 = path[0]
				var b: Vector3 = path[1]
				for i in range(path.size() - 1):
					var seg: float = path[i].distance_to(path[i + 1])
					if dist <= seg:
						a = path[i]
						b = path[i + 1]
						break
					dist -= seg
				var dir := (b - a).normalized()
				var side := Vector3(-dir.z, 0, dir.x) * float(mv["side"])
				n.position = a + dir * dist + side
				n.rotation.y = lerp_angle(n.rotation.y, atan2(dir.x, dir.z), 0.1)
				for w in mv["wheels"]:
					(w as Node3D).rotate_x(dt * 6.0)
			"orbit":
				var cc: Vector3 = mv["c"]
				var r: float = mv["r"]
				var sp: float = mv["speed"]
				var p := cc + Vector3(cos(t * sp) * r, sin(t * 0.7) * 2.0, sin(t * sp) * r)
				var nxt := cc + Vector3(cos(t * sp + 0.05) * r, 0, sin(t * sp + 0.05) * r)
				n.position = p
				var d := Vector3(nxt.x, p.y, nxt.z) - p
				n.rotation = Vector3(0, atan2(d.x, d.z), 0)   # models face +Z
				n.rotate_object_local(Vector3(0, 0, 1), 0.35 if r > 50.0 else 0.12)   # bank into the turn
				for ro in mv["rotors"]:
					var rn: Node3D = ro
					if "Tail" in rn.name:
						rn.rotate_x(dt * 45.0)
					else:
						rn.rotate_y(dt * 40.0)
	# building idle animations (radar spin etc.)
	for key in get_meta_list():
		if str(key).begins_with("anims_"):
			for a in get_meta(key):
				var node: Node3D = a["node"]
				if not is_instance_valid(node):
					continue
				match a["kind"]:
					"spin":
						node.rotate_y(dt * float(a["speed"]))
					"spinz":
						pass
					"sweep":
						node.rotation.y = sin(t * float(a["speed"])) * 0.9
					"nod":
						node.rotation.x = sin(t * float(a["speed"])) * 0.25
					"blink":
						node.visible = fmod(t * float(a["speed"]), 1.0) < 0.5
					"pulse":
						node.scale = Vector3.ONE * (0.75 + 0.25 * sin(t * float(a["speed"]) * 2.0))
