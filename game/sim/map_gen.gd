class_name MapGen
extends RefCounted
## Builds a map description. Deterministic (seeded) so it can be generated on the
## server and sent to clients as a plain dictionary.
##
## Every map is a list of spawn slots (start positions). Each base gets the same
## "kit" laid out in a local frame: u points from the base toward the map centre,
## v is perpendicular. So the kit works for corner and mid-edge bases alike.

const THEMES := {
	"desert": {"trees": ["Environment/SM_Env_Tree_01.tscn", "Environment/SM_Env_Tree_Small_01.tscn", "Environment/SM_Env_Cactus_01.tscn", "Environment/SM_Env_Cactus_02.tscn"], "deco": "Environment/SM_Env_SandDunes_0%d.tscn", "trees_per_base": 10},
	"snow": {"trees": ["Environment/SM_Env_Tree_Big_01.tscn", "Environment/SM_Env_Tree_Big_02.tscn", "Environment/SM_Env_Tree_02.tscn"], "deco": "Environment/SM_Env_Rock_Flat_0%d.tscn", "trees_per_base": 30},
	"grass": {"trees": ["Environment/SM_Env_Tree_Large_01.tscn", "Environment/SM_Env_Tree_Round_01.tscn", "Environment/SM_Env_Tree_Bush_01.tscn", "Environment/SM_Env_Tree_02.tscn"], "deco": "Environment/SM_Env_Bush_Group_0%d.tscn", "trees_per_base": 30},
}

## Playable maps. "starts" are fractions of the map size.
const MAPS := {
	"desert2": {"name": "Desert Divide", "theme": "desert", "size": 300.0, "seed": 7, "players": 2,
		"starts": [Vector2(0.18, 0.18), Vector2(0.82, 0.82)]},
	"desert4": {"name": "Sand Sea", "theme": "desert", "size": 400.0, "seed": 11, "players": 4,
		"starts": [Vector2(0.16, 0.16), Vector2(0.84, 0.84), Vector2(0.84, 0.16), Vector2(0.16, 0.84)]},
	"snow4": {"name": "Frozen Front", "theme": "snow", "size": 400.0, "seed": 21, "players": 4,
		"starts": [Vector2(0.16, 0.16), Vector2(0.84, 0.84), Vector2(0.84, 0.16), Vector2(0.16, 0.84)]},
	"grass6": {"name": "Green Valley", "theme": "grass", "size": 500.0, "seed": 33, "players": 6,
		"starts": [Vector2(0.13, 0.13), Vector2(0.87, 0.87), Vector2(0.87, 0.13), Vector2(0.13, 0.87), Vector2(0.11, 0.5), Vector2(0.89, 0.5)]},
}
const MAP_ORDER := ["desert2", "desert4", "snow4", "grass6"]

static func map_id(id: String) -> String:
	if MAPS.has(id):
		return id
	# legacy names
	match id:
		"desert":
			return "desert2"
		"snow":
			return "snow4"
		"grass":
			return "grass6"
	return "desert2"

static func slots(id: String) -> int:
	return int(MAPS[map_id(id)]["players"])

## Build the whole map (all slots get a base kit whether or not a player sits there,
## so the map looks the same in every game).
static func build(id: String = "desert2", _players := 2) -> Dictionary:
	id = map_id(id)
	var md: Dictionary = MAPS[id]
	var th: Dictionary = THEMES[md["theme"]]
	var S: float = md["size"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(md["seed"])
	var m := {
		"id": id,
		"name": md["name"],
		"theme": md["theme"],
		"size": S,
		"starts": [],
		"start_yaw": [],
		"docks": [],        # [{p, boxes}]
		"derricks": [],     # [p]
		"props": [],        # [{m, p, yaw, s, fp, kind}] fp = blocked cells (Vector2i), Vector2i.ZERO = decoration only
		"ridges": [],       # [{a, b, w, h}] impassable mountain ridges (capsules), raised terrain on the client
		"roads": [],        # [{a, b}] purely visual
		"civ": [],          # [{type, p, yaw}] garrisonable civilian structures (spawned as neutral entities)
	}
	var centre := Vector2(S * 0.5, S * 0.5)
	var frames: Array = []   # [s, u, v]
	for f in md["starts"]:
		var s: Vector2 = Vector2(f) * S
		var u := (centre - s).normalized()
		var v := Vector2(-u.y, u.x)
		frames.append([s, u, v])
		m["starts"].append(s)
		m["start_yaw"].append(atan2(u.x, u.y))
	var mtn_models := ["Environment/SM_Env_Mountain_01.tscn", "Environment/SM_Env_Mountain_02.tscn", "Environment/SM_Env_Mountain_03.tscn", "Environment/SM_Env_Mountain_04.tscn"]
	for fr in frames:
		var s: Vector2 = fr[0]
		var u: Vector2 = fr[1]
		var v: Vector2 = fr[2]
		# two base docks flanking the entrance
		for sv in [1.0, -1.0]:
			_add_dock(m, [s + u * 16.0 + v * (50.0 * sv)], 400, S)
		# expansion dock + derrick out along the edge (first clear candidate wins)
		_add_dock(m, [s + u * 72.0 - v * 120.0, s + u * 40.0 - v * 120.0, s + u * 72.0 + v * 120.0], 300, S)
		_add_derrick(m, [s + u * 95.0 - v * 98.0, s + u * 60.0 - v * 98.0, s + u * 95.0 + v * 98.0], S)
		m["roads"].append({"a": s, "b": s + u * 90.0})
	for fr in frames:
		var s: Vector2 = fr[0]
		var u: Vector2 = fr[1]
		var v: Vector2 = fr[2]
		# ridges shielding the base: one along the approach, one spur toward the expansion
		_add_ridge(m, rng, mtn_models, s + u * 65.0 - v * 14.0, s + u * 122.0, S)
		_add_ridge(m, rng, mtn_models, s + u * 37.0 - v * 85.0, s + u * 72.0 - v * 64.0, S)
	# centre: derricks and a ruined village
	for d in [Vector2(-14, 14), Vector2(14, -14)]:
		_add_derrick(m, [centre + d], S)
	# the village: intact houses and shops you can garrison (Generals-style), a couple of ruins for cover
	var houses := [
		{"d": Vector2(-30, -14), "type": "civ_house"},
		{"d": Vector2(30, 14), "type": "civ_house"},
		{"d": Vector2(14, -30), "type": "civ_shop"},
		{"d": Vector2(-14, 30), "type": "civ_shop"},
		{"d": Vector2(0, 0), "type": "civ_tower"},
	]
	for h in houses:
		m["civ"].append({"type": h["type"], "p": centre + h["d"], "yaw": 0.0 if h["d"].x <= 0 else PI})
	for d in [Vector2(-34, 16), Vector2(34, -16)]:
		m["props"].append({"m": "", "p": centre + d, "yaw": 0.0 if d.x <= 0 else PI, "s": 1.0, "fp": Vector2i(4, 3), "kind": "ruin"})
	# a farmstead on each approach: a house and a shop flanking the road out of the base
	for fr in frames:
		var s: Vector2 = fr[0]
		var u: Vector2 = fr[1]
		var v: Vector2 = fr[2]
		for cand in [[s + u * 92.0 + v * 26.0, "civ_house"], [s + u * 100.0 - v * 30.0, "civ_shop"], [s + u * 60.0 + v * 70.0, "civ_tower"]]:
			var p: Vector2 = cand[0]
			if _inside(p, S, 14.0) and _clear_spot(m, p, 16.0, true):
				m["civ"].append({"type": cand[1], "p": p, "yaw": atan2(u.x, u.y)})
				var fp: Vector2i = Data.BUILDINGS[cand[1]]["fp"]
				m["props"].append({"m": "", "p": p, "yaw": 0.0, "s": 1.0, "fp": fp, "kind": "civ"})   # reserves the ground for the clear-spot checks
	# rock formations shaping the lanes between neighbouring bases
	var rock_models := ["Environment/SM_Env_Rock_01.tscn", "Environment/SM_Env_Rock_02.tscn", "Environment/SM_Env_Rock_03.tscn", "Environment/SM_Env_Rock_04.tscn"]
	for i in range(frames.size()):
		var s: Vector2 = frames[i][0]
		var u: Vector2 = frames[i][1]
		var v: Vector2 = frames[i][2]
		for d in [u * 150.0 + v * 40.0, u * 150.0 - v * 40.0, u * 105.0 + v * 12.0]:
			var p: Vector2 = s + d
			if _inside(p, S, 12.0) and _clear_spot(m, p, 14.0, true):
				m["props"].append({"m": rock_models[rng.randi() % rock_models.size()], "p": p, "yaw": rng.randf() * TAU, "s": 1.0, "fp": Vector2i(4 + rng.randi() % 4, 4 + rng.randi() % 3), "kind": "rock"})
	# trees (single blocked cell each), away from bases and docks
	var tree_models: Array = th["trees"]
	var want_trees: int = int(th["trees_per_base"]) * frames.size()
	var tries := 0
	var placed := 0
	while placed < want_trees and tries < 6000:
		tries += 1
		var p := Vector2(rng.randf_range(12, S - 12), rng.randf_range(12, S - 12))
		if not _clear_spot(m, p, 12.0):
			continue
		var n := 1 + rng.randi() % 3
		for k in range(n):
			var q := p + Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5))
			if _inside(q, S, 8.0):
				m["props"].append({"m": tree_models[rng.randi() % tree_models.size()], "p": q, "yaw": rng.randf() * TAU, "s": 1.0, "fp": Vector2i(1, 1), "kind": "tree"})
				placed += 1
	# decoration (no blocking)
	for i in range(int(S / 10.0)):
		var p := Vector2(rng.randf_range(10, S - 10), rng.randf_range(10, S - 10))
		if not _clear_spot(m, p, 16.0):
			continue
		var dm: String = th["deco"] % (1 + rng.randi() % 2)
		m["props"].append({"m": dm, "p": p, "yaw": rng.randf() * TAU, "s": 1.0, "fp": Vector2i.ZERO, "kind": "deco"})
	# roads through the middle
	m["roads"].append({"a": centre + Vector2(-100, -100), "b": centre + Vector2(100, 100)})
	m["roads"].append({"a": centre + Vector2(100, -100), "b": centre + Vector2(-100, 100)})
	return m

static func _inside(p: Vector2, S: float, margin: float) -> bool:
	return p.x >= margin and p.y >= margin and p.x <= S - margin and p.y <= S - margin

static func _add_dock(m: Dictionary, cands: Array, boxes: int, S: float) -> void:
	for c in cands:
		var p := Vector2(clampf(c.x, 14.0, S - 14.0), clampf(c.y, 14.0, S - 14.0))
		if _site_free(m, p, 24.0):
			m["docks"].append({"p": p, "boxes": boxes})
			return

static func _add_derrick(m: Dictionary, cands: Array, S: float) -> void:
	for c in cands:
		var p := Vector2(clampf(c.x, 10.0, S - 10.0), clampf(c.y, 10.0, S - 10.0))
		if _site_free(m, p, 16.0):
			m["derricks"].append(p)
			return

static func _site_free(m: Dictionary, p: Vector2, d: float) -> bool:
	for s in m["starts"]:
		if p.distance_to(s) < 30.0:
			return false
	for k in m["docks"]:
		if k["p"].distance_to(p) < d:
			return false
	for k in m["derricks"]:
		if k.distance_to(p) < d:
			return false
	for r in m["ridges"]:
		if PathGrid.seg_dist(p, r["a"], r["b"]) < r["w"] + 6.0:
			return false
	return true

## A mountain ridge from a to b: a capsule of half-width w. Cells under it are blocked
## (see World / ClientView grid setup); the client raises the terrain to match.
static func _add_ridge(m: Dictionary, rng: RandomNumberGenerator, _models: Array, a: Vector2, b: Vector2, S: float) -> void:
	a = Vector2(clampf(a.x, 10.0, S - 10.0), clampf(a.y, 10.0, S - 10.0))
	b = Vector2(clampf(b.x, 10.0, S - 10.0), clampf(b.y, 10.0, S - 10.0))
	# shorten the ridge if it would cover a dock / derrick / start
	var n := int(a.distance_to(b) / 4.0) + 1
	var pts: Array = []
	for i in range(n + 1):
		var pp := a.lerp(b, float(i) / n)
		if _site_free(m, pp, 18.0):
			pts.append(pp)
	if pts.size() < 3:
		return
	m["ridges"].append({"a": pts[0], "b": pts[pts.size() - 1], "w": 9.0 + rng.randf() * 3.0, "h": 15.0 + rng.randf() * 6.0, "seed": rng.randi() % 1000})

static func _clear_spot(m: Dictionary, p: Vector2, min_d: float, allow_near_start := false) -> bool:
	for s in m["starts"]:
		if p.distance_to(s) < (40.0 if allow_near_start else 70.0):
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
	for rd in m["ridges"]:
		if PathGrid.seg_dist(p, rd["a"], rd["b"]) < rd["w"] + min_d * 0.5:
			return false
	return true

## Small preview image for the lobby (theme colour, ridges, docks, derricks, starts).
static func preview(id: String, px := 220) -> Image:
	var m := build(id)
	var S: float = m["size"]
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var base := Color(0.55, 0.47, 0.32)
	var rock := Color(0.36, 0.32, 0.28)
	match m["theme"]:
		"snow":
			base = Color(0.78, 0.80, 0.84)
			rock = Color(0.45, 0.47, 0.52)
		"grass":
			base = Color(0.32, 0.45, 0.2)
			rock = Color(0.4, 0.38, 0.32)
	img.fill(base)
	var k := px / S
	for pr in m["props"]:
		var fp: Vector2i = pr["fp"]
		if fp == Vector2i.ZERO:
			continue
		var col := rock
		if pr["kind"] == "tree":
			col = Color(0.2, 0.38, 0.18)
		elif pr["kind"] == "mountain":
			col = rock.darkened(0.25)
		var p: Vector2 = pr["p"]
		var x0 := int((p.x - fp.x) * k)
		var y0 := int((p.y - fp.y) * k)
		for y in range(y0, int((p.y + fp.y) * k) + 1):
			for x in range(x0, int((p.x + fp.x) * k) + 1):
				if x >= 0 and y >= 0 and x < px and y < px:
					img.set_pixel(x, y, col)
	for rd in m["ridges"]:
		var a: Vector2 = rd["a"]
		var b: Vector2 = rd["b"]
		var steps := int(a.distance_to(b) / 2.0) + 1
		for i in range(steps + 1):
			_blob(img, a.lerp(b, float(i) / steps) * k, int(rd["w"] * k), rock.darkened(0.3))
	for d in m["docks"]:
		_blob(img, Vector2(d["p"]) * k, 3, Color(1.0, 0.85, 0.2))
	for d in m["derricks"]:
		_blob(img, Vector2(d) * k, 2, Color(0.15, 0.15, 0.15))
	return img

static func _blob(img: Image, c: Vector2, r: int, col: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r:
				var px := int(c.x) + x
				var py := int(c.y) + y
				if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
					img.set_pixel(px, py, col)
