class_name Bot
extends RefCounted
## Server-side AI opponent. Issues the same commands a human client would.
## Keeps a build order going, gathers, trains a mixed army, defends alerts,
## attacks in waves, rebuilds, researches, buys and uses general's powers.

var w: World
var p := 0
var t := 0.0
var think_t := 0.0
var next_build_t := 0.0
var wave_t := 0.0
var wave_size := 6
var known_enemy := Vector2(-1, -1)
var attack_target := Vector2(-1, -1)
var attacking := false
var defend_until := 0.0
var defend_pos := Vector2.ZERO
var last_alert_t := -100.0
var ring := 0
var rng := RandomNumberGenerator.new()
var difficulty := 1.0     # income / aggression multiplier

var fd: Dictionary = {}          # Data.FACTIONS entry for this bot's side
var next_want := ""              # structure the crew is saving up for (production leaves the money alone)

var level := "medium"
var powers_after := 240.0
var bonus_t := 0.0
var unit_cap := 40
var wave_gap := 90.0
var wave_grow := 3
var wave_max := 18

func setup(_w: World, _p: int, _level := "medium") -> void:
	w = _w
	p = _p
	level = _level
	fd = Data.FACTIONS[w.faction_of_player(p)]
	rng.seed = 100 + p
	match level:
		"easy":
			wave_t = 360.0
			wave_size = 8
			powers_after = 600.0
			unit_cap = 16
			wave_gap = 180.0
			wave_grow = 1
			wave_max = 10
		"hard":
			wave_t = 120.0
			wave_size = 6
			powers_after = 150.0
			unit_cap = 60
			wave_gap = 60.0
			wave_grow = 3
			wave_max = 18
		_:
			# medium: a real opponent but one you can out-macro - fewer units, slower waves, later powers
			wave_t = 300.0
			wave_size = 6
			powers_after = 420.0
			unit_cap = 24
			wave_gap = 120.0
			wave_grow = 2
			wave_max = 12

func think(dt: float) -> void:
	t += dt
	think_t -= dt
	if think_t > 0.0:
		return
	think_t = 1.0 if level != "easy" else 2.0
	if w.players[p]["defeated"]:
		return
	if level == "hard":
		# hard AI gets a supply subsidy, Generals "Hard" style
		bonus_t += think_t
		if bonus_t >= 10.0:
			bonus_t = 0.0
			w.players[p]["cash"] += 150.0
	if w.debug and int(t) % 10 == 0:
		var counts := {}
		for e: Ent in w.ents.values():
			if e.alive and e.owner == p:
				counts[e.type] = counts.get(e.type, 0) + 1
		print("[Bot %d] t=%d cash=%d attacking=%s wave_t=%d known=%s %s" % [p, int(t), int(_cash()), str(attacking), int(wave_t), str(known_enemy), str(counts)])
	_scan_enemy()
	_economy()
	_construction()
	_production()
	_research()
	_powers()
	_army()

# ---------------------------------------------------------------------------
func _own(type: String, complete_only := true) -> Array:
	var out := []
	for e: Ent in w.ents.values():
		if e.alive and e.owner == p and e.type == type and (e.complete or not complete_only):
			out.append(e)
	return out

func _own_units() -> Array:
	var out := []
	for e: Ent in w.ents.values():
		if e.alive and e.owner == p and not e.is_building:
			out.append(e)
	return out

## Own completed structures with a given role (cc / supply / factory / airfield / barracks ...).
func _role(role: String, complete_only := true) -> Array:
	var out := []
	for e: Ent in w.ents.values():
		if e.alive and e.owner == p and e.is_building and (e.complete or not complete_only) and Data.role_of(e.type) == role:
			out.append(e)
	return out

func _cc() -> Ent:
	var l := _role("cc")
	return l[0] if not l.is_empty() else null

## Construction crew, oldest first. GLA workers: the first two are builders, the rest haul.
func _builders() -> Array:
	var out := []
	for e: Ent in w.ents.values():
		if e.alive and e.owner == p and not e.is_building and e.def.get("builder", false) and e.inside_id < 0:
			out.append(e)
	out.sort_custom(func(a: Ent, b: Ent) -> bool: return a.id < b.id)
	return out

const KEEP_BUILDERS := 2

func _is_crew(e: Ent) -> bool:
	var bs := _builders()
	for i in range(mini(KEEP_BUILDERS, bs.size())):
		if bs[i] == e:
			return true
	return false

func _pick(list: Array) -> String:
	return list[rng.randi() % list.size()]

func _base_pos() -> Vector2:
	var cc := _cc()
	if cc:
		return cc.pos
	for e: Ent in w.ents.values():
		if e.alive and e.owner == p and e.is_building:
			return e.pos
	return w.map["starts"][int(w.players[p].get("slot", p))]

func _cash() -> float:
	return float(w.players[p]["cash"])

func _scan_enemy() -> void:
	# The bot "sees" like a player: only remembers enemy buildings its vision has covered.
	var v: Vision = w.visions[p]
	for e: Ent in w.ents.values():
		if e.alive and e.owner >= 0 and not w.allied(e.owner, p) and e.is_building and v.visible(e.pos):
			known_enemy = e.pos
	if known_enemy.x < 0 and t > 30.0:
		known_enemy = _nearest_enemy_start()

func _nearest_enemy_start() -> Vector2:
	var base := _base_pos()
	var best := Vector2(200, 200)
	var bd := 1e18
	for i in range(w.players.size()):
		if w.allied(i, p) or w.players[i]["defeated"]:
			continue
		var s: Vector2 = w.map["starts"][int(w.players[i].get("slot", i))]
		if s.distance_squared_to(base) < bd:
			bd = s.distance_squared_to(base)
			best = s
	return best

# ---------------------------------------------------------------------------
func _economy() -> void:
	# haulers: re-task idle ones, keep a few per supply centre (GLA workers double as builders:
	# the two oldest are the construction crew and never haul)
	var centers := _role("supply")
	var haulers := []
	for e: Ent in w.ents.values():
		if e.alive and e.owner == p and not e.is_building and int(e.def.get("gatherer", 0)) > 0 and e.inside_id < 0 and not _is_crew(e):
			haulers.append(e)
	var builder_type: String = fd["builder"]
	var gla := builder_type == "worker"
	for c in haulers:
		if c.state == "idle":
			w.cmd(p, {"t": "gather", "ids": [c.id], "tid": -1})
	var per_center := 2 if fd["cc"] == "command_center" else (3 if not gla else 5)
	var want_haulers := mini(per_center * 2 + 1, centers.size() * per_center)
	if not centers.is_empty() and haulers.size() < want_haulers:
		var sc: Ent = centers[0]
		var ht: String = sc.def["produces"][0] if not sc.def.get("produces", []).is_empty() else ""
		if ht != "" and sc.prod.is_empty() and _cash() > float(Data.UNITS[ht]["cost"]) + 300.0:
			w.cmd(p, {"t": "produce", "id": sc.id, "type": ht})
	# construction crew: keep two
	var cc := _cc()
	var crew := 0
	for b in _builders():
		if _is_crew(b):
			crew += 1
	var margin := (1200.0 if not gla else 300.0) if crew > 0 else 100.0
	if cc and crew < KEEP_BUILDERS and cc.prod.is_empty() and _cash() > float(Data.UNITS[builder_type]["cost"]) + margin and (t > 60.0 or crew == 0 or gla):
		w.cmd(p, {"t": "produce", "id": cc.id, "type": builder_type})
	# capture derricks with basic infantry once the upgrade exists
	if w.players[p]["upgrades"].has("capture"):
		for d: Ent in w.ents.values():
			if d.alive and d.type == "oil_derrick" and d.owner != p and d.capture_by != p:
				var best: Ent = null
				for r in _own_units():
					if r.def.get("capture", false) and not r.def.get("capture_free", false) and (r.state == "idle" or r.state == "guard"):
						if best == null or r.pos.distance_squared_to(d.pos) < best.pos.distance_squared_to(d.pos):
							best = r
				if best != null and best.pos.distance_to(d.pos) < 160.0:
					w.cmd(p, {"t": "capture", "ids": [best.id], "tid": d.id})
					break

func _construction() -> void:
	var dozers := []
	for b in _builders():
		if _is_crew(b):
			dozers.append(b)
	if dozers.is_empty():
		return
	# repair damaged structures first
	for b: Ent in w.ents.values():
		if b.alive and b.owner == p and b.is_building and b.complete and b.hp < b.max_hp * 0.6:
			for d in dozers:
				if d.state == "idle":
					w.cmd(p, {"t": "repair", "ids": [d.id], "tid": b.id})
					break
	# resume abandoned construction sites
	for b: Ent in w.ents.values():
		if b.alive and b.owner == p and b.is_building and not b.complete:
			var builder: Ent = w.ents.get(b.builder_id)
			if builder == null or not builder.alive or builder.state != "build" or builder.target_id != b.id:
				for d in dozers:
					if d.state == "idle":
						w.cmd(p, {"t": "repair", "ids": [d.id], "tid": b.id})
						return
			return   # one site at a time
	var idle: Ent = null
	for d in dozers:
		if d.state == "idle":
			idle = d
	if idle == null or t < next_build_t:
		return
	# what to build next: first missing entry in the build order, with power kept positive
	var pl: Dictionary = w.players[p]
	var want := ""
	var order: Array = fd["build_order"]
	var power_type := ""
	for b in order:
		if Data.role_of(b) == "power":
			power_type = b
			break
	if power_type != "" and int(pl["pu"]) >= int(pl["pp"]) and _count_built(power_type) > 0:
		want = power_type
	else:
		var counts := {}
		for b in order:
			counts[b] = counts.get(b, 0) + 1
			if _count_built(b, false) < counts[b]:
				want = b
				break
	if want == "":
		var factory := ""
		var defense := ""
		for b in order:
			if Data.role_of(b) == "factory" and factory == "":
				factory = b
			if Data.role_of(b) == "defense" and defense == "":
				defense = b
		want = factory if _count_built(factory) < 3 else defense
	next_want = want
	var d: Dictionary = Data.BUILDINGS[want]
	if w.prereqs_met(p, want) != "" or _cash() < float(d["cost"]) + 200.0:
		return
	var pos := _find_spot(want)
	if pos.x < 0:
		return
	w.cmd(p, {"t": "build", "id": idle.id, "type": want, "x": pos.x, "y": pos.y, "yaw": 0.0})
	next_build_t = t + 3.0

func _count_built(type: String, complete_only := true) -> int:
	return _own(type, complete_only).size()

## Spiral out from the base looking for a free footprint (defenses toward the enemy).
func _find_spot(type: String) -> Vector2:
	var base := _base_pos()
	var fp: Vector2i = Data.BUILDINGS[type]["fp"]
	var toward := Vector2.ZERO
	if Data.role_of(type) == "defense" or Data.role_of(type) == "trap":
		var en: Vector2 = known_enemy if known_enemy.x >= 0 else Vector2(200, 200)
		toward = (en - base).normalized()
	var best := Vector2(-1, -1)
	var best_d := 1e18
	var step := 4.0
	var r := 14.0
	while r < 110.0:
		var n := int(TAU * r / step)
		for i in range(n):
			var a := TAU * i / n
			var cand := base + Vector2(cos(a), sin(a)) * r
			if toward != Vector2.ZERO:
				cand = base + toward * (r + 16.0) + Vector2(-toward.y, toward.x) * ((i % 7 - 3) * 6.0)
			cand = PathGrid.snap_center(cand, fp)
			if not w.placement_ok(p, type, cand):
				continue
			var d := cand.distance_squared_to(base)
			if toward != Vector2.ZERO:
				d = cand.distance_squared_to(base + toward * 40.0)
			if d < best_d:
				best_d = d
				best = cand
		if best.x >= 0:
			return best
		r += 8.0
	return best

## A unit the bot can build right now from a role list (prereqs, promotions, limits).
func _choose(list: Array, b: Ent) -> String:
	for i in range(4):
		var pick := _pick(list)
		if b.def.get("produces", []).has(pick) and w.prereqs_met(p, pick) == "":
			return pick
	for pick in b.def.get("produces", []):
		if w.prereqs_met(p, pick) == "" and int(Data.UNITS[pick].get("gatherer", 0)) == 0 and not Data.UNITS[pick].get("builder", false):
			return pick
	return ""

func _production() -> void:
	var cash := _cash()
	var army := _own_units().size()
	# the crew gets first call on the money while the core base is still going up
	var reserve := 600.0 if not _role("factory").is_empty() else 0.0
	if next_want != "":
		var nf := _role("factory").size()
		if nf == 0:
			reserve = maxf(reserve, float(Data.BUILDINGS[next_want]["cost"]) * 0.8)
		elif nf == 1:
			reserve = maxf(reserve, float(Data.BUILDINGS[next_want]["cost"]) * 0.4)
	var qmax := 2 if level == "hard" else 1
	for b: Ent in _role("barracks"):
		if b.prod.size() < qmax and cash > reserve + 300 and army < unit_cap:
			var pick := _choose(fd["inf"], b)
			if pick == "paladin" or pick == "":
				continue
			if w.players[p]["powers"].has("pathfinder") and pick == "ranger" and rng.randf() < 0.15:
				pick = "pathfinder"
			w.cmd(p, {"t": "produce", "id": b.id, "type": pick})
			cash -= float(Data.UNITS[pick]["cost"])
	for b: Ent in _role("factory"):
		if b.prod.size() < qmax and cash > 900 and army < unit_cap:
			var pick := _choose(fd["veh"], b)
			if pick == "":
				continue
			var roll := rng.randf()
			if fd["cc"] == "command_center":
				if w.players[p]["powers"].has("paladin") and roll < 0.35:
					pick = "paladin"
				elif roll < 0.42 and _count_built("ambulance") + _queued("ambulance") < 1:
					pick = "ambulance"
			elif fd["cc"] == "gla_cc" and w.players[p]["powers"].has("marauder") and roll < 0.3:
				pick = "marauder"
			if w.prereqs_met(p, pick) != "":
				continue
			w.cmd(p, {"t": "produce", "id": b.id, "type": pick})
			cash -= float(Data.UNITS[pick]["cost"])
	if fd["cc"] == "command_center" and cash > 1800 and level != "easy":
		# USA: drones for the armour when money allows
		for u in _own_units():
			if u.cat() == "veh" and u.drone_id < 0 and not u.def.get("builder", false) and int(u.def.get("gatherer", 0)) == 0 and rng.randf() < 0.15:
				var kind := "battle_drone" if rng.randf() < 0.6 else "hellfire_drone"
				w.cmd(p, {"t": "drone", "id": u.id, "kind": kind})
				cash -= float(Data.UNITS[kind]["cost"])
				break
	for b: Ent in _role("airfield"):
		if b.prod.is_empty() and cash > 2200 and w._airfield_load(b) < 4 and not (fd["air"] as Array).is_empty():
			var pick := _choose(fd["air"], b)
			if pick == "":
				continue
			w.cmd(p, {"t": "produce", "id": b.id, "type": pick})
			cash -= float(Data.UNITS[pick]["cost"])

func _queued(type: String) -> int:
	var n := 0
	for b: Ent in w.ents.values():
		if b.alive and b.owner == p and b.is_building:
			for q in b.prod:
				if q["type"] == type:
					n += 1
	return n

func _research() -> void:
	# battle plan as soon as the strategy center stands: hard bots go on the offensive
	for sc in _own("strategy_center"):
		if sc.plan == "":
			w.cmd(p, {"t": "plan", "id": sc.id, "plan": "bombardment" if level == "hard" else ("search" if level == "medium" else "hold")})
	if _cash() < 3000:
		return
	var order: Array = fd["upgrades"]
	for pair in order:
		var bs := _own(pair[0])
		if bs.is_empty():
			continue
		var uid: String = pair[1]
		var done: bool = w.players[p]["upgrades"].has(uid)
		for b in bs:
			if b.upg_done.has(uid):
				done = true
			if not b.research.is_empty():
				return
		if done:
			continue
		w.cmd(p, {"t": "upgrade", "id": bs[0].id, "uid": uid})
		return

func _powers() -> void:
	var pl: Dictionary = w.players[p]
	if t < powers_after:
		return
	if int(pl["points"]) > 0:
		for pid in fd["powers"]:
			var pd: Dictionary = Data.POWERS[pid]
			if int(pl["rank"]) >= int(pd["rank"]) and int(pl["powers"].get(pid, 0)) < int(pd.get("levels", 1)):
				w.cmd(p, {"t": "buy_power", "pid": pid})
				break
	# use abilities on the enemy base / our defence
	var target: Vector2 = attack_target if attacking and attack_target.x >= 0 else known_enemy
	if target.x < 0:
		return
	for pid in fd["strike_powers"]:
		if int(pl["powers"].get(pid, 0)) > 0 and float(pl["cds"].get(pid, 0.0)) <= w.time:
			if (pid == "rebel_ambush" or pid == "sneak_attack") and not attacking:
				continue
			var tp := _enemy_cluster(target)
			w.cmd(p, {"t": "power", "pid": pid, "x": tp.x, "y": tp.y})
	if int(pl["powers"].get("paradrop", 0)) > 0 and float(pl["cds"].get("paradrop", 0.0)) <= w.time and attacking:
		w.cmd(p, {"t": "power", "pid": "paradrop", "x": target.x, "y": target.y})
	if int(pl["powers"].get("cash_hack", 0)) > 0 and float(pl["cds"].get("cash_hack", 0.0)) <= w.time:
		for e: Ent in w.ents.values():
			if e.alive and e.is_building and e.owner >= 0 and not w.allied(e.owner, p) and w.visions[p].visible(e.pos):
				w.cmd(p, {"t": "power", "pid": "cash_hack", "x": e.pos.x, "y": e.pos.y})
				break
	if int(pl["powers"].get("frenzy", 0)) > 0 and float(pl["cds"].get("frenzy", 0.0)) <= w.time and attacking:
		var centre := Vector2.ZERO
		var n := 0
		for u in _own_units():
			if u.pos.distance_to(target) < 60.0:
				centre += u.pos
				n += 1
		if n >= 5:
			centre /= n
			w.cmd(p, {"t": "power", "pid": "frenzy", "x": centre.x, "y": centre.y})
	if int(pl["powers"].get("emergency_repair", 0)) > 0 and float(pl["cds"].get("emergency_repair", 0.0)) <= w.time:
		var hurt := 0
		var centre := Vector2.ZERO
		for u in _own_units():
			if u.cat() == "veh" and u.hp < u.max_hp * 0.5:
				hurt += 1
				centre += u.pos
		if hurt >= 3:
			centre /= hurt
			w.cmd(p, {"t": "power", "pid": "emergency_repair", "x": centre.x, "y": centre.y})
	# superweapon
	for b: Ent in _role("sw"):
		if b.sw_ready:
			var tp := _enemy_cluster(known_enemy)
			w.cmd(p, {"t": "sw", "id": b.id, "x": tp.x, "y": tp.y})
			if b.def.get("sw_kind", "beam") == "beam":
				w.cmd(p, {"t": "sw_steer", "x": tp.x, "y": tp.y})

## Densest known enemy spot near a point (visible entities), else the point itself.
func _enemy_cluster(near: Vector2) -> Vector2:
	var best := near
	var best_n := 0
	for e: Ent in w.ents.values():
		if not e.alive or w.allied(e.owner, p) or e.owner < 0 or not w.visions[p].visible(e.pos):
			continue
		var n := 0
		for o: Ent in w.query(e.pos, 12.0):
			if o.owner == e.owner:
				n += 1
		if n > best_n:
			best_n = n
			best = e.pos
	return best

func _army() -> void:
	var units := []
	for u in _own_units():
		if u.def.get("builder", false) or u.def.get("gatherer", 0) > 0 or u.type == "ambulance" or u.def.has("hack") or u.inside_id >= 0:
			continue
		units.append(u)
	# defence: react to attacks on our base
	var pl: Dictionary = w.players[p]
	if float(pl["attack_msg_t"]) > last_alert_t:
		last_alert_t = float(pl["attack_msg_t"])
		var base := _base_pos()
		# find the nearest enemy to the base
		var nearest: Ent = null
		for e: Ent in w.ents.values():
			if e.alive and e.owner >= 0 and not w.allied(e.owner, p) and not e.is_building and e.pos.distance_to(base) < 110.0:
				if nearest == null or e.pos.distance_squared_to(base) < nearest.pos.distance_squared_to(base):
					nearest = e
		if nearest != null:
			defend_pos = nearest.pos
			defend_until = t + 25.0
			var ids := []
			for u in units:
				if not attacking or u.pos.distance_to(base) < 140.0:
					ids.append(u.id)
			if not ids.is_empty():
				w.cmd(p, {"t": "amove", "ids": ids, "x": defend_pos.x, "y": defend_pos.y, "q": false})
			return
	if t < defend_until:
		return
	# attack waves
	if not attacking:
		var ready := 0
		for u in units:
			if u.state == "idle" or u.state == "guard":
				ready += 1
		if t >= wave_t and ready >= wave_size and known_enemy.x >= 0:
			attacking = true
			attack_target = known_enemy
			var ids := []
			for u in units:
				ids.append(u.id)
			w.cmd(p, {"t": "amove", "ids": ids, "x": attack_target.x, "y": attack_target.y, "q": false})
			wave_size = mini(wave_size + wave_grow, wave_max)
		elif t > 40.0:
			# idle units gather at a rally point between base and the enemy
			var base := _base_pos()
			var en: Vector2 = known_enemy if known_enemy.x >= 0 else Vector2(200, 200)
			var rally := base + (en - base).normalized() * 34.0
			var ids := []
			for u in units:
				if u.state == "idle" and u.pos.distance_to(rally) > 18.0 and not u.is_jet():
					ids.append(u.id)
			if not ids.is_empty():
				w.cmd(p, {"t": "guard", "ids": ids, "x": rally.x, "y": rally.y})
	else:
		# wave over when few units remain or the target area is clear
		var alive := 0
		var near_target := 0
		for u in units:
			alive += 1
			if u.pos.distance_to(attack_target) < 50.0:
				near_target += 1
		var enemy_left := false
		for e: Ent in w.ents.values():
			if e.alive and e.owner >= 0 and not w.allied(e.owner, p) and e.is_building and e.pos.distance_to(attack_target) < 70.0:
				enemy_left = true
				if w.visions[p].visible(e.pos):
					attack_target = e.pos
		if alive < 3 or (near_target > 0 and not enemy_left):
			attacking = false
			wave_t = t + wave_gap
			if not enemy_left:
				# pick another known enemy building
				known_enemy = Vector2(-1, -1)
				for e: Ent in w.ents.values():
					if e.alive and e.owner >= 0 and not w.allied(e.owner, p) and e.is_building:
						known_enemy = e.pos
						break
				if known_enemy.x < 0:
					known_enemy = _nearest_enemy_start()
		else:
			# keep re-issuing attack-move so units that finished fighting push on
			var ids := []
			for u in units:
				if u.state == "idle" or u.state == "guard":
					ids.append(u.id)
			if not ids.is_empty():
				w.cmd(p, {"t": "amove", "ids": ids, "x": attack_target.x, "y": attack_target.y, "q": false})
