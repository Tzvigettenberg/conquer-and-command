class_name MapGen
extends RefCounted
## Builds the 1v1 map description. Deterministic (seeded) so it can be
## generated on the server and sent to clients as a plain dictionary.
## Layout is point-symmetric around the map centre: what P0 has at (x,y) P1 has at (S-x, S-y).

const SIZE := 400.0

static func mirror(p: Vector2) -> Vector2:
	return Vector2(SIZE - p.x, SIZE - p.y)

static func build(seed_val: int = 7) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var m := {
		"name": "Desert Divide",
		"size": SIZE,
		"starts": [Vector2(64, 64), mirror(Vector2(64, 64))],
		"start_yaw": [0.0, PI],
		"docks": [],        # [{p, boxes}]
		"derricks": [],     # [p]
		"props": [],        # [{m, p, yaw, s, fp}] fp = blocked cells (Vector2i), Vector2i.ZERO = decoration only
		"roads": [],        # [{a, b}] purely visual
	}
	# Supply docks: two per base, two contested expansions.
	for p in [Vector2(110, 40), Vector2(40, 110), Vector2(330, 44)]:
		m["docks"].append({"p": p, "boxes": 400})
		m["docks"].append({"p": mirror(p), "boxes": 400})
	# Oil derricks: one at each expansion corner, two in the centre.
	for p in [Vector2(352, 90), Vector2(186, 214)]:
		m["derricks"].append(p)
		m["derricks"].append(mirror(p))
	# Rock formations shaping the lanes.
	var rocks := [
		{"p": Vector2(200, 118), "fp": Vector2i(14, 5)},
		{"p": Vector2(118, 200), "fp": Vector2i(5, 14)},
		{"p": Vector2(150, 150), "fp": Vector2i(4, 4)},
		{"p": Vector2(262, 60), "fp": Vector2i(4, 10)},
		{"p": Vector2(60, 262), "fp": Vector2i(10, 4)},
		{"p": Vector2(300, 150), "fp": Vector2i(6, 4)},
		{"p": Vector2(20, 200), "fp": Vector2i(4, 12)},
	]
	var rock_models := ["Environment/SM_Env_Rock_01.tscn", "Environment/SM_Env_Rock_02.tscn", "Environment/SM_Env_Rock_03.tscn", "Environment/SM_Env_Rock_04.tscn"]
	for r in rocks:
		for pp in [r["p"], mirror(r["p"])]:
			m["props"].append({"m": rock_models[rng.randi() % rock_models.size()], "p": pp, "yaw": rng.randf() * TAU, "s": 1.0, "fp": r["fp"], "kind": "rock"})
	# Central ruined village: cover and chokepoints.
	var houses := [
		{"p": Vector2(170, 186), "fp": Vector2i(4, 4), "m": "Buildings/SM_Bld_Village_House_01_Destroyed.tscn"},
		{"p": Vector2(214, 170), "fp": Vector2i(4, 3), "m": "Buildings/SM_Bld_Village_House_03_Destroyed.tscn"},
		{"p": Vector2(200, 200), "fp": Vector2i(3, 3), "m": "Buildings/SM_Bld_Village_Well_01.tscn"},
	]
	for h in houses:
		m["props"].append({"m": h["m"], "p": h["p"], "yaw": 0.0, "s": 1.0, "fp": h["fp"], "kind": "ruin"})
		if h["p"] != Vector2(200, 200):
			m["props"].append({"m": h["m"], "p": mirror(h["p"]), "yaw": PI, "s": 1.0, "fp": h["fp"], "kind": "ruin"})
	# Trees (single blocked cell each), away from bases and docks.
	var tree_models := ["Environment/SM_Env_Tree_01.tscn", "Environment/SM_Env_Tree_02.tscn", "Environment/SM_Env_Tree_Small_01.tscn", "Environment/SM_Env_Cactus_01.tscn"]
	var tries := 0
	var placed := 0
	while placed < 60 and tries < 2000:
		tries += 1
		var p := Vector2(rng.randf_range(12, SIZE * 0.5 - 4), rng.randf_range(12, SIZE - 12))
		if not _clear_spot(m, p, 12.0):
			continue
		m["props"].append({"m": tree_models[rng.randi() % tree_models.size()], "p": p, "yaw": rng.randf() * TAU, "s": 1.0, "fp": Vector2i(1, 1), "kind": "tree"})
		m["props"].append({"m": tree_models[rng.randi() % tree_models.size()], "p": mirror(p), "yaw": rng.randf() * TAU, "s": 1.0, "fp": Vector2i(1, 1), "kind": "tree"})
		placed += 2
	# Decoration (no blocking): dunes and pebbles.
	for i in range(40):
		var p := Vector2(rng.randf_range(10, SIZE - 10), rng.randf_range(10, SIZE - 10))
		if not _clear_spot(m, p, 16.0):
			continue
		var dm := "Environment/SM_Env_SandDunes_0%d.tscn" % (1 + rng.randi() % 3)
		m["props"].append({"m": dm, "p": p, "yaw": rng.randf() * TAU, "s": 1.0, "fp": Vector2i.ZERO, "kind": "deco"})
	# Dirt road between the bases (visual only).
	m["roads"].append({"a": Vector2(64, 64), "b": Vector2(140, 140)})
	m["roads"].append({"a": Vector2(260, 260), "b": Vector2(336, 336)})
	m["roads"].append({"a": Vector2(140, 140), "b": Vector2(260, 260)})
	return m

static func _clear_spot(m: Dictionary, p: Vector2, min_d: float) -> bool:
	for s in m["starts"]:
		if p.distance_to(s) < 75.0:
			return false
	for d in m["docks"]:
		if p.distance_to(d["p"]) < 22.0:
			return false
	for d in m["derricks"]:
		if p.distance_to(d) < 14.0:
			return false
	for pr in m["props"]:
		var fp: Vector2i = pr["fp"]
		var r := maxf(fp.x, fp.y) * 1.0 + min_d * 0.5
		if p.distance_to(pr["p"]) < r:
			return false
	return true
