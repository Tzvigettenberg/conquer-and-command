class_name World
extends RefCounted
## Server-authoritative RTS simulation. Runs only on the host.
## Clients send commands; the world replicates spawns, snapshots, events and
## per-player state back through the Session node. Enemy entities are only
## replicated to a client while that client can see them (fog of war).

const TICK := 0.05
const SNAP_EVERY := 2       # 10 Hz snapshots
const VIS_EVERY := 5        # 4 Hz vision / fog
const PSTATE_EVERY := 5
const SPATIAL_CELL := 8.0
const CAPTURE_TIME := 20.0
const GHOST_TIMEOUT_TICKS := 20

var session: Node
var map: Dictionary
var map_size := 400.0
var ents: Dictionary = {}          # id -> Ent
var next_id := 1
var players: Array = []
var grid := PathGrid.new()
var visions: Array = []
var tick := 0
var time := 0.0
var shots: Array = []              # scheduled projectile impacts
var events: Array = []             # pending FX events for this snapshot
var strikes: Array = []            # delayed general's powers
var beams: Array = []              # active particle cannon beams
var spatial: Dictionary = {}
var known: Array = []              # per player: id -> last tick included
var pending_despawn: Array = []    # per player: id -> pos (ghost buildings)
var dead_list: Array = []
var game_over := false
var winner := -1
var solo := false
var debug := false

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
func start(_session: Node, peers: Array, names: Array) -> void:
	session = _session
	map = MapGen.build()
	map_size = map["size"]
	grid.setup(map_size)
	solo = peers.size() == 1
	for i in range(peers.size()):
		players.append({
			"peer": peers[i], "name": names[i], "cash": float(Data.STARTING_CASH), "xp": 0.0, "rank": 1, "points": 1,
			"powers": {}, "cds": {}, "upgrades": {}, "defeated": false, "pp": 0, "pu": 0, "low": false,
			"sw_steer": Vector2(-1, -1), "attack_msg_t": -100.0, "income_mult": 1.0,
		})
		var v := Vision.new()
		v.setup(map_size)
		visions.append(v)
		known.append({})
		pending_despawn.append({})
	# map obstacles
	for pr in map["props"]:
		var fp: Vector2i = pr["fp"]
		if fp != Vector2i.ZERO:
			grid.set_cells(PathGrid.footprint_cells(pr["p"], fp), true)
	for d in map["docks"]:
		var e := spawn("supply_dock", -1, d["p"])
		e.boxes = d["boxes"]
	for p in map["derricks"]:
		spawn("oil_derrick", -1, p)
	for i in range(players.size()):
		var s: Vector2 = map["starts"][i]
		var cc := spawn("command_center", i, PathGrid.snap_center(s, Data.BUILDINGS["command_center"]["fp"]))
		var ex := _exit_point(cc)
		var dz := spawn("dozer", i, ex)
		dz.yaw = map["start_yaw"][i]
		_recompute_power(i)
	grid.flush()
	for i in range(players.size()):
		session.s_map(players[i]["peer"], map, i)
	_update_vision()

func player_of_peer(peer: int) -> int:
	for i in range(players.size()):
		if players[i]["peer"] == peer:
			return i
	return -1

# ---------------------------------------------------------------------------
# Entities
# ---------------------------------------------------------------------------
func spawn(type: String, owner: int, pos: Vector2, complete := true) -> Ent:
	var e := Ent.new()
	e.setup(next_id, type, owner, pos)
	next_id += 1
	if e.is_building:
		e.cells = PathGrid.footprint_cells(pos, e.def["fp"])
		grid.set_cells(e.cells, true)
		e.complete = complete
		if not complete:
			e.hp = e.max_hp * 0.1
			e.progress = 0.0
		var fp: Vector2i = e.def["fp"]
		e.rally = pos + Vector2(0, fp.y + 5.0)
		e.has_rally = false
	else:
		if e.is_air():
			e.alt = float(e.def.get("alt", 10.0))
		if owner >= 0 and players[owner]["upgrades"].has("composite_armor") and (type == "crusader" or type == "paladin"):
			e.max_hp *= 1.25
			e.hp = e.max_hp
		e.guard_pos = pos
	ents[e.id] = e
	return e

func destroy(e: Ent, reason := "killed", killer: Ent = null) -> void:
	if not e.alive:
		return
	e.alive = false
	dead_list.append(e)
	if e.is_building:
		grid.set_cells(e.cells, false)
		# jets homed here lose their pads
		for o: Ent in ents.values():
			if o.alive and o.home_id == e.id:
				o.home_id = -1
				o.landed = false
	if killer != null and killer.owner >= 0 and killer.owner != e.owner and e.owner >= 0:
		var xp := float(e.def.get("cost", 100)) * 0.06
		var kp: Dictionary = players[killer.owner]
		if kp["upgrades"].has("advanced_training"):
			xp *= 2.0
		killer.xp += xp
		killer.kills += 1
		while killer.level < 3 and killer.xp >= Data.VET_XP[killer.level]:
			killer.level += 1
			var old_max := killer.max_hp
			killer.max_hp = float(killer.def.get("hp", 100.0)) * Data.VET_HP[killer.level]
			killer.hp += killer.max_hp - old_max
		_add_player_xp(killer.owner, xp)
	events.append({"k": "die", "p": e.pos, "d": [e.id, e.type, e.pos.x, e.pos.y, e.alt, e.yaw, reason], "o": e.owner})
	for p in range(players.size()):
		if known[p].has(e.id):
			if not e.is_building or visions[p].visible(e.pos) or e.owner == p:
				session.s_despawn(players[p]["peer"], e.id, reason)
				known[p].erase(e.id)
			else:
				pending_despawn[p][e.id] = e.pos
	if e.owner >= 0:
		if e.is_building:
			_recompute_power(e.owner)
			if reason == "killed" and e.complete:
				session.s_msg(players[e.owner]["peer"], "%s lost" % e.def["name"])
		# units targeting it are handled lazily in _do_attack

func _flush_dead() -> void:
	if dead_list.is_empty():
		return
	for e: Ent in dead_list:
		ents.erase(e.id)
	dead_list.clear()

func _exit_point(b: Ent) -> Vector2:
	var fp: Vector2i = b.def["fp"]
	var p := b.pos + Vector2(0, fp.y + 1.5)
	var c := grid.nearest_free(grid.cell_of(p))
	return grid.center_of(c)

func _pad_pos(air: Ent, idx: int) -> Vector2:
	var offs := [Vector2(-7.5, -5.0), Vector2(-2.5, -5.0), Vector2(2.5, -5.0), Vector2(7.5, -5.0)]
	return air.pos + offs[clampi(idx, 0, 3)]

func _add_player_xp(p: int, xp: float) -> void:
	var pl: Dictionary = players[p]
	pl["xp"] += xp
	while pl["rank"] < 5 and pl["xp"] >= Data.RANK_XP[pl["rank"]]:
		pl["rank"] += 1
		pl["points"] += 1
		session.s_msg(pl["peer"], "Promoted to General rank %d - promotion point available" % pl["rank"])
		if pl["rank"] == 5:
			pl["powers"]["fuel_air_bomb"] = 1

func _recompute_power(p: int) -> void:
	var prod := 0
	var use := 0
	for e: Ent in ents.values():
		if not e.alive or e.owner != p or not e.is_building or not e.complete:
			continue
		var pw := int(e.def.get("power", 0))
		if pw > 0:
			prod += pw + (5 if e.upg_done.has("control_rods") else 0)
		else:
			use -= pw
	var pl: Dictionary = players[p]
	var was_low: bool = pl["low"]
	pl["pp"] = prod
	pl["pu"] = use
	pl["low"] = use > prod
	if pl["low"] and not was_low:
		session.s_msg(pl["peer"], "Low power! Production slowed, defenses offline.")
	for e: Ent in ents.values():
		if e.alive and e.owner == p and e.is_building:
			e.powered = not pl["low"]

func has_building(p: int, type: String) -> bool:
	for e: Ent in ents.values():
		if e.alive and e.owner == p and e.type == type and e.complete:
			return true
	return false

func count_type(p: int, type: String, include_queued := true) -> int:
	var n := 0
	for e: Ent in ents.values():
		if not e.alive or e.owner != p:
			continue
		if e.type == type:
			n += 1
		if include_queued and e.is_building:
			for q in e.prod:
				if q["type"] == type:
					n += 1
	return n

func prereqs_met(p: int, type: String) -> String:
	var d := Data.def(type)
	var pl: Dictionary = players[p]
	for r in d.get("prereq", []):
		if not has_building(p, r):
			return "Requires %s" % Data.BUILDINGS[r]["name"]
	if d.has("prereq_any"):
		var ok := false
		for r in d["prereq_any"]:
			if has_building(p, r):
				ok = true
		if not ok:
			var names := []
			for r in d["prereq_any"]:
				names.append(Data.BUILDINGS[r]["name"])
			return "Requires %s" % " or ".join(names)
	if d.has("needs_power"):
		if not pl["powers"].has(d["needs_power"]):
			return "Requires General's promotion: %s" % Data.POWERS[d["needs_power"]]["name"]
	if d.has("limit") and count_type(p, type) >= int(d["limit"]):
		return "Limit reached"
	return ""

# ---------------------------------------------------------------------------
# Spatial hash
# ---------------------------------------------------------------------------
func _build_spatial() -> void:
	spatial.clear()
	for e: Ent in ents.values():
		if not e.alive:
			continue
		var c := Vector2i(int(e.pos.x / SPATIAL_CELL), int(e.pos.y / SPATIAL_CELL))
		if not spatial.has(c):
			spatial[c] = []
		spatial[c].append(e)

func query(p: Vector2, r: float) -> Array[Ent]:
	var out: Array[Ent] = []
	var c0 := Vector2i(int((p.x - r) / SPATIAL_CELL), int((p.y - r) / SPATIAL_CELL))
	var c1 := Vector2i(int((p.x + r) / SPATIAL_CELL), int((p.y + r) / SPATIAL_CELL))
	for y in range(c0.y, c1.y + 1):
		for x in range(c0.x, c1.x + 1):
			var arr = spatial.get(Vector2i(x, y))
			if arr == null:
				continue
			for e in arr:
				if e.alive and e.pos.distance_to(p) <= r + e.radius:
					out.append(e)
	return out

# ---------------------------------------------------------------------------
# Main tick
# ---------------------------------------------------------------------------
func step(dt: float) -> void:
	if game_over:
		return
	tick += 1
	time += dt
	_build_spatial()
	for e: Ent in ents.values():
		if not e.alive:
			continue
		if e.is_building:
			_tick_building(e, dt)
		else:
			_tick_unit(e, dt)
	_tick_shots()
	_tick_strikes()
	_tick_beams(dt)
	if tick % 10 == 0:
		_tick_heal(0.5)
	_flush_dead()
	if tick % VIS_EVERY == 0:
		_update_vision()
	if tick % SNAP_EVERY == 0:
		_send_snapshots()
	if tick % PSTATE_EVERY == 0:
		_send_pstates()
	if tick % 20 == 0:
		_check_victory()
	if debug and tick % 60 == 0:
		for e: Ent in ents.values():
			if e.alive and not e.is_building and e.owner >= 0:
				print("[Sim %d] %s#%d st=%s pos=%s path=%d/%d tgt=%d hp=%.0f" % [tick, e.type, e.id, e.state, e.pos.round(), e.path_i, e.path.size(), e.target_id, e.hp])

# ---------------------------------------------------------------------------
# Units
# ---------------------------------------------------------------------------
func _tick_unit(e: Ent, dt: float) -> void:
	for i in range(e.cds.size()):
		e.cds[i] = maxf(0.0, e.cds[i] - dt)
		if e.clip[i] <= 0 and e.reload_t[i] > 0.0:
			e.reload_t[i] -= dt
			if e.reload_t[i] <= 0.0:
				e.clip[i] = int(Data.WEAPONS[e.weapon_ids()[i]].get("clip", 0))
	if e.is_jet() and e.landed:
		_tick_landed_jet(e, dt)
		return
	match e.state:
		"idle", "guard":
			if e.is_jet():
				_jet_go_home(e)
			elif e.has_weapons():
				_auto_acquire(e, dt)
		"move":
			if _follow_path(e, dt):
				if e.is_jet():
					_jet_go_home(e)
				else:
					_next_order(e)
		"amove":
			if not _auto_acquire(e, dt):
				if _follow_path(e, dt):
					_next_order(e)
		"attack":
			_do_attack(e, dt)
		"gather":
			_do_gather(e, dt)
		"build":
			_do_build(e, dt)
		"repair":
			_do_repair(e, dt)
		"capture":
			_do_capture(e, dt)
		"return":
			_do_return(e, dt)
	e.last_pos = e.pos

func _next_order(e: Ent) -> void:
	e.state = "idle"
	e.target_id = -1
	e.path = PackedVector2Array()
	e.path_i = 0
	e.guard_pos = e.pos
	if not e.resume.is_empty():
		var r: Dictionary = e.resume
		e.resume = {}
		_order_move(e, r["goal"], r["state"])
		return
	if not e.queue.is_empty():
		var c: Dictionary = e.queue.pop_front()
		_apply_unit_cmd(e, c)

func _fwd(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))

## Steer e toward wp. Returns true when arrived.
func _move_toward(e: Ent, wp: Vector2, dt: float, final := false) -> bool:
	var to := wp - e.pos
	var d := to.length()
	var arrive_d := 0.7 if not final else 0.9
	if d <= arrive_d:
		return true
	var want := atan2(to.x, to.y)
	var turn := deg_to_rad(float(e.def.get("turn", 180.0))) * dt
	var diff := wrapf(want - e.yaw, -PI, PI)
	e.yaw = wrapf(e.yaw + clampf(diff, -turn, turn), -PI, PI)
	var facing := absf(wrapf(want - e.yaw, -PI, PI))
	var spd := e.speed
	if e.is_air():
		if facing > 1.2:
			spd *= 0.5
	elif e.cat() == "veh" and facing > 0.6:
		spd *= 0.15
	var step := minf(spd * dt, d)
	var np := e.pos + (to / d) * step
	if not e.is_air():
		if grid.is_solid_pos(np):
			var alt1 := Vector2(np.x, e.pos.y)
			var alt2 := Vector2(e.pos.x, np.y)
			if not grid.is_solid_pos(alt1):
				np = alt1
			elif not grid.is_solid_pos(alt2):
				np = alt2
			else:
				np = e.pos
	e.pos = np
	if e.is_air():
		if e.state != "return":
			var talt := float(e.def.get("alt", 10.0))
			e.alt = move_toward(e.alt, talt, 8.0 * dt)
	else:
		_separate(e, dt)
		if e.def.get("crusher", false):
			_crush(e)
	return e.pos.distance_to(wp) <= arrive_d

func _separate(e: Ent, dt: float) -> void:
	var push := Vector2.ZERO
	for o: Ent in query(e.pos, e.radius + 2.5):
		if o == e or o.is_building or o.is_air():
			continue
		var d := e.pos - o.pos
		var dist := d.length()
		var min_d := e.radius + o.radius
		if dist < min_d and dist > 0.001:
			push += d / dist * (min_d - dist)
		elif dist <= 0.001:
			push += Vector2(randf() - 0.5, randf() - 0.5)
	if push != Vector2.ZERO:
		var np := e.pos + push.limit_length(3.0 * dt + 0.3)
		if not grid.is_solid_pos(np):
			e.pos = np

func _crush(e: Ent) -> void:
	for o: Ent in query(e.pos, e.radius):
		if o == e or o.owner == e.owner or o.owner < 0 or not o.def.get("crushable", false):
			continue
		if o.pos.distance_to(e.pos) < e.radius * 0.9:
			_damage(o, 10000.0, "CRUSH", e)

func _follow_path(e: Ent, dt: float) -> bool:
	if e.path.is_empty():
		return true
	if e.path_i >= e.path.size():
		return true
	var last := e.path_i == e.path.size() - 1
	var wp := e.path[e.path_i]
	if last and not e.is_air():
		# crowd arrival: give up when close and boxed in by stopped friends
		var dg := e.pos.distance_to(wp)
		if dg < 4.0 + e.radius * 2.0:
			for o: Ent in query(e.pos, e.radius + 1.0):
				if o != e and not o.is_building and o.owner == e.owner and o.state != "move" and o.state != "amove" and o.pos.distance_to(e.pos) < e.radius + o.radius + 0.3:
					return true
	if _move_toward(e, wp, dt, last):
		e.path_i += 1
		if e.path_i >= e.path.size():
			return true
	# stuck detection
	if e.pos.distance_to(e.last_pos) < e.speed * dt * 0.1:
		e.stuck_t += dt
		if e.stuck_t > 1.5:
			e.stuck_t = 0.0
			var goal := e.path[e.path.size() - 1]
			_set_path(e, goal)
			if e.path.size() <= 1:
				return true
	else:
		e.stuck_t = 0.0
	return false

func _set_path(e: Ent, goal: Vector2) -> void:
	e.path_i = 0
	if e.is_air():
		e.path = PackedVector2Array([goal])
		return
	e.path = grid.find_path(e.pos, goal)
	if e.path.size() >= 1 and e.path[0].distance_to(e.pos) < 0.01:
		e.path.remove_at(0)
	if e.path.is_empty():
		e.path = PackedVector2Array([goal])

func _order_move(e: Ent, goal: Vector2, state := "move") -> void:
	e.state = state
	e.target_id = -1
	e.goal = goal
	e.landed = false
	_set_path(e, goal)

## Target scanning for idle / guard / attack-move. Returns true if attacking.
func _auto_acquire(e: Ent, dt: float) -> bool:
	e.acquire_t -= dt
	if e.acquire_t > 0.0:
		return e.state == "attack"
	e.acquire_t = 0.4
	if not e.has_weapons():
		return false
	if e.is_building and not e.powered and _needs_power(e):
		return false
	var rng := e.vision
	for w in e.weapon_ids():
		rng = maxf(rng, float(Data.WEAPONS[w]["range"]))
	var best: Ent = null
	var best_score := 1e18
	for o: Ent in query(e.pos, rng):
		if o == e or not o.alive or o.owner == e.owner or o.owner < 0:
			continue
		if _is_stealthed(o) and not o.detected:
			continue
		if _pick_weapon(e, o) < 0:
			continue
		var d := e.pos.distance_to(o.pos)
		if d > rng:
			continue
		var score := d
		if o.is_building:
			score += 40.0
		if not o.has_weapons():
			score += 10.0
		if score < best_score:
			best_score = score
			best = o
	if best == null:
		return false
	if e.state == "amove":
		e.resume = {"state": "amove", "goal": e.goal}
	elif e.state == "guard" or e.state == "idle":
		e.guard_pos = e.pos if e.state == "idle" else e.guard_pos
	e.state = "attack"
	e.target_id = best.id
	e.path = PackedVector2Array()
	e.repath_t = 0.0
	return true

func _needs_power(e: Ent) -> bool:
	for w in e.weapon_ids():
		if Data.WEAPONS[w].get("needs_power", false):
			return true
	return false

func _weapon_available(e: Ent, wid: String) -> bool:
	var wd: Dictionary = Data.WEAPONS[wid]
	if wd.has("upgrade") and e.owner >= 0 and not players[e.owner]["upgrades"].has(wd["upgrade"]):
		return false
	return true

## Best weapon index able to hit target t, or -1.
func _pick_weapon(e: Ent, t: Ent) -> int:
	var best := -1
	var best_dmg := -1.0
	var ws := e.weapon_ids()
	for i in range(ws.size()):
		var wd: Dictionary = Data.WEAPONS[ws[i]]
		if not _weapon_available(e, ws[i]):
			continue
		if t.is_air() and not t.landed:
			if not wd["aa"]:
				continue
		elif not wd["ag"]:
			continue
		var dmg: float = wd["dmg"] * Data.armor_mult(t.def.get("armor", ""), wd["type"])
		if dmg > best_dmg:
			best_dmg = dmg
			best = i
	if best_dmg <= 0.0:
		return -1
	return best

func _is_stealthed(e: Ent) -> bool:
	if not e.stealth:
		return false
	if time < e.revealed_until:
		return false
	if e.type == "pathfinder" and (e.state == "move" or e.state == "amove" or e.pos != e.last_pos):
		return false
	return true

func _do_attack(e: Ent, dt: float) -> void:
	var t: Ent = ents.get(e.target_id)
	if t == null or not t.alive or (_is_stealthed(t) and not t.detected and t.owner != e.owner):
		if e.is_building:
			e.state = "idle"
			e.target_id = -1
		else:
			_next_order(e)
		return
	var wi := _pick_weapon(e, t)
	if wi < 0:
		_next_order(e)
		return
	var wid: String = e.weapon_ids()[wi]
	var wd: Dictionary = Data.WEAPONS[wid]
	var rng: float = wd["range"]
	var min_rng: float = wd.get("min_range", 0.0)
	var d := edge_dist(e.pos, t)
	var want := atan2(t.pos.x - e.pos.x, t.pos.y - e.pos.y)
	if d <= rng and d >= min_rng - t.radius:
		# in range: aim and fire
		if e.def.get("turret", false):
			e.turret_yaw = want
		elif not e.is_building:
			var turn := deg_to_rad(float(e.def.get("turn", 180.0))) * dt * 2.0
			var diff := wrapf(want - e.yaw, -PI, PI)
			e.yaw = wrapf(e.yaw + clampf(diff, -turn, turn), -PI, PI)
			if absf(wrapf(want - e.yaw, -PI, PI)) > 0.5 and not e.is_air():
				return
		if e.is_building and not e.powered and wd.get("needs_power", false):
			return
		if e.cds[wi] <= 0.0 and (int(wd.get("clip", 0)) == 0 or e.clip[wi] > 0):
			_fire(e, wi, t)
		elif int(wd.get("clip", 0)) > 0 and e.clip[wi] <= 0 and float(wd.get("reload", 0.0)) < 0.0:
			# out of ammo: jets return to base
			e.ammo_empty = true
			e.target_id = -1
			_jet_go_home(e)
		return
	# out of range: chase
	if e.is_building or not e.can_move():
		return
	if not e.is_building and e.state == "attack" and e.resume.is_empty() and e.target_id >= 0 and e.pos.distance_to(e.guard_pos) > 26.0 and not e.is_air() and e.def.get("cat", "") != "air" and _was_auto(e):
		# wandered too far from post while auto-engaging
		e.target_id = -1
		_order_move(e, e.guard_pos)
		return
	e.repath_t -= dt
	if e.repath_t <= 0.0 or e.path.is_empty():
		e.repath_t = 0.6
		var goal := t.pos
		if t.is_building:
			goal = grid.center_of(grid.approach_cell(e.pos, t.pos, t.def["fp"]))
		_set_path(e, goal)
	_follow_path(e, dt)

func _was_auto(e: Ent) -> bool:
	return e.queue.is_empty() and e.guard_pos != Vector2.ZERO and not e.def.get("gatherer", false)

func _fire(e: Ent, wi: int, t: Ent) -> void:
	var wid: String = e.weapon_ids()[wi]
	var wd: Dictionary = Data.WEAPONS[wid]
	e.cds[wi] = float(wd["cd"])
	if int(wd.get("clip", 0)) > 0:
		e.clip[wi] -= 1
		if e.clip[wi] <= 0:
			var rl := float(wd.get("reload", 0.0))
			if rl > 0.0:
				e.reload_t[wi] = rl
	e.last_fire_t = time
	if e.stealth:
		e.revealed_until = time + 2.0
	var dmg: float = wd["dmg"] * e.vet_dmg()
	if e.owner >= 0 and wd["type"] == "JET_MISSILES" and players[e.owner]["upgrades"].has("laser_missiles"):
		dmg *= 1.25
	events.append({"k": "shot", "p": e.pos, "d": [e.id, wid, t.pos.x, t.pos.y, t.alt, t.id], "o": e.owner})
	var spd := float(wd.get("speed", 0.0))
	if spd <= 0.0:
		_apply_hit(e, wid, t, t.pos, dmg)
	else:
		var d := e.pos.distance_to(t.pos)
		shots.append({"t": time + d / spd, "wid": wid, "tid": t.id, "pos": t.pos, "dmg": dmg, "aid": e.id, "owner": e.owner})

func _tick_shots() -> void:
	if shots.is_empty():
		return
	var keep := []
	for s in shots:
		if time < s["t"]:
			keep.append(s)
			continue
		var a: Ent = ents.get(s["aid"])
		var t: Ent = ents.get(s["tid"])
		var pos: Vector2 = s["pos"]
		if t != null and t.alive:
			pos = t.pos
		_apply_hit(a, s["wid"], t, pos, s["dmg"], s["owner"])
	shots = keep

func _apply_hit(attacker: Ent, wid: String, target: Ent, pos: Vector2, dmg: float, owner := -2) -> void:
	var wd: Dictionary = Data.WEAPONS[wid]
	var own := owner if owner != -2 else (attacker.owner if attacker != null else -1)
	var alt := 0.0
	if target != null and target.alive:
		alt = target.alt
	events.append({"k": "hit", "p": pos, "d": [wid, pos.x, pos.y, alt], "o": own})
	var radius := float(wd.get("radius", 0.0))
	var radius2 := float(wd.get("radius2", 0.0))
	var dtype: String = wd["type"]
	if target != null and target.alive:
		_damage(target, dmg, dtype, attacker)
	if radius <= 0.0 and radius2 <= 0.0:
		return
	var r := maxf(radius, radius2)
	for o: Ent in query(pos, r):
		if o == target or not o.alive:
			continue
		if o.owner == own and own >= 0:
			continue
		if o.owner < 0 and dtype != "PARTICLE_BEAM":
			continue
		if o.is_air() and not o.landed and not wd["aa"]:
			continue
		var d := o.pos.distance_to(pos) - o.radius
		if d <= radius:
			_damage(o, dmg, dtype, attacker)
		elif d <= radius2:
			_damage(o, float(wd.get("dmg2", 0.0)), dtype, attacker)

func _damage(t: Ent, amount: float, dtype: String, attacker: Ent) -> void:
	if not t.alive:
		return
	var mult := Data.armor_mult(t.def.get("armor", ""), dtype)
	if t.owner < 0 and t.def.get("neutral", false) and not t.def.get("capturable", false):
		return
	t.hp -= amount * mult
	if t.owner >= 0 and attacker != null and attacker.owner != t.owner:
		var pl: Dictionary = players[t.owner]
		if time - pl["attack_msg_t"] > 8.0:
			pl["attack_msg_t"] = time
			session.s_msg(pl["peer"], "%s under attack!" % ("Base" if t.is_building else "Units"))
			events.append({"k": "alert", "p": t.pos, "d": [t.pos.x, t.pos.y], "o": t.owner, "only": t.owner})
		# passive units: retaliate / flee
		if not t.is_building and t.state == "idle" and t.has_weapons() and attacker.alive and _pick_weapon(t, attacker) >= 0:
			t.state = "attack"
			t.target_id = attacker.id
	if t.hp <= 0.0:
		destroy(t, "killed", attacker)

# ---- jets -------------------------------------------------------------------
func _jet_go_home(e: Ent) -> void:
	if e.home_id < 0 or ents.get(e.home_id) == null or not ents[e.home_id].alive:
		e.home_id = -1
		for b: Ent in ents.values():
			if b.alive and b.owner == e.owner and b.type == "airfield" and b.complete and _airfield_load(b) < int(b.def.get("pads", 4)):
				e.home_id = b.id
				break
	if e.home_id < 0:
		e.state = "idle"
		return
	e.state = "return"
	e.target_id = -1
	var home: Ent = ents[e.home_id]
	e.goal = _pad_pos(home, _pad_index(home, e))
	e.path = PackedVector2Array([e.goal])
	e.path_i = 0

func _airfield_load(b: Ent) -> int:
	var n := 0
	for o: Ent in ents.values():
		if o.alive and o.home_id == b.id:
			n += 1
	for q in b.prod:
		if Data.UNITS.get(q["type"], {}).get("jet", false):
			n += 1
	return n

func _pad_index(b: Ent, e: Ent) -> int:
	var i := 0
	for o: Ent in ents.values():
		if o.alive and o.home_id == b.id and o.is_jet():
			if o.id == e.id:
				return i
			i += 1
	return 0

func _do_return(e: Ent, dt: float) -> void:
	if e.home_id < 0:
		_jet_go_home(e)
		if e.home_id < 0:
			e.state = "idle"
			return
	var home: Ent = ents.get(e.home_id)
	if home == null or not home.alive:
		e.home_id = -1
		return
	e.goal = _pad_pos(home, _pad_index(home, e))
	var d := e.pos.distance_to(e.goal)
	if d < 12.0:
		e.alt = move_toward(e.alt, 0.0, 6.0 * dt)
		e.speed = float(e.def["speed"]) * 0.5
	if _move_toward(e, e.goal, dt, true) and e.alt < 0.5:
		e.landed = true
		e.state = "idle"
		e.speed = float(e.def["speed"])
		e.alt = 0.0
		e.yaw = 0.0
		for i in range(e.clip.size()):
			if e.clip[i] <= 0:
				e.reload_t[i] = 8.0
	elif d >= 12.0:
		e.speed = float(e.def["speed"])
		var talt := float(e.def.get("alt", 10.0))
		e.alt = move_toward(e.alt, talt, 8.0 * dt)

func _tick_landed_jet(e: Ent, dt: float) -> void:
	e.alt = 0.0
	var full := true
	for i in range(e.clip.size()):
		if e.clip[i] <= 0:
			full = false
	if full:
		e.ammo_empty = false
	if not e.queue.is_empty():
		var c: Dictionary = e.queue.pop_front()
		_apply_unit_cmd(e, c)

# ---- gathering ----------------------------------------------------------------
func _nearest_dock(e: Ent) -> Ent:
	var best: Ent = null
	var bd := 1e18
	for o: Ent in ents.values():
		if o.alive and o.type == "supply_dock" and o.boxes > 0:
			var d := o.pos.distance_squared_to(e.pos)
			if d < bd:
				bd = d
				best = o
	return best

func _nearest_center(e: Ent) -> Ent:
	var best: Ent = null
	var bd := 1e18
	for o: Ent in ents.values():
		if o.alive and o.owner == e.owner and o.type == "supply_center" and o.complete:
			var d := o.pos.distance_squared_to(e.pos)
			if d < bd:
				bd = d
				best = o
	return best

func _do_gather(e: Ent, dt: float) -> void:
	var cap := int(e.def.get("gatherer", 0))
	if e.carry < cap:
		var dock: Ent = ents.get(e.dock_id)
		if dock == null or not dock.alive or dock.boxes <= 0:
			dock = _nearest_dock(e)
			if dock == null:
				if e.carry > 0:
					e.carry = cap  # deliver what we have
					return
				e.state = "idle"
				return
			e.dock_id = dock.id
		var d := e.pos.distance_to(dock.pos)
		if d > dock.radius + 2.0:
			_move_toward(e, dock.pos + (e.pos - dock.pos).normalized() * (dock.radius + 1.0), dt)
			return
		e.alt = move_toward(e.alt, 3.0, 8.0 * dt)
		e.timer += dt
		if e.timer >= 1.2:
			e.timer = 0.0
			if dock.boxes > 0:
				dock.boxes -= 1
				e.carry += 1
			else:
				e.carry = cap
	else:
		var c: Ent = ents.get(e.center_id)
		if c == null or not c.alive:
			c = _nearest_center(e)
			if c == null:
				return
			e.center_id = c.id
		var d := e.pos.distance_to(c.pos)
		if d > 3.0:
			_move_toward(e, c.pos, dt)
			return
		e.alt = move_toward(e.alt, 3.0, 8.0 * dt)
		e.timer += dt
		if e.timer >= 1.0:
			e.timer = 0.0
			var val := float(e.carry * Data.BOX_VALUE) * float(players[e.owner]["income_mult"])
			players[e.owner]["cash"] += val
			events.append({"k": "cash", "p": c.pos, "d": [int(val)], "o": e.owner, "only": e.owner})
			e.carry = 0
			var dock: Ent = ents.get(e.dock_id)
			if dock == null or not dock.alive or dock.boxes <= 0:
				dock = _nearest_dock(e)
				e.dock_id = dock.id if dock != null else -1
			if e.dock_id < 0:
				e.state = "idle"

# ---- construction -------------------------------------------------------------
## Distance from a point to the edge of an entity (footprint rectangle for buildings).
func edge_dist(p: Vector2, t: Ent) -> float:
	if t.is_building:
		var fp: Vector2i = t.def["fp"]
		var dx := maxf(absf(p.x - t.pos.x) - fp.x, 0.0)
		var dy := maxf(absf(p.y - t.pos.y) - fp.y, 0.0)
		return sqrt(dx * dx + dy * dy)
	return p.distance_to(t.pos) - t.radius

func _approach_building(e: Ent, b: Ent, dt: float, reach := 2.6) -> bool:
	var d := edge_dist(e.pos, b)
	if d <= reach:
		e.path = PackedVector2Array()
		return true
	e.repath_t -= dt
	if e.path.is_empty() or e.repath_t <= 0.0:
		e.repath_t = 2.0
		_set_path(e, grid.center_of(grid.approach_cell(e.pos, b.pos, b.def["fp"])))
	_follow_path(e, dt)
	return false

func _do_build(e: Ent, dt: float) -> void:
	var site: Ent = ents.get(e.target_id)
	if site == null or not site.alive or site.complete:
		_next_order(e)
		return
	if not _approach_building(e, site, dt):
		return
	site.builder_id = e.id
	var want := atan2(site.pos.x - e.pos.x, site.pos.y - e.pos.y)
	e.yaw = lerp_angle(e.yaw, want, 5.0 * dt)
	site.progress += dt / float(site.def["time"])
	site.hp = maxf(site.hp, site.max_hp * (0.1 + 0.9 * clampf(site.progress, 0.0, 1.0)))
	if site.progress >= 1.0:
		_complete_building(site)
		_next_order(e)

func _complete_building(b: Ent) -> void:
	b.complete = true
	b.progress = 1.0
	b.hp = b.max_hp
	b.builder_id = -1
	_recompute_power(b.owner)
	session.s_msg(players[b.owner]["peer"], "%s complete" % b.def["name"])
	events.append({"k": "built", "p": b.pos, "d": [b.id], "o": b.owner})
	if b.def.has("free_unit"):
		var u := spawn(b.def["free_unit"], b.owner, b.pos + Vector2(0, 4))
		if u.def.get("gatherer", 0) > 0:
			u.state = "gather"
			u.center_id = b.id

func _do_repair(e: Ent, dt: float) -> void:
	var b: Ent = ents.get(e.target_id)
	if b == null or not b.alive or b.owner != e.owner:
		_next_order(e)
		return
	if not b.complete:
		e.state = "build"
		return
	if b.hp >= b.max_hp:
		_next_order(e)
		return
	if not _approach_building(e, b, dt):
		return
	var rate := b.max_hp / (float(b.def["time"]) * 1.5)
	b.hp = minf(b.max_hp, b.hp + rate * dt)

func _do_capture(e: Ent, dt: float) -> void:
	var b: Ent = ents.get(e.target_id)
	if b == null or not b.alive or b.owner == e.owner:
		_next_order(e)
		return
	if not _approach_building(e, b, dt):
		return
	if b.capture_by != e.owner:
		b.capture_by = e.owner
		b.capture_t = 0.0
	b.capture_t += dt
	if b.capture_t >= CAPTURE_TIME:
		var old := b.owner
		b.owner = e.owner
		b.capture_by = -1
		b.capture_t = 0.0
		b.prod.clear()
		b.research.clear()
		b.has_rally = false
		if b.def.has("capture_bonus") and old < 0:
			players[e.owner]["cash"] += float(b.def["capture_bonus"])
		session.s_msg(players[e.owner]["peer"], "%s captured" % b.def["name"])
		if old >= 0:
			session.s_msg(players[old]["peer"], "%s captured by the enemy!" % b.def["name"])
			_recompute_power(old)
		_recompute_power(e.owner)
		for p in range(players.size()):
			if known[p].has(b.id):
				_send_spawn(p, b)
		_next_order(e)

# ---------------------------------------------------------------------------
# Buildings
# ---------------------------------------------------------------------------
func _tick_building(e: Ent, dt: float) -> void:
	if not e.complete:
		if e.capture_by >= 0 and e.capture_t > 0.0:
			pass
		return
	if e.owner < 0:
		return
	var pl: Dictionary = players[e.owner]
	var rate := Data.LOW_POWER_SPEED if pl["low"] else 1.0
	if not e.prod.is_empty():
		var q: Dictionary = e.prod[0]
		q["t"] += dt * rate
		if q["t"] >= q["total"]:
			e.prod.pop_front()
			_produce(e, q["type"])
	if not e.research.is_empty():
		var r: Dictionary = e.research[0]
		r["t"] += dt * rate
		if r["t"] >= r["total"]:
			e.research.pop_front()
			_finish_upgrade(e, r["id"])
	if e.def.has("income"):
		e.income_t += dt
		if e.income_t >= float(e.def["income"]["every"]):
			e.income_t = 0.0
			var amt := float(e.def["income"]["amount"]) * float(pl["income_mult"])
			pl["cash"] += amt
			events.append({"k": "cash", "p": e.pos, "d": [int(amt)], "o": e.owner, "only": e.owner})
	if e.def.has("superweapon") and not e.sw_ready:
		if e.powered:
			e.sw_t += dt
			if e.sw_t >= float(e.def["superweapon"]):
				e.sw_ready = true
				session.s_msg(pl["peer"], "Particle Cannon ready")
	if e.has_weapons():
		for i in range(e.cds.size()):
			e.cds[i] = maxf(0.0, e.cds[i] - dt)
			if e.clip[i] <= 0 and e.reload_t[i] > 0.0:
				e.reload_t[i] -= dt
				if e.reload_t[i] <= 0.0:
					e.clip[i] = int(Data.WEAPONS[e.weapon_ids()[i]].get("clip", 0))
		if e.state == "attack":
			_do_attack(e, dt)
		else:
			_auto_acquire(e, dt)

func _produce(b: Ent, type: String) -> void:
	var d: Dictionary = Data.UNITS[type]
	var u: Ent
	if d.get("jet", false):
		var idx := 0
		for o: Ent in ents.values():
			if o.alive and o.home_id == b.id and o.is_jet():
				idx += 1
		u = spawn(type, b.owner, _pad_pos(b, idx))
		u.home_id = b.id
		u.landed = true
		u.alt = 0.0
		u.yaw = 0.0
	elif d.get("cat", "") == "air":
		u = spawn(type, b.owner, b.pos)
		u.alt = 0.5
		if d.get("gatherer", 0) > 0:
			u.state = "gather"
			u.center_id = b.id
		else:
			_order_move(u, b.rally)
	else:
		var ex := _exit_point(b)
		u = spawn(type, b.owner, ex)
		u.yaw = atan2(b.rally.x - ex.x, b.rally.y - ex.y)
		_order_move(u, b.rally + Vector2(randf_range(-2, 2), randf_range(-2, 2)))
	session.s_msg(players[b.owner]["peer"], "%s ready" % d["name"])

func _finish_upgrade(b: Ent, uid: String) -> void:
	var ud: Dictionary = Data.UPGRADES[uid]
	if ud.get("per_building", false):
		b.upg_done[uid] = true
	else:
		players[b.owner]["upgrades"][uid] = true
	match uid:
		"control_rods":
			_recompute_power(b.owner)
		"supply_lines":
			players[b.owner]["income_mult"] = 1.1
		"composite_armor":
			for o: Ent in ents.values():
				if o.alive and o.owner == b.owner and (o.type == "crusader" or o.type == "paladin"):
					var f := o.hp / o.max_hp
					o.max_hp = float(o.def["hp"]) * 1.25 * Data.VET_HP[o.level]
					o.hp = o.max_hp * f
	session.s_msg(players[b.owner]["peer"], "%s upgrade complete" % ud["name"])

func _tick_heal(dt: float) -> void:
	for h: Ent in ents.values():
		if not h.alive or h.owner < 0 or not h.def.has("heal"):
			continue
		if h.is_building and not h.complete:
			continue
		var hd: Dictionary = h.def["heal"]
		for o: Ent in query(h.pos, float(hd["radius"])):
			if o == h or o.owner != h.owner or o.is_building or o.cat() != hd["cat"]:
				continue
			if o.is_jet() and not o.landed:
				continue
			o.hp = minf(o.max_hp, o.hp + float(hd["rate"]) * dt)
	# heroic units self-heal
	for o: Ent in ents.values():
		if o.alive and not o.is_building and o.level >= 3:
			o.hp = minf(o.max_hp, o.hp + o.max_hp * 0.02 * dt)

# ---------------------------------------------------------------------------
# General's powers / superweapon
# ---------------------------------------------------------------------------
func _tick_strikes() -> void:
	if strikes.is_empty():
		return
	var keep := []
	for s in strikes:
		if time < s["t"]:
			keep.append(s)
			continue
		var p: Vector2 = s["p"]
		match s["k"]:
			"a10":
				var dir := Vector2.from_angle(s["heading"])
				for i in range(int(s["level"])):
					for j in range(-2, 3):
						var hp_ := p + dir * (j * 7.0) + dir.orthogonal() * ((i - 1) * 6.0)
						shots.append({"t": time + 0.15 * (j + 2), "wid": "a10_gun", "tid": -1, "pos": hp_, "dmg": 150.0, "aid": -1, "owner": s["owner"]})
			"fab":
				shots.append({"t": time, "wid": "fab", "tid": -1, "pos": p, "dmg": 600.0, "aid": -1, "owner": s["owner"]})
			"paradrop":
				for i in range(4):
					var c := grid.nearest_free(grid.cell_of(p + Vector2(randf_range(-4, 4), randf_range(-4, 4))))
					var u := spawn("ranger", s["owner"], grid.center_of(c))
					u.state = "guard"
					u.guard_pos = u.pos
	strikes = keep

func _tick_beams(dt: float) -> void:
	if beams.is_empty():
		return
	var keep := []
	for b in beams:
		if time >= b["until"]:
			continue
		var steer: Vector2 = players[b["owner"]]["sw_steer"]
		if steer.x >= 0.0:
			b["p"] = (b["p"] as Vector2).move_toward(steer, 7.0 * dt)
		b["next"] -= dt
		if b["next"] <= 0.0:
			b["next"] = 0.25
			var pos: Vector2 = b["p"]
			events.append({"k": "beam", "p": pos, "d": [pos.x, pos.y], "o": b["owner"], "all": true})
			for o: Ent in query(pos, 6.0):
				if o.alive and o.owner >= 0:
					var d := o.pos.distance_to(pos) - o.radius
					if d <= 6.0:
						_damage(o, 120.0 * 0.25, "PARTICLE_BEAM", null)
		keep.append(b)
	beams = keep

# ---------------------------------------------------------------------------
# Vision / fog
# ---------------------------------------------------------------------------
func _update_vision() -> void:
	for p in range(players.size()):
		var v: Vision = visions[p]
		v.clear()
		for e: Ent in ents.values():
			if not e.alive or e.owner != p:
				continue
			var r := e.vision
			if e.is_building and not e.complete:
				r = 12.0
			v.stamp(e.pos, r)
		var keep := []
		for r in v.reveals:
			if time < r["until"]:
				v.stamp(r["pos"], r["radius"])
				keep.append(r)
		v.reveals = keep
		session.s_fog(players[p]["peer"], v.packed())
		# ghost buildings that died out of sight
		var done := []
		for id in pending_despawn[p]:
			if v.visible(pending_despawn[p][id]):
				session.s_despawn(players[p]["peer"], id, "gone")
				known[p].erase(id)
				done.append(id)
		for id in done:
			pending_despawn[p].erase(id)
	# stealth detection (none of the M1 units are detectors; superweapon beams reveal)
	for e: Ent in ents.values():
		e.detected = false

func _visible_to(p: int, e: Ent) -> bool:
	if e.owner == p:
		return true
	if not visions[p].visible(e.pos):
		return false
	if e.owner >= 0 and _is_stealthed(e) and not e.detected:
		return false
	return true

# ---------------------------------------------------------------------------
# Replication
# ---------------------------------------------------------------------------
func _send_spawn(p: int, e: Ent) -> void:
	var extra := {"complete": e.complete}
	if e.is_building:
		extra["boxes"] = e.boxes
	session.s_spawn(players[p]["peer"], e.id, e.type, e.owner, e.pos.x, e.pos.y, e.alt, e.yaw, extra)
	known[p][e.id] = tick

func _send_snapshots() -> void:
	for p in range(players.size()):
		var buf := StreamPeerBuffer.new()
		buf.put_u32(tick)
		var count_pos := buf.get_position()
		buf.put_u16(0)
		var n := 0
		for e: Ent in ents.values():
			if not e.alive:
				continue
			if not _visible_to(p, e):
				continue
			if not known[p].has(e.id):
				_send_spawn(p, e)
			known[p][e.id] = tick
			buf.put_u16(e.id)
			buf.put_16(int(clampf(e.pos.x * 20.0, -32000, 32000)))
			buf.put_16(int(clampf(e.pos.y * 20.0, -32000, 32000)))
			buf.put_u16(int(clampf(e.alt * 20.0, 0, 65000)))
			buf.put_u8(int(wrapf(e.yaw, 0.0, TAU) / TAU * 255.0) & 255)
			buf.put_u8(int(wrapf(e.turret_yaw, 0.0, TAU) / TAU * 255.0) & 255)
			buf.put_u8(int(clampf(e.hp / e.max_hp, 0.0, 1.0) * 255.0))
			var flags := 0
			if e.pos != e.last_pos and not e.is_building:
				flags |= 1
			if time - e.last_fire_t < 0.3:
				flags |= 2
			if e.owner == p and _is_stealthed(e):
				flags |= 4
			if e.is_building and not e.complete:
				flags |= 8
			if e.is_building and not e.powered and e.owner >= 0 and players[e.owner]["low"]:
				flags |= 16
			if e.carry > 0:
				flags |= 32
			flags |= (e.level & 3) << 6
			buf.put_u8(flags)
			var aux := 0
			if e.is_building:
				if not e.complete:
					aux = int(clampf(e.progress, 0.0, 1.0) * 100.0)
				elif e.capture_by >= 0:
					aux = 100 + int(clampf(e.capture_t / CAPTURE_TIME, 0.0, 1.0) * 100.0)
			elif e.is_jet():
				aux = e.clip[0] if e.clip.size() > 0 else 0
			elif e.carry > 0:
				aux = e.carry
			buf.put_u8(aux)
			n += 1
		var end := buf.get_position()
		buf.seek(count_pos)
		buf.put_u16(n)
		buf.seek(end)
		session.s_state(players[p]["peer"], buf.data_array)
		# forget units that left view so they respawn cleanly later
		var forget := []
		for id in known[p]:
			if tick - known[p][id] > GHOST_TIMEOUT_TICKS:
				var e: Ent = ents.get(id)
				if e == null or not e.is_building:
					forget.append(id)
		for id in forget:
			known[p].erase(id)
		# events
		var evs := []
		for ev in events:
			if ev.has("only") and ev["only"] != p:
				continue
			if ev.get("all", false) or ev.get("o", -1) == p or visions[p].visible(ev["p"]) or ev.has("only"):
				evs.append([ev["k"], ev["d"]])
		if not evs.is_empty():
			session.s_events(players[p]["peer"], evs)
	events.clear()

func _send_pstates() -> void:
	var sw := {}
	for e: Ent in ents.values():
		if e.alive and e.is_building and e.def.has("superweapon") and e.complete and e.owner >= 0:
			var remaining := 0.0 if e.sw_ready else float(e.def["superweapon"]) - e.sw_t
			if not sw.has(e.owner) or remaining < sw[e.owner]:
				sw[e.owner] = remaining
	var docks := {}
	for e: Ent in ents.values():
		if e.alive and e.type == "supply_dock":
			docks[e.id] = e.boxes
	for p in range(players.size()):
		var pl: Dictionary = players[p]
		var st := {
			"cash": int(pl["cash"]), "pp": pl["pp"], "pu": pl["pu"], "low": pl["low"], "rank": pl["rank"], "xp": int(pl["xp"]),
			"next": Data.RANK_XP[pl["rank"]] if pl["rank"] < 5 else -1, "points": pl["points"], "powers": pl["powers"].duplicate(),
			"cds": {}, "upgrades": pl["upgrades"].keys(), "research": {}, "queues": {}, "rally": {}, "sw": sw, "docks": docks,
			"tick": tick, "time": time, "upg_done": {}, "hp": {}, "xp_units": {}, "beam": beams.size() > 0 and beams[0]["owner"] == p,
		}
		for pid in pl["cds"]:
			st["cds"][pid] = maxf(0.0, pl["cds"][pid] - time)
		for e: Ent in ents.values():
			if not e.alive or e.owner != p:
				continue
			if e.is_building:
				if not e.prod.is_empty():
					var q := []
					for it in e.prod:
						q.append([it["type"], it["t"] / it["total"]])
					st["queues"][e.id] = q
				if not e.research.is_empty():
					st["research"][e.id] = [e.research[0]["id"], e.research[0]["t"] / e.research[0]["total"]]
				if e.has_rally:
					st["rally"][e.id] = [e.rally.x, e.rally.y]
				if not e.upg_done.is_empty():
					st["upg_done"][e.id] = e.upg_done.keys()
			st["hp"][e.id] = [int(e.hp), int(e.max_hp)]
		session.s_pstate(pl["peer"], st)

func _check_victory() -> void:
	if game_over or time < 5.0:
		return
	var alive_players := []
	for p in range(players.size()):
		if players[p]["defeated"]:
			continue
		var n := 0
		for e: Ent in ents.values():
			if e.alive and e.owner == p and e.is_building and not e.def.get("neutral", false):
				n += 1
		if n == 0:
			players[p]["defeated"] = true
			session.s_msg(players[p]["peer"], "All structures lost")
		else:
			alive_players.append(p)
	if solo:
		if alive_players.is_empty():
			game_over = true
			session.s_gameover(-1)
		return
	if alive_players.size() <= 1:
		game_over = true
		winner = alive_players[0] if alive_players.size() == 1 else -1
		session.s_gameover(winner)

# ---------------------------------------------------------------------------
# Commands (from clients)
# ---------------------------------------------------------------------------
func cmd(p: int, c: Dictionary) -> void:
	if p < 0 or game_over:
		return
	var t: String = c.get("t", "")
	match t:
		"move", "amove", "attack", "stop", "guard", "gather", "repair", "capture":
			var q: bool = c.get("q", false)
			for id in c.get("ids", []):
				var e: Ent = ents.get(int(id))
				if e == null or not e.alive or e.owner != p or e.is_building:
					continue
				if q and e.state != "idle":
					e.queue.append(c)
				else:
					e.queue.clear()
					e.resume = {}
					_apply_unit_cmd(e, c)
		"build":
			_cmd_build(p, c)
		"produce":
			_cmd_produce(p, c)
		"cancel":
			_cmd_cancel(p, c)
		"rally":
			var b: Ent = ents.get(int(c.get("id", -1)))
			if b != null and b.alive and b.owner == p and b.is_building:
				b.rally = Vector2(float(c["x"]), float(c["y"]))
				b.has_rally = true
		"sell":
			_cmd_sell(p, c)
		"upgrade":
			_cmd_upgrade(p, c)
		"cancel_upgrade":
			var b: Ent = ents.get(int(c.get("id", -1)))
			if b != null and b.alive and b.owner == p and not b.research.is_empty():
				var r: Dictionary = b.research.pop_back()
				players[p]["cash"] += float(Data.UPGRADES[r["id"]]["cost"])
		"buy_power":
			_cmd_buy_power(p, c)
		"power":
			_cmd_power(p, c)
		"sw":
			_cmd_superweapon(p, c)
		"sw_steer":
			players[p]["sw_steer"] = Vector2(float(c["x"]), float(c["y"]))
		"cheat_cash":
			if solo:
				players[p]["cash"] += 10000.0

func _apply_unit_cmd(e: Ent, c: Dictionary) -> void:
	var t: String = c["t"]
	var ids: Array = c.get("ids", [])
	match t:
		"move", "amove":
			var goal := Vector2(float(c["x"]), float(c["y"]))
			goal = _formation_goal(e, ids, goal)
			if e.is_jet() and e.landed:
				e.landed = false
			if e.is_building or not e.can_move():
				return
			_order_move(e, goal, t)
		"attack":
			var tgt: Ent = ents.get(int(c.get("tid", -1)))
			if tgt == null or not tgt.alive or tgt.owner == e.owner:
				return
			if tgt.owner < 0 and tgt.def.get("neutral", false) and not tgt.def.get("capturable", false):
				return
			if _pick_weapon(e, tgt) < 0:
				if e.can_move():
					_order_move(e, tgt.pos)
				return
			e.state = "attack"
			e.target_id = tgt.id
			e.landed = false
			e.path = PackedVector2Array()
			e.repath_t = 0.0
			e.guard_pos = Vector2.ZERO
		"stop":
			e.clear_orders()
			e.resume = {}
			e.guard_pos = e.pos
		"guard":
			e.clear_orders()
			e.state = "guard"
			e.guard_pos = e.pos
		"gather":
			if e.def.get("gatherer", 0) <= 0:
				return
			var dock: Ent = ents.get(int(c.get("tid", -1)))
			e.state = "gather"
			e.dock_id = dock.id if dock != null and dock.type == "supply_dock" else -1
			e.target_id = -1
		"repair":
			if not e.def.get("builder", false):
				return
			var b: Ent = ents.get(int(c.get("tid", -1)))
			if b == null or not b.alive or not b.is_building or b.owner != e.owner:
				return
			e.state = "repair" if b.complete else "build"
			e.target_id = b.id
			e.path = PackedVector2Array()
			e.repath_t = 0.0
		"capture":
			if e.type != "ranger" or not players[e.owner]["upgrades"].has("capture"):
				return
			var b: Ent = ents.get(int(c.get("tid", -1)))
			if b == null or not b.alive or not b.is_building or b.owner == e.owner or b.type == "supply_dock":
				return
			if b.owner >= 0 and not b.complete:
				return
			e.state = "capture"
			e.target_id = b.id
			e.path = PackedVector2Array()
			e.repath_t = 0.0

## Spread a group destination into a loose formation so units don't all fight for one cell.
func _formation_goal(e: Ent, ids: Array, goal: Vector2) -> Vector2:
	var n := ids.size()
	if n <= 1:
		return goal
	var idx := ids.find(e.id)
	if idx < 0:
		idx = 0
	var cols := int(ceil(sqrt(float(n))))
	var spacing := 2.2 + e.radius * 1.2
	var row := idx / cols
	var col := idx % cols
	var off := Vector2((col - (cols - 1) * 0.5) * spacing, (row - (ceil(float(n) / cols) - 1) * 0.5) * spacing)
	var g := goal + off
	g.x = clampf(g.x, 2.0, map_size - 2.0)
	g.y = clampf(g.y, 2.0, map_size - 2.0)
	if e.is_air():
		return g
	if grid.is_solid_pos(g):
		return grid.center_of(grid.nearest_free(grid.cell_of(g)))
	return g

func _cmd_build(p: int, c: Dictionary) -> void:
	var dz: Ent = ents.get(int(c.get("id", -1)))
	var type: String = c.get("type", "")
	if dz == null or not dz.alive or dz.owner != p or not dz.def.get("builder", false):
		return
	if not Data.BUILDINGS.has(type) or Data.BUILDINGS[type].get("neutral", false):
		return
	var d: Dictionary = Data.BUILDINGS[type]
	var why := prereqs_met(p, type)
	if why != "":
		session.s_msg(players[p]["peer"], why)
		return
	var pl: Dictionary = players[p]
	if pl["cash"] < float(d["cost"]):
		session.s_msg(pl["peer"], "Insufficient funds")
		return
	var pos := PathGrid.snap_center(Vector2(float(c["x"]), float(c["y"])), d["fp"])
	if not placement_ok(p, type, pos):
		session.s_msg(pl["peer"], "Cannot build there")
		return
	pl["cash"] -= float(d["cost"])
	var site := spawn(type, p, pos, false)
	site.builder_id = dz.id
	dz.queue.clear()
	dz.resume = {}
	dz.state = "build"
	dz.target_id = site.id
	dz.path = PackedVector2Array()
	dz.repath_t = 0.0
	events.append({"k": "place", "p": pos, "d": [site.id], "o": p})

func placement_ok(p: int, type: String, pos: Vector2) -> bool:
	var d: Dictionary = Data.BUILDINGS[type]
	var fp: Vector2i = d["fp"]
	var half := Vector2(fp) * 1.0
	if pos.x - half.x < 6.0 or pos.y - half.y < 6.0 or pos.x + half.x > map_size - 6.0 or pos.y + half.y > map_size - 6.0:
		return false
	if not grid.footprint_free(pos, fp, 1):
		return false
	# units standing in the footprint (other than air) block placement
	for o: Ent in query(pos, maxf(half.x, half.y) + 1.0):
		if o.is_building or o.is_air():
			continue
		if absf(o.pos.x - pos.x) < half.x + o.radius and absf(o.pos.y - pos.y) < half.y + o.radius:
			return false
	if type == "supply_center":
		return true
	# must be near an existing own structure (Generals lets you build anywhere; keep a generous radius so bases stay coherent)
	return true

func _cmd_produce(p: int, c: Dictionary) -> void:
	var b: Ent = ents.get(int(c.get("id", -1)))
	var type: String = c.get("type", "")
	if b == null or not b.alive or b.owner != p or not b.complete or not Data.UNITS.has(type):
		return
	if not b.def.get("produces", []).has(type):
		return
	var pl: Dictionary = players[p]
	var d: Dictionary = Data.UNITS[type]
	var why := prereqs_met(p, type)
	if why != "":
		session.s_msg(pl["peer"], why)
		return
	if b.prod.size() >= Data.MAX_QUEUE:
		return
	if d.get("jet", false) and _airfield_load(b) >= int(b.def.get("pads", 4)):
		session.s_msg(pl["peer"], "Airfield full")
		return
	if pl["cash"] < float(d["cost"]):
		session.s_msg(pl["peer"], "Insufficient funds")
		return
	pl["cash"] -= float(d["cost"])
	b.prod.append({"type": type, "t": 0.0, "total": float(d["time"])})

func _cmd_cancel(p: int, c: Dictionary) -> void:
	var b: Ent = ents.get(int(c.get("id", -1)))
	if b == null or not b.alive or b.owner != p:
		return
	var i := int(c.get("i", -1))
	if i < 0 or i >= b.prod.size():
		i = b.prod.size() - 1
	if i < 0:
		return
	var q: Dictionary = b.prod[i]
	b.prod.remove_at(i)
	players[p]["cash"] += float(Data.UNITS[q["type"]]["cost"])

func _cmd_sell(p: int, c: Dictionary) -> void:
	var b: Ent = ents.get(int(c.get("id", -1)))
	if b == null or not b.alive or b.owner != p or not b.is_building or b.def.get("neutral", false):
		return
	var refund := float(b.def["cost"]) * (Data.REFUND if b.complete else (1.0 - clampf(b.progress, 0.0, 1.0)))
	for q in b.prod:
		refund += float(Data.UNITS[q["type"]]["cost"])
	for r in b.research:
		refund += float(Data.UPGRADES[r["id"]]["cost"])
	players[p]["cash"] += refund
	b.sold = true
	destroy(b, "sold")
	session.s_msg(players[p]["peer"], "%s sold for $%d" % [b.def["name"], int(refund)])

func _cmd_upgrade(p: int, c: Dictionary) -> void:
	var b: Ent = ents.get(int(c.get("id", -1)))
	var uid: String = c.get("uid", "")
	if b == null or not b.alive or b.owner != p or not b.complete or not Data.UPGRADES.has(uid):
		return
	if not b.def.get("upgrades", []).has(uid):
		return
	var pl: Dictionary = players[p]
	var ud: Dictionary = Data.UPGRADES[uid]
	if ud.get("per_building", false):
		if b.upg_done.has(uid):
			return
		for r in b.research:
			if r["id"] == uid:
				return
	else:
		if pl["upgrades"].has(uid):
			return
		for o: Ent in ents.values():
			if o.alive and o.owner == p and o.is_building:
				for r in o.research:
					if r["id"] == uid:
						return
	if pl["cash"] < float(ud["cost"]):
		session.s_msg(pl["peer"], "Insufficient funds")
		return
	pl["cash"] -= float(ud["cost"])
	b.research.append({"id": uid, "t": 0.0, "total": float(ud["time"])})

func _cmd_buy_power(p: int, c: Dictionary) -> void:
	var pid: String = c.get("pid", "")
	if not Data.POWERS.has(pid):
		return
	var pl: Dictionary = players[p]
	var pd: Dictionary = Data.POWERS[pid]
	if pd.get("auto", false):
		return
	if pl["rank"] < int(pd["rank"]) or pl["points"] <= 0:
		return
	var lvl := int(pl["powers"].get(pid, 0))
	if lvl >= int(pd.get("levels", 1)):
		return
	pl["points"] -= 1
	pl["powers"][pid] = lvl + 1
	session.s_msg(pl["peer"], "%s acquired" % pd["name"])

func _cmd_power(p: int, c: Dictionary) -> void:
	var pid: String = c.get("pid", "")
	if not Data.POWERS.has(pid):
		return
	var pl: Dictionary = players[p]
	var pd: Dictionary = Data.POWERS[pid]
	if pd["kind"] != "ability" or int(pl["powers"].get(pid, 0)) <= 0:
		return
	if not has_building(p, "command_center"):
		session.s_msg(pl["peer"], "Requires a Command Center")
		return
	if float(pl["cds"].get(pid, 0.0)) > time:
		return
	var pos := Vector2(clampf(float(c["x"]), 0.0, map_size), clampf(float(c["y"]), 0.0, map_size))
	pl["cds"][pid] = time + float(pd["cd"])
	match pid:
		"spy_satellite":
			visions[p].reveals.append({"pos": pos, "radius": float(pd["radius"]), "until": time + 15.0})
			events.append({"k": "strike", "p": pos, "d": [pid, pos.x, pos.y, 0.0], "o": p, "all": true})
		"a10":
			var heading := randf() * TAU
			strikes.append({"k": "a10", "p": pos, "t": time + 4.0, "owner": p, "level": int(pl["powers"][pid]), "heading": heading})
			events.append({"k": "strike", "p": pos, "d": [pid, pos.x, pos.y, heading, int(pl["powers"][pid])], "o": p, "all": true})
		"emergency_repair":
			for o: Ent in query(pos, float(pd["radius"])):
				if o.alive and o.owner == p and not o.is_building and o.cat() != "inf":
					o.hp = o.max_hp
			events.append({"k": "strike", "p": pos, "d": [pid, pos.x, pos.y, 0.0], "o": p, "all": true})
		"paradrop":
			strikes.append({"k": "paradrop", "p": pos, "t": time + 6.0, "owner": p})
			events.append({"k": "strike", "p": pos, "d": [pid, pos.x, pos.y, 0.0], "o": p, "all": true})
		"fuel_air_bomb":
			strikes.append({"k": "fab", "p": pos, "t": time + 8.0, "owner": p})
			events.append({"k": "strike", "p": pos, "d": [pid, pos.x, pos.y, 0.0], "o": p, "all": true})
			for o in range(players.size()):
				if o != p:
					session.s_msg(players[o]["peer"], "Warning: enemy Fuel Air Bomb inbound!")

func _cmd_superweapon(p: int, c: Dictionary) -> void:
	var b: Ent = ents.get(int(c.get("id", -1)))
	if b == null or not b.alive or b.owner != p or not b.def.has("superweapon") or not b.sw_ready or not b.powered:
		return
	var pos := Vector2(clampf(float(c["x"]), 0.0, map_size), clampf(float(c["y"]), 0.0, map_size))
	b.sw_ready = false
	b.sw_t = 0.0
	players[p]["sw_steer"] = Vector2(-1, -1)
	beams.append({"owner": p, "p": pos, "until": time + 7.0, "next": 0.0})
	for o in range(players.size()):
		session.s_msg(players[o]["peer"], "Particle Cannon fired" if o == p else "Warning: enemy Particle Cannon fired!")
