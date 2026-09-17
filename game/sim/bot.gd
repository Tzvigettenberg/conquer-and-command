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

const BUILD_ORDER := ["power_plant", "barracks", "supply_center", "war_factory", "power_plant", "patriot", "supply_center", "war_factory", "airfield", "power_plant", "strategy_center", "patriot", "patriot", "firebase", "power_plant", "supply_drop_zone", "particle_cannon", "power_plant"]

func setup(_w: World, _p: int) -> void:
	w = _w
	p = _p
	rng.seed = 100 + p
	wave_t = 150.0

func think(dt: float) -> void:
	t += dt
	think_t -= dt
	if think_t > 0.0:
		return
	think_t = 1.0
	if w.players[p]["defeated"]:
		return
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

func _cc() -> Ent:
	var l := _own("command_center")
	return l[0] if not l.is_empty() else null

func _base_pos() -> Vector2:
	var cc := _cc()
	if cc:
		return cc.pos
	for e: Ent in w.ents.values():
		if e.alive and e.owner == p and e.is_building:
			return e.pos
	return w.map["starts"][p]

func _cash() -> float:
	return float(w.players[p]["cash"])

func _scan_enemy() -> void:
	# The bot "sees" like a player: only remembers enemy buildings its vision has covered.
	var v: Vision = w.visions[p]
	for e: Ent in w.ents.values():
		if e.alive and e.owner >= 0 and e.owner != p and e.is_building and v.visible(e.pos):
			known_enemy = e.pos
	if known_enemy.x < 0 and t > 30.0:
		known_enemy = w.map["starts"][1 - p] if w.players.size() > 1 else Vector2(200, 200)

# ---------------------------------------------------------------------------
func _economy() -> void:
	# keep 2 chinooks per supply center, re-task idle ones
	var centers := _own("supply_center")
	var chinooks := _own("chinook")
	for c in chinooks:
		if c.state == "idle":
			w.cmd(p, {"t": "gather", "ids": [c.id], "tid": -1})
	if not centers.is_empty() and chinooks.size() < mini(3, centers.size() * 2) and _cash() > 1800:
		var sc: Ent = centers[0]
		if sc.prod.is_empty():
			w.cmd(p, {"t": "produce", "id": sc.id, "type": "chinook"})
	# dozers: keep two
	var cc := _cc()
	var dozers := _own("dozer")
	if cc and dozers.size() < 2 and cc.prod.is_empty() and _cash() > 2200 and t > 60.0:
		w.cmd(p, {"t": "produce", "id": cc.id, "type": "dozer"})
	# capture derricks with rangers once the upgrade exists
	if w.players[p]["upgrades"].has("capture"):
		for d: Ent in w.ents.values():
			if d.alive and d.type == "oil_derrick" and d.owner != p and d.capture_by != p:
				var rangers := _own("ranger")
				var best: Ent = null
				for r in rangers:
					if r.state == "idle" or r.state == "guard":
						if best == null or r.pos.distance_squared_to(d.pos) < best.pos.distance_squared_to(d.pos):
							best = r
				if best != null and best.pos.distance_to(d.pos) < 160.0:
					w.cmd(p, {"t": "capture", "ids": [best.id], "tid": d.id})
					break

func _construction() -> void:
	var dozers := _own("dozer")
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
	if int(pl["pu"]) >= int(pl["pp"]) and _count_built("power_plant") > 0:
		want = "power_plant"
	else:
		var counts := {}
		for b in BUILD_ORDER:
			counts[b] = counts.get(b, 0) + 1
			if _count_built(b, false) < counts[b]:
				want = b
				break
	if want == "":
		want = "war_factory" if _count_built("war_factory") < 3 else "patriot"
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
	if type == "patriot" or type == "firebase":
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

func _production() -> void:
	var cash := _cash()
	var army := _own_units().size()
	var reserve := 600.0 if _count_built("war_factory") > 0 else 0.0
	for b: Ent in _own("barracks"):
		if b.prod.size() < 2 and cash > reserve + 300 and army < 40:
			var pick := "ranger" if rng.randf() < 0.55 else "missile_defender"
			if _count_built("strategy_center") > 0 and rng.randf() < 0.15:
				pick = "pathfinder" if w.players[p]["powers"].has("pathfinder") else pick
			w.cmd(p, {"t": "produce", "id": b.id, "type": pick})
			cash -= float(Data.UNITS[pick]["cost"])
	for b: Ent in _own("war_factory"):
		if b.prod.size() < 2 and cash > 900 and army < 40:
			var roll := rng.randf()
			var pick := "crusader"
			if w.players[p]["powers"].has("paladin") and roll < 0.35:
				pick = "paladin"
			elif roll < 0.5:
				pick = "humvee"
			elif roll < 0.62 and _count_built("strategy_center") > 0:
				pick = "tomahawk"
			elif roll < 0.7:
				pick = "ambulance" if _count_built("ambulance") + _queued("ambulance") < 1 else "crusader"
			w.cmd(p, {"t": "produce", "id": b.id, "type": pick})
			cash -= float(Data.UNITS[pick]["cost"])
	for b: Ent in _own("airfield"):
		if b.prod.is_empty() and cash > 2200 and w._airfield_load(b) < 4:
			var pick := "raptor" if rng.randf() < 0.5 else "comanche"
			if _count_built("strategy_center") > 0 and rng.randf() < 0.3:
				pick = "aurora"
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
	if _cash() < 3000:
		return
	var order := [["barracks", "capture"], ["war_factory", "tow"], ["power_plant", "control_rods"], ["strategy_center", "composite_armor"], ["airfield", "rocket_pods"], ["strategy_center", "advanced_training"], ["strategy_center", "supply_lines"], ["airfield", "laser_missiles"]]
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
	if int(pl["points"]) > 0:
		for pid in ["a10", "paladin", "spy_satellite", "emergency_repair", "paradrop", "pathfinder", "stealth_fighter"]:
			var pd: Dictionary = Data.POWERS[pid]
			if int(pl["rank"]) >= int(pd["rank"]) and int(pl["powers"].get(pid, 0)) < int(pd.get("levels", 1)):
				w.cmd(p, {"t": "buy_power", "pid": pid})
				break
	# use abilities on the enemy base / our defence
	var target: Vector2 = attack_target if attacking and attack_target.x >= 0 else known_enemy
	if target.x < 0:
		return
	for pid in ["a10", "fuel_air_bomb"]:
		if int(pl["powers"].get(pid, 0)) > 0 and float(pl["cds"].get(pid, 0.0)) <= w.time:
			var tp := _enemy_cluster(target)
			w.cmd(p, {"t": "power", "pid": pid, "x": tp.x, "y": tp.y})
	if int(pl["powers"].get("paradrop", 0)) > 0 and float(pl["cds"].get("paradrop", 0.0)) <= w.time and attacking:
		w.cmd(p, {"t": "power", "pid": "paradrop", "x": target.x, "y": target.y})
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
	for b: Ent in _own("particle_cannon"):
		if b.sw_ready:
			var tp := _enemy_cluster(known_enemy)
			w.cmd(p, {"t": "sw", "id": b.id, "x": tp.x, "y": tp.y})
			w.cmd(p, {"t": "sw_steer", "x": tp.x, "y": tp.y})

## Densest known enemy spot near a point (visible entities), else the point itself.
func _enemy_cluster(near: Vector2) -> Vector2:
	var best := near
	var best_n := 0
	for e: Ent in w.ents.values():
		if not e.alive or e.owner == p or e.owner < 0 or not w.visions[p].visible(e.pos):
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
		if u.def.get("builder", false) or u.def.get("gatherer", 0) > 0 or u.type == "ambulance":
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
			if e.alive and e.owner >= 0 and e.owner != p and not e.is_building and e.pos.distance_to(base) < 110.0:
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
			wave_size = mini(wave_size + 3, 18)
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
			if e.alive and e.owner >= 0 and e.owner != p and e.is_building and e.pos.distance_to(attack_target) < 70.0:
				enemy_left = true
				if w.visions[p].visible(e.pos):
					attack_target = e.pos
		if alive < 3 or (near_target > 0 and not enemy_left):
			attacking = false
			wave_t = t + 60.0
			if not enemy_left:
				# pick another known enemy building
				known_enemy = Vector2(-1, -1)
				for e: Ent in w.ents.values():
					if e.alive and e.owner >= 0 and e.owner != p and e.is_building:
						known_enemy = e.pos
						break
				if known_enemy.x < 0:
					known_enemy = w.map["starts"][1 - p]
		else:
			# keep re-issuing attack-move so units that finished fighting push on
			var ids := []
			for u in units:
				if u.state == "idle" or u.state == "guard":
					ids.append(u.id)
			if not ids.is_empty():
				w.cmd(p, {"t": "amove", "ids": ids, "x": attack_target.x, "y": attack_target.y, "q": false})
