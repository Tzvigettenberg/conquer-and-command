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
const GUARD_RADIUS := 36.0
const ASSIST_RADIUS := 45.0      # idle units this close to an attacked friend join the fight
const SCRAMBLE_RADIUS := 130.0
const PATRIOT_LINK := 40.0       # Patriots this close share targets (Zero Hour RequestAssistRange 175 x 0.2 m)   # parked aircraft launch when something this close to their airfield is hit
const ORPHAN_DRAIN := 0.035      # fraction of max hp lost per second by jets with no airfield
const TURRET_RATE := 150.0       # deg/s turret traverse
const RETALIATE_LEASH := 40.0

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
var next_sid := 1                  # shot ids (client matches projectiles for mid-air intercepts)
var spatial: Dictionary = {}
var known: Array = []              # per player: id -> last tick included
var pending_despawn: Array = []    # per player: id -> pos (ghost buildings)
var dead_list: Array = []
var game_over := false
var winner := -1
var solo := false
var debug := false
var bots: Array = []             # Bot instances (server-side AI players)
var options: Dictionary = {}
var paused := false

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
func start(_session: Node, peers: Array, names: Array, opts: Dictionary = {}) -> void:
	session = _session
	options = opts
	map = MapGen.build(str(opts.get("map", "desert2")), peers.size())
	map_size = map["size"]
	grid.setup(map_size)
	solo = peers.size() == 1
	var start_cash := float(opts.get("cash", Data.STARTING_CASH))
	var teams: Array = opts.get("teams", [])
	var levels: Array = opts.get("levels", [])
	# spawn slot per player (index into map starts); default = player order
	var slots: Array = opts.get("slots", [])
	var used_slots := {}
	for i in range(peers.size()):
		var sl: int = int(slots[i]) if i < slots.size() else -1
		if sl < 0 or sl >= map["starts"].size() or used_slots.has(sl):
			sl = 0
			while used_slots.has(sl):
				sl += 1
		used_slots[sl] = true
		if i < slots.size():
			slots[i] = sl
		else:
			slots.append(sl)
	for i in range(peers.size()):
		players.append({
			"peer": peers[i], "name": names[i], "cash": start_cash, "xp": 0.0, "rank": 1, "points": 1, "lost_msg_t": -100.0,
			"stats": {"units_built": 0, "units_lost": 0, "units_killed": 0, "bld_built": 0, "bld_lost": 0, "bld_killed": 0, "cash_earned": 0},
			"team": int(teams[i]) if i < teams.size() else i,
			"slot": int(slots[i]), "level": str(levels[i]) if i < levels.size() else str(opts.get("ai", "medium")),
			"powers": {}, "cds": {}, "upgrades": {}, "defeated": false, "pp": 0, "pu": 0, "low": false,
			"sw_steer": Vector2(-1, -1), "attack_msg_t": -100.0, "income_mult": 1.0, "plan": "",
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
	for rd in map.get("ridges", []):
		grid.set_cells(PathGrid.capsule_cells(rd["a"], rd["b"], float(rd["w"]) + 0.5), true)
	for d in map["docks"]:
		var e := spawn("supply_dock", -1, d["p"])
		e.boxes = d["boxes"]
	for p in map["derricks"]:
		spawn("oil_derrick", -1, p)
	for i in range(players.size()):
		var sl: int = players[i]["slot"]
		var s: Vector2 = map["starts"][sl]
		var cc := spawn("command_center", i, PathGrid.snap_center(s, Data.BUILDINGS["command_center"]["fp"]), true, map["start_yaw"][sl])
		var ex := _exit_point(cc)
		var dz := spawn("dozer", i, ex)
		dz.yaw = map["start_yaw"][sl]
		_recompute_power(i)
	grid.flush()
	map["player_names"] = names.duplicate()
	map["player_teams"] = _teams_array()
	map["player_slots"] = slots.duplicate()
	for i in range(players.size()):
		if peers[i] == -1:
			var b := Bot.new()
			b.setup(self, i, str(players[i]["level"]))
			bots.append(b)
		else:
			session.s_map(players[i]["peer"], map, i)
	_update_vision()

## Same player or same lobby team. Neutral (-1) is never allied.
func allied(a: int, b: int) -> bool:
	if a == b:
		return true
	if a < 0 or b < 0 or a >= players.size() or b >= players.size():
		return false
	return players[a]["team"] == players[b]["team"]

## Vision shared across a team.
func team_visible(p: int, pos: Vector2) -> bool:
	for i in range(players.size()):
		if allied(p, i) and visions[i].visible(pos):
			return true
	return false

func player_of_peer(peer: int) -> int:
	for i in range(players.size()):
		if players[i]["peer"] == peer:
			return i
	return -1

# ---------------------------------------------------------------------------
# Entities
# ---------------------------------------------------------------------------
func spawn(type: String, owner: int, pos: Vector2, complete := true, yaw := 0.0) -> Ent:
	var e := Ent.new()
	e.setup(next_id, type, owner, pos)
	next_id += 1
	e.yaw = yaw
	if e.is_building:
		e.cells = PathGrid.footprint_cells(pos, e.def["fp"], yaw)
		grid.set_cells(e.cells, true)
		e.complete = complete
		if not complete:
			e.hp = e.max_hp * 0.1
			e.progress = 0.0
		var fp: Vector2i = e.def["fp"]
		e.rally = pos + Vector2(sin(yaw), cos(yaw)) * (fp.y + 5.0)
		e.has_rally = false
	else:
		if e.is_air():
			e.alt = float(e.def.get("alt", 10.0))
			e.flight = "fly"
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
	for id in e.cargo:
		var u: Ent = ents.get(id)
		if u != null and u.alive:
			u.inside_id = -1
			destroy(u, "killed", killer)
	e.cargo.clear()
	if e.inside_id >= 0:
		var car: Ent = ents.get(e.inside_id)
		if car != null:
			car.cargo.erase(e.id)
	if e.is_building:
		grid.set_cells(e.cells, false)
		if e.def.get("plans", false):
			_recompute_plans()
		# jets homed here lose their pads
		for o: Ent in ents.values():
			if o.alive and o.home_id == e.id:
				o.home_id = -1
				o.flight = "fly" if o.flight in ["parked", "taxi", "taxi_in"] else o.flight
	if e.owner >= 0 and reason == "killed":
		players[e.owner]["stats"]["bld_lost" if e.is_building else "units_lost"] += 1
	if killer != null and killer.owner >= 0 and killer.owner != e.owner and e.owner >= 0:
		players[killer.owner]["stats"]["bld_killed" if e.is_building else "units_killed"] += 1
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
		elif reason == "killed":
			var pl: Dictionary = players[e.owner]
			if time - float(pl["lost_msg_t"]) > 2.5:
				pl["lost_msg_t"] = time
				session.s_msg(pl["peer"], "Unit lost: %s" % e.def["name"])
		# units targeting it are handled lazily in _do_attack

func _flush_dead() -> void:
	if dead_list.is_empty():
		return
	for e: Ent in dead_list:
		ents.erase(e.id)
	dead_list.clear()

func _exit_point(b: Ent) -> Vector2:
	var fp: Vector2i = b.def["fp"]
	var p := b.pos + Vector2(sin(b.yaw), cos(b.yaw)) * (fp.y + 1.5)
	var c := grid.nearest_free(grid.cell_of(p))
	return grid.center_of(c)

## Hangar bays (back row of the airfield, local z = -4.5).
func _pad_pos(air: Ent, idx: int) -> Vector2:
	var offs := [Vector2(-8.0, -4.5), Vector2(-2.7, -4.5), Vector2(2.7, -4.5), Vector2(8.0, -4.5)]
	return air.pos + offs[clampi(idx, 0, 3)].rotated(-air.yaw)

## Where jets line up for takeoff / touch down (start of the runway, front row).
func _runway_start(air: Ent) -> Vector2:
	return air.pos + Vector2(-9.5, 4.5).rotated(-air.yaw)

## Helipad at the tower end.
func _helipad_pos(air: Ent) -> Vector2:
	return air.pos + Vector2(8.5, 4.5).rotated(-air.yaw)

## Runway direction (unit vector) of an airfield: along its local +X.
func _runway_dir(air: Ent) -> Vector2:
	return Vector2(cos(air.yaw), -sin(air.yaw))

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
	if d.has("superweapon") and not bool(options.get("superweapons", true)):
		return "Superweapons are disabled in this match"
	return ""

# ---------------------------------------------------------------------------
# Spatial hash
# ---------------------------------------------------------------------------
func _build_spatial() -> void:
	spatial.clear()
	for e: Ent in ents.values():
		if not e.alive or e.inside_id >= 0:
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
	for b in bots:
		b.think(dt)
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
	if e.inside_id >= 0:
		# riding: follow the transport, fire out of it if it has fire ports
		var car: Ent = ents.get(e.inside_id)
		if car == null or not car.alive:
			e.inside_id = -1
			return
		e.pos = car.pos
		e.alt = car.alt
		e.last_pos = e.pos
		if car.def.get("fire_ports", false) and e.has_weapons():
			_tick_passenger(e, car, dt)
		return
	if e.is_jet():
		_tick_jet(e, dt)
		e.last_pos = e.pos
		return
	if not e.is_air() and grid.is_solid_pos(e.pos):
		# somehow inside an obstacle (spawned there, pushed there): walk out to the nearest free cell
		var free := grid.center_of(grid.nearest_free(grid.cell_of(e.pos)))
		e.pos = e.pos.move_toward(free, maxf(e.speed, 2.0) * dt)
	if e.def.get("turret", false) and e.state != "attack" and e.state != "attack_ground":
		# turret settles back to the hull heading
		var turn := deg_to_rad(90.0) * dt
		var diff := wrapf(e.yaw - e.turret_yaw, -PI, PI)
		e.turret_yaw = wrapf(e.turret_yaw + clampf(diff, -turn, turn), -PI, PI)
	match e.state:
		"idle":
			if e.has_weapons():
				_auto_acquire(e, dt)
			elif e.def.get("builder", false):
				e.acquire_t -= dt
				if e.acquire_t <= 0.0:
					e.acquire_t = 1.5
					_dozer_auto_repair(e)
		"guard":
			if not e.path.is_empty() and e.path_i < e.path.size():
				_follow_path(e, dt)
			elif e.has_weapons():
				_auto_acquire(e, dt)
		"move":
			if _follow_path(e, dt):
				_next_order(e)
		"amove":
			if not _auto_acquire(e, dt):
				if _follow_path(e, dt):
					_next_order(e)
		"attack":
			_do_attack(e, dt)
		"attack_ground":
			_do_attack_ground(e, dt)
		"gather":
			_do_gather(e, dt)
		"board":
			_do_board(e, dt)
		"unload":
			_do_unload(e, dt)
		"pickup":
			# transport landed for boarding: wait for the walkers, then lift off again
			e.alt = move_toward(e.alt, 0.5, 6.0 * dt)
			e.timer -= dt
			if e.timer <= 0.0:
				e.state = "idle"
		"build":
			_do_build(e, dt)
		"repair":
			_do_repair(e, dt)
		"capture":
			_do_capture(e, dt)
	e.last_pos = e.pos

## Idle dozers fix up damaged friendly structures nearby on their own.
func _dozer_auto_repair(e: Ent) -> void:
	var best: Ent = null
	var bd := 1e18
	for o: Ent in query(e.pos, 36.0):
		if not o.alive or not o.is_building or not o.complete or o.sold or o.owner < 0 or not allied(o.owner, e.owner):
			continue
		if o.hp >= o.max_hp * 0.98 or o.def.get("neutral", false):
			continue
		var d := o.pos.distance_squared_to(e.pos)
		if d < bd:
			bd = d
			best = o
	if best != null:
		e.state = "repair"
		e.target_id = best.id
		e.path = PackedVector2Array()
		e.repath_t = 0.0
		e.guard_pos = e.pos

func _next_order(e: Ent) -> void:
	e.state = "idle"
	e.target_id = -1
	e.path = PackedVector2Array()
	e.path_i = 0
	if not e.resume.is_empty():
		var r: Dictionary = e.resume
		e.resume = {}
		if r["state"] == "guard":
			e.state = "guard"
			e.guard_pos = r["goal"]
			e.guard_radius = float(r.get("r", GUARD_RADIUS))
			if not e.is_jet():
				_set_path(e, e.guard_pos)
			return
		_order_move(e, r["goal"], r["state"])
		return
	e.guard_pos = e.pos
	e.guard_radius = 0.0
	if not e.queue.is_empty():
		var c: Dictionary = e.queue.pop_front()
		_apply_unit_cmd(e, c)

## Default guard radius: the unit's longest weapon range (at least the old default).
func _guard_reach(e: Ent) -> float:
	var r := GUARD_RADIUS
	for w in e.weapon_ids():
		r = maxf(r, _range(e, Data.WEAPONS[w]) + 4.0)
	return r

## Traverse the turret toward a heading at TURRET_RATE.
func _aim_turret(e: Ent, want: float, dt: float) -> bool:
	var turn := deg_to_rad(TURRET_RATE) * dt
	var diff := wrapf(want - e.turret_yaw, -PI, PI)
	e.turret_yaw = wrapf(e.turret_yaw + clampf(diff, -turn, turn), -PI, PI)
	return absf(wrapf(want - e.turret_yaw, -PI, PI)) < 0.12

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
	var moving := e.state != "idle" and e.state != "guard"
	for o: Ent in query(e.pos, e.radius + 2.5):
		if o == e or o.is_building or o.is_air():
			continue
		var d := e.pos - o.pos
		var dist := d.length()
		var min_d := e.radius + o.radius
		if dist < min_d and dist > 0.001:
			push += d / dist * (min_d - dist)
			# a parked friend in the way steps aside instead of blocking the mover
			if moving and allied(o.owner, e.owner) and (o.state == "idle" or o.state == "guard") and not o.is_building and o.can_move():
				var side := Vector2(-d.y, d.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
				var op := o.pos - d / dist * (min_d - dist) * 0.6 + side * 0.5
				if not grid.is_solid_pos(op):
					o.pos = op
		elif dist <= 0.001:
			push += Vector2(randf() - 0.5, randf() - 0.5)
	if push != Vector2.ZERO:
		var np := e.pos + push.limit_length(3.0 * dt + 0.3)
		if not grid.is_solid_pos(np):
			e.pos = np

## Idle / guarding friendlies within reach of a stuck mover take a short step
## sideways (so a dozer never sits behind a parked tank forever).
func _nudge_idle_friends(e: Ent) -> void:
	var fwd := _fwd(e.yaw)
	for o: Ent in query(e.pos, e.radius + 4.0):
		if o == e or o.is_building or o.is_air() or not o.can_move() or not allied(o.owner, e.owner):
			continue
		if o.state != "idle" and o.state != "guard":
			continue
		var d := o.pos - e.pos
		if d.length() > e.radius + o.radius + 2.0:
			continue
		var side := Vector2(-fwd.y, fwd.x)
		if d.dot(side) < 0.0:
			side = -side
		var goal := o.pos + side * (o.radius + e.radius + 1.5) + fwd * 0.5
		var c := grid.cell_of(goal)
		if grid.is_solid(c):
			c = grid.nearest_free(c)
		var was_guard := o.state == "guard"
		var gp := o.guard_pos
		var gr := o.guard_radius
		_order_move(o, grid.center_of(c))
		if was_guard:
			o.resume = {"state": "guard", "goal": gp, "r": gr}

func _crush(e: Ent) -> void:
	for o: Ent in query(e.pos, e.radius):
		if o == e or allied(o.owner, e.owner) or o.owner < 0 or not o.def.get("crushable", false):
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
	# stuck detection: shove parked friends out of the way, then re-path
	if e.pos.distance_to(e.last_pos) < e.speed * dt * 0.1:
		e.stuck_t += dt
		if e.stuck_t > 0.8:
			_nudge_idle_friends(e)
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
	_set_path(e, goal)

## Target scanning for idle / guard / attack-move. Returns true if attacking.
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
		rng = maxf(rng, _range(e, Data.WEAPONS[w]))
	var centre := e.pos
	if e.state == "guard" and e.guard_radius > 0.0:
		centre = e.guard_pos
		rng = maxf(rng, e.guard_radius + 10.0)
	var best: Ent = null
	var best_score := 1e18
	for o: Ent in query(centre, rng):
		if o == e or not o.alive or allied(o.owner, e.owner) or o.owner < 0:
			continue
		if _is_stealthed(o) and not o.detected:
			continue
		if _pick_weapon(e, o) < 0:
			continue
		var d := centre.distance_to(o.pos)
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
	elif e.state == "guard":
		e.resume = {"state": "guard", "goal": e.guard_pos, "r": e.guard_radius}
	elif e.state == "idle":
		e.guard_pos = e.pos
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
	if wd.has("plan") and (e.plan != wd["plan"] or e.plan_t > 0.0):
		return false
	return true

## Active battle plan of the entity's owner ("" if none). Only ground units benefit.
func _plan_of(e: Ent) -> String:
	if e.owner < 0 or e.is_building or e.is_air():
		return ""
	return str(players[e.owner]["plan"])

## Weapon range including the Search and Destroy bonus.
func _range(e: Ent, wd: Dictionary) -> float:
	var r := float(wd["range"])
	if _plan_of(e) == "search":
		r *= 1.2
	if e.type == "patriot" and time < e.linked_until:
		r *= 1.2
	return r

func _recompute_plans() -> void:
	for p in range(players.size()):
		players[p]["plan"] = ""
	for e: Ent in ents.values():
		if e.alive and e.is_building and e.complete and e.owner >= 0 and e.def.get("plans", false) and e.plan != "" and e.plan_t <= 0.0:
			if players[e.owner]["plan"] == "":
				players[e.owner]["plan"] = e.plan

## Best weapon index able to hit target t, or -1.
func _pick_weapon(e: Ent, t: Ent) -> int:
	var best := -1
	var best_dmg := -1.0
	var ws := e.weapon_ids()
	for i in range(ws.size()):
		var wd: Dictionary = Data.WEAPONS[ws[i]]
		if not _weapon_available(e, ws[i]):
			continue
		if t.is_air() and t.alt > 0.5:
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
	if t == null or not t.alive or (_is_stealthed(t) and not t.detected and not allied(t.owner, e.owner)):
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
	var rng: float = _range(e, wd)
	var min_rng: float = wd.get("min_range", 0.0)
	var d := edge_dist(e.pos, t)
	var want := atan2(t.pos.x - e.pos.x, t.pos.y - e.pos.y)
	if e.def.get("turret", false):
		if not _aim_turret(e, want, dt) and d <= rng:
			return   # still traversing
	if d <= rng and d >= min_rng - t.radius:
		# in range: aim and fire
		if e.def.get("turret", false):
			pass
		elif not e.is_building:
			var turn := deg_to_rad(float(e.def.get("turn", 180.0))) * dt * 2.0
			var diff := wrapf(want - e.yaw, -PI, PI)
			e.yaw = wrapf(e.yaw + clampf(diff, -turn, turn), -PI, PI)
			if absf(wrapf(want - e.yaw, -PI, PI)) > 0.5 and not e.is_air():
				return
		if e.is_building and not e.powered and wd.get("needs_power", false):
			return
		if e.is_building:
			e.timer = 0.0
		if e.cds[wi] <= 0.0 and (int(wd.get("clip", 0)) == 0 or e.clip[wi] > 0):
			_fire(e, wi, t)
		return
	# out of range: chase (structures wait a moment, then look for something else)
	if e.is_building or not e.can_move():
		e.timer += dt
		if e.timer > 2.5:
			e.timer = 0.0
			e.state = "idle"
			e.target_id = -1
		return
	# leash: units that engaged on their own don't wander far from their post
	var leash := RETALIATE_LEASH
	if not e.resume.is_empty() and e.resume["state"] == "guard":
		leash = e.guard_radius + 6.0
	if _was_auto(e) and e.pos.distance_to(e.guard_pos) > leash:
		e.target_id = -1
		if not e.resume.is_empty():
			_next_order(e)
		else:
			_order_move(e, e.guard_pos)
		return
	e.repath_t -= dt
	# stuck behind friends: pick a different angle of approach
	if e.pos.distance_to(e.last_pos) < e.speed * dt * 0.15:
		e.stuck_t += dt
		if e.stuck_t > 1.2:
			e.stuck_t = 0.0
			e.flank = randf_range(-1.4, 1.4)
			e.repath_t = 0.0
	else:
		e.stuck_t = 0.0
	if e.repath_t <= 0.0 or e.path.is_empty():
		e.repath_t = 0.6
		var goal := t.pos
		if e.flank != 0.0 and d > rng * 0.9:
			# stand-off point on a ring around the target, rotated by this unit's flank angle
			var from_t := e.pos - t.pos
			var ang := atan2(from_t.x, from_t.y) + e.flank
			var standoff := rng * 0.7 + (maxf(t.def.get("fp", Vector2i.ONE).x, t.def.get("fp", Vector2i.ONE).y) * PathGrid.CELL * 0.5 if t.is_building else 0.0)
			goal = t.pos + Vector2(sin(ang), cos(ang)) * standoff
			var gc := grid.cell_of(goal)
			if grid.is_solid(gc):
				gc = grid.nearest_free(gc)
			goal = grid.center_of(gc)
		elif t.is_building:
			goal = grid.center_of(grid.approach_cell(e.pos, t.cells))
		_set_path(e, goal)
	_follow_path(e, dt)

## Force-fire at a ground position (artillery / clearing / attacking own or neutral things nearby).
func _do_attack_ground(e: Ent, dt: float) -> void:
	var wi := -1
	var ws := e.weapon_ids()
	for i in range(ws.size()):
		var wd0: Dictionary = Data.WEAPONS[ws[i]]
		if wd0["ag"] and _weapon_available(e, ws[i]):
			wi = i
			break
	if wi < 0:
		_next_order(e)
		return
	var wid: String = ws[wi]
	var wd: Dictionary = Data.WEAPONS[wid]
	var rng: float = _range(e, wd)
	var min_rng: float = wd.get("min_range", 0.0)
	var d := e.pos.distance_to(e.goal)
	var want := atan2(e.goal.x - e.pos.x, e.goal.y - e.pos.y)
	if e.def.get("turret", false):
		if not _aim_turret(e, want, dt) and d <= rng:
			return
	if d <= rng and d >= min_rng:
		if e.def.get("turret", false):
			pass
		elif not e.is_building:
			var turn := deg_to_rad(float(e.def.get("turn", 180.0))) * dt * 2.0
			var diff := wrapf(want - e.yaw, -PI, PI)
			e.yaw = wrapf(e.yaw + clampf(diff, -turn, turn), -PI, PI)
			if absf(wrapf(want - e.yaw, -PI, PI)) > 0.5 and not e.is_air():
				return
		if e.is_building and not e.powered and wd.get("needs_power", false):
			return
		if e.cds[wi] <= 0.0 and (int(wd.get("clip", 0)) == 0 or e.clip[wi] > 0):
			_fire_at_pos(e, wi, e.goal)
		return
	if e.is_building or not e.can_move():
		return
	if e.path.is_empty():
		_set_path(e, e.goal)
	_follow_path(e, dt)

func _was_auto(e: Ent) -> bool:
	return e.queue.is_empty() and e.guard_pos != Vector2.ZERO and not e.def.get("gatherer", false)

## Linked Patriot batteries: when one fires, idle Patriots within PATRIOT_LINK lock
## on to the same target (and get a little extra reach from the designation).
func _patriot_assist(e: Ent, t: Ent) -> void:
	for o: Ent in query(e.pos, PATRIOT_LINK):
		if o == e or not o.alive or o.type != "patriot" or not o.complete or not allied(o.owner, e.owner) or o.owner < 0:
			continue
		if o.state == "attack" or not o.powered:
			continue
		if _pick_weapon(o, t) < 0:
			continue
		if edge_dist(o.pos, t) <= _range(o, Data.WEAPONS["patriot"]) * 1.2:
			o.state = "attack"
			o.target_id = t.id
			o.timer = 0.0
			o.linked_until = time + 4.0

func _fire(e: Ent, wi: int, t: Ent) -> void:
	var wid: String = e.weapon_ids()[wi]
	var wd: Dictionary = Data.WEAPONS[wid]
	var dmg := _consume_shot(e, wi)
	e.last_target_owner = t.owner
	if e.type == "patriot":
		_patriot_assist(e, t)
	var sid := next_sid
	next_sid += 1
	events.append({"k": "shot", "p": e.pos, "d": [e.id, wid, t.pos.x, t.pos.y, t.alt, t.id, sid], "o": e.owner})
	var spd := float(wd.get("speed", 0.0))
	if spd <= 0.0:
		_apply_hit(e, wid, t, t.pos, dmg)
	else:
		var d := e.pos.distance_to(t.pos)
		shots.append({"t": time + d / spd, "t0": time, "from": e.pos, "wid": wid, "tid": t.id, "pos": t.pos, "dmg": dmg, "aid": e.id, "owner": e.owner, "sid": sid})

func _fire_at_pos(e: Ent, wi: int, pos: Vector2) -> void:
	var wid: String = e.weapon_ids()[wi]
	var wd: Dictionary = Data.WEAPONS[wid]
	var dmg := _consume_shot(e, wi)
	var sid := next_sid
	next_sid += 1
	events.append({"k": "shot", "p": e.pos, "d": [e.id, wid, pos.x, pos.y, 0.0, -1, sid], "o": e.owner})
	var spd := float(wd.get("speed", 0.0))
	if spd <= 0.0:
		_apply_hit(e, wid, null, pos, dmg)
	else:
		shots.append({"t": time + e.pos.distance_to(pos) / spd, "t0": time, "from": e.pos, "wid": wid, "tid": -1, "pos": pos, "dmg": dmg, "aid": e.id, "owner": e.owner, "sid": sid})

## Cooldown / clip bookkeeping for one shot; returns the damage it will do.
func _consume_shot(e: Ent, wi: int) -> float:
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
	if _plan_of(e) == "bombardment":
		dmg *= 1.2
	return dmg

func _tick_shots() -> void:
	if shots.is_empty():
		return
	var keep := []
	for s in shots:
		if time < s["t"]:
			# missiles in flight can be shot down mid-air once they're past a third of the way
			if s.has("t0") and _pd_style(s) and _point_defence(s, _shot_pos(s)):
				continue
			keep.append(s)
			continue
		var a: Ent = ents.get(s["aid"])
		var t: Ent = ents.get(s["tid"])
		var pos: Vector2 = s["pos"]
		if t != null and t.alive:
			pos = t.pos
		_apply_hit(a, s["wid"], t, pos, s["dmg"], s["owner"])
	shots = keep

func _pd_style(s: Dictionary) -> bool:
	var style := str(Data.WEAPONS[s["wid"]].get("style", ""))
	return style == "missile" or style == "cruise"

## Where a shot is right now (straight line from shooter to target).
func _shot_pos(s: Dictionary) -> Vector2:
	var t0: float = s["t0"]
	var k := clampf((time - t0) / maxf(float(s["t"]) - t0, 0.01), 0.0, 1.0)
	var to: Vector2 = s["pos"]
	var tg: Ent = ents.get(s["tid"])
	if tg != null and tg.alive:
		to = tg.pos
	return (s["from"] as Vector2).lerp(to, k)

## Avenger / Paladin laser point defence: an incoming missile or shell aimed near
## a friendly is burned out of the air. Each defender has a cooldown, so a salvo
## can overwhelm it (Avenger 0.35 s, Paladin 1.5 s, Generals-style).
func _point_defence(s: Dictionary, pos: Vector2) -> bool:
	if not _pd_style(s):
		return false
	var t0: float = s.get("t0", time)
	var k := clampf((time - t0) / maxf(float(s["t"]) - t0, 0.01), 0.0, 1.0)
	if k < 0.3:
		return false
	var own := int(s["owner"])
	for d: Ent in query(pos, 26.0):
		if not d.alive or d.owner < 0 or allied(d.owner, own):
			continue
		var pd := 0.0
		if d.type == "avenger":
			pd = 0.25
		elif d.type == "paladin":
			pd = 0.8
		else:
			continue
		if time < d.pd_t:
			continue
		d.pd_t = time + pd
		# missile altitude along its arc (shells arc high, missiles fly flat-ish)
		var alt := 2.0 + sin(k * PI) * (2.5 if str(Data.WEAPONS[s["wid"]].get("style", "")) == "missile" else 10.0)
		events.append({"k": "pd", "p": d.pos, "d": [d.id, pos.x, pos.y, alt, int(s.get("sid", -1))], "o": d.owner})
		return true
	return false

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
		if allied(o.owner, own) and own >= 0:
			continue
		if o.owner < 0 and dtype != "PARTICLE_BEAM" and target != null:
			continue
		if o.is_air() and o.alt > 0.5 and not wd["aa"]:
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
	if _plan_of(t) == "hold":
		mult *= 0.9
	elif t.is_building and t.def.get("plans", false) and t.plan == "hold" and t.plan_t <= 0.0:
		mult *= 0.5
	t.hp -= amount * mult
	if t.owner >= 0 and attacker != null and not allied(attacker.owner, t.owner):
		var pl: Dictionary = players[t.owner]
		if time - pl["attack_msg_t"] > 8.0:
			pl["attack_msg_t"] = time
			session.s_msg(pl["peer"], "%s under attack!" % ("Base" if t.is_building else "Units"))
			events.append({"k": "alert", "p": t.pos, "d": [t.pos.x, t.pos.y], "o": t.owner, "only": t.owner})
		# units that are being shot from outside their reach go and find the shooter
		if not t.is_building and (t.state == "idle" or t.state == "guard") and t.has_weapons() and attacker.alive and _pick_weapon(t, attacker) >= 0 and not t.is_jet():
			if t.state == "guard":
				t.resume = {"state": "guard", "goal": t.guard_pos, "r": t.guard_radius}
			else:
				t.guard_pos = t.pos
			t.state = "attack"
			t.target_id = attacker.id
			t.path = PackedVector2Array()
			t.repath_t = 0.0
		if attacker.alive and time - t.help_t > 3.0:
			t.help_t = time
			_call_for_help(t, attacker)
	if t.hp <= 0.0:
		destroy(t, "killed", attacker)

## Nearby idle friendlies (own or allied) come to help; parked aircraft near the
## fight scramble. Like Generals, everyone sitting around a base defends it.
func _call_for_help(t: Ent, attacker: Ent) -> void:
	var n := 0
	for o in query(t.pos, ASSIST_RADIUS):
		if o == t or not o.alive or o.is_building or o.owner < 0 or not allied(o.owner, t.owner):
			continue
		if o.is_jet() or not o.has_weapons() or o.def.get("gatherer", 0) > 0 or o.def.get("builder", false):
			continue
		if o.state != "idle" and o.state != "guard":
			continue
		if o.state == "guard" and o.guard_radius > 0.0 and o.guard_pos.distance_to(attacker.pos) > o.guard_radius + 12.0:
			continue
		if _pick_weapon(o, attacker) < 0:
			continue
		if o.state == "guard":
			o.resume = {"state": "guard", "goal": o.guard_pos, "r": o.guard_radius}
		else:
			o.guard_pos = o.pos
		o.state = "attack"
		o.target_id = attacker.id
		o.flank = randf_range(-1.2, 1.2)
		o.path = PackedVector2Array()
		o.repath_t = 0.0
		n += 1
		if n >= 12:
			break
	# aircraft: parked jets and idle helicopters whose airfield / position is near the fight
	for o: Ent in ents.values():
		if not o.alive or o.is_building or o.owner < 0 or not allied(o.owner, t.owner) or not o.is_air():
			continue
		if o.state != "idle" or not o.has_weapons() or _pick_weapon(o, attacker) < 0:
			continue
		var base: Ent = ents.get(o.home_id) if o.is_jet() else o
		if base == null or base.pos.distance_to(t.pos) > SCRAMBLE_RADIUS:
			continue
		if o.is_jet() and (o.flight != "parked" or o.clip.is_empty() or o.clip[0] <= 0):
			continue
		o.guard_pos = o.pos
		o.state = "attack"
		o.target_id = attacker.id
		o.path = PackedVector2Array()
		o.repath_t = 0.0

# ---- jets -------------------------------------------------------------------
## Fixed-wing aircraft: taxi/takeoff along the runway, fly with a minimum speed
## and a turn rate (so they arc and make attack passes), loiter in circles when
## they have nowhere to be, and land back on their pad to rearm. With no
## airfield left they circle and slowly lose airframe integrity.
func _tick_jet(e: Ent, dt: float) -> void:
	var home: Ent = ents.get(e.home_id)
	if home != null and (not home.alive or home.owner != e.owner):
		home = null
		e.home_id = -1
	match e.flight:
		"parked":
			e.alt = 0.0
			if home == null:
				e.flight = "fly"    # airfield vanished under us
				e.air_spd = e.speed
				return
			e.pos = _pad_pos(home, _pad_index(home, e))
			e.yaw = atan2(_runway_dir(home).x, _runway_dir(home).y)
			var full := true
			for i in range(e.clip.size()):
				if e.clip[i] <= 0:
					full = false
			if full:
				e.ammo_empty = false
			if e.state == "idle" and not e.queue.is_empty():
				var c: Dictionary = e.queue.pop_front()
				_apply_unit_cmd(e, c)
			if e.state != "idle" and e.state != "return" and (full or e.state == "move"):
				e.flight = "taxi"     # roll out of the hangar to the runway first
				e.air_spd = 0.0
				e.timer = 0.0
			elif e.state == "return":
				e.state = "idle"
		"taxi", "taxi_in":
			e.alt = 0.0
			if home == null:
				e.flight = "takeoff"
				return
			var goal := _runway_start(home) if e.flight == "taxi" else _pad_pos(home, _pad_index(home, e))
			var d := e.pos.distance_to(goal)
			var want := atan2(goal.x - e.pos.x, goal.y - e.pos.y) if d > 0.3 else e.yaw
			e.yaw = lerp_angle(e.yaw, want, 4.0 * dt)
			var step := minf(7.0 * dt, d)
			e.pos = e.pos.move_toward(goal, step)
			if d < 0.4:
				if e.flight == "taxi":
					e.flight = "takeoff"
					e.air_spd = 0.0
					e.timer = 0.0
					e.yaw = atan2(_runway_dir(home).x, _runway_dir(home).y)
				else:
					e.flight = "parked"
					e.pos = goal
					e.yaw = atan2(_runway_dir(home).x, _runway_dir(home).y)
		"takeoff":
			var dir := _runway_dir(home) if home != null else Vector2(sin(e.yaw), cos(e.yaw))
			e.yaw = atan2(dir.x, dir.y)
			e.air_spd = minf(e.speed, e.air_spd + e.speed * 0.9 * dt)
			e.pos += dir * e.air_spd * dt
			e.timer += dt
			if e.timer > 0.7:
				e.alt = move_toward(e.alt, float(e.def.get("alt", 20.0)), 11.0 * dt)
			if e.alt >= float(e.def.get("alt", 20.0)) * 0.45:
				e.flight = "fly"
				e.air_spd = e.speed
		"fly":
			_jet_fly(e, dt, home)

func _jet_steer(e: Ent, to: Vector2, dt: float, spd_mult := 1.0) -> void:
	var want := atan2(to.x - e.pos.x, to.y - e.pos.y)
	var turn := deg_to_rad(float(e.def.get("turn", 120.0))) * dt
	var diff := wrapf(want - e.yaw, -PI, PI)
	e.yaw = wrapf(e.yaw + clampf(diff, -turn, turn), -PI, PI)
	var spd := e.speed * spd_mult
	e.pos += Vector2(sin(e.yaw), cos(e.yaw)) * spd * dt
	e.pos.x = clampf(e.pos.x, 2.0, map_size - 2.0)
	e.pos.y = clampf(e.pos.y, 2.0, map_size - 2.0)

## Loiter: fly a circle of radius r around c.
func _jet_loiter(e: Ent, c: Vector2, dt: float, r := 28.0) -> void:
	var rel := e.pos - c
	var target := c + Vector2(r, 0)
	if rel.length() > 1.0:
		var tangent := Vector2(-rel.y, rel.x).normalized()
		target = c + rel.normalized() * r + tangent * 14.0
	_jet_steer(e, target, dt)

func _jet_fly(e: Ent, dt: float, home: Ent) -> void:
	if e.state != "return":
		e.alt = move_toward(e.alt, float(e.def.get("alt", 20.0)), 6.0 * dt)
	match e.state:
		"attack":
			var t: Ent = ents.get(e.target_id)
			if t == null or not t.alive or (_is_stealthed(t) and not t.detected):
				_next_order(e)
				return
			var wi := _pick_weapon(e, t)
			if wi < 0:
				_next_order(e)
				return
			var wd: Dictionary = Data.WEAPONS[e.weapon_ids()[wi]]
			if int(wd.get("clip", 0)) > 0 and e.clip[wi] <= 0:
				e.ammo_empty = true
				_jet_return_home(e)
				return
			_jet_pass(e, dt, t.pos, edge_dist(e.pos, t), wd, wi, t)
		"attack_ground":
			var wi := 0
			var wd: Dictionary = Data.WEAPONS[e.weapon_ids()[wi]]
			if int(wd.get("clip", 0)) > 0 and e.clip[wi] <= 0:
				e.ammo_empty = true
				_jet_return_home(e)
				return
			_jet_pass(e, dt, e.goal, e.pos.distance_to(e.goal), wd, wi, null)
		"move":
			_jet_steer(e, e.goal, dt)
			if e.pos.distance_to(e.goal) < 10.0:
				_next_order(e)
		"guard":
			if not _auto_acquire(e, dt):
				_jet_loiter(e, e.guard_pos, dt)
		"return":
			if home == null:
				e.state = "idle"
				return
			_jet_land(e, dt, home)
		_:
			if home != null:
				_jet_return_home(e)
			else:
				_jet_orphan(e, dt)

## One attack run: line up, fire when in range and roughly ahead, overshoot, turn around.
func _jet_pass(e: Ent, dt: float, tp: Vector2, d: float, wd: Dictionary, wi: int, t: Ent) -> void:
	var want := atan2(tp.x - e.pos.x, tp.y - e.pos.y)
	var off := absf(wrapf(want - e.yaw, -PI, PI))
	if e.timer > 0.0:
		e.timer -= dt
		_jet_steer(e, e.pos + Vector2(sin(e.yaw), cos(e.yaw)) * 50.0, dt)
		return
	_jet_steer(e, tp, dt)
	if d <= float(wd["range"]) and off < 0.6 and e.cds[wi] <= 0.0 and (int(wd.get("clip", 0)) == 0 or e.clip[wi] > 0):
		if t != null:
			_fire(e, wi, t)
		else:
			_fire_at_pos(e, wi, tp)
	elif d < 14.0 and off > 1.3:
		e.timer = 1.6

func _jet_return_home(e: Ent) -> void:
	if e.home_id < 0 or ents.get(e.home_id) == null:
		_jet_find_home(e)
	if e.home_id < 0:
		e.state = "idle"
		return
	e.state = "return"
	e.target_id = -1
	e.land_phase = 0
	e.timer = 0.0
	e.flight = "fly"

func _jet_find_home(e: Ent) -> void:
	e.home_id = -1
	for b: Ent in ents.values():
		if b.alive and b.owner == e.owner and b.type == "airfield" and b.complete and _airfield_load(b) < int(b.def.get("pads", 4)):
			e.home_id = b.id
			return

## No airfield: circle where we are and bleed out.
func _jet_orphan(e: Ent, dt: float) -> void:
	e.orphan_t += dt
	if e.orphan_t > 2.0:
		e.orphan_t = 0.0
		_jet_find_home(e)
		if e.home_id >= 0:
			_jet_return_home(e)
			return
	if e.guard_pos == Vector2.ZERO:
		e.guard_pos = e.pos
	_jet_loiter(e, e.guard_pos, dt)
	e.hp -= e.max_hp * ORPHAN_DRAIN * dt
	if e.hp <= 0.0:
		destroy(e, "killed")

## Landing: line up on the runway from the approach side, then descend onto the pad.
func _jet_land(e: Ent, dt: float, home: Ent) -> void:
	var dir := _runway_dir(home)
	var pad := _runway_start(home)
	var approach := pad - dir * 45.0
	approach.x = clampf(approach.x, 8.0, map_size - 8.0)
	approach.y = clampf(approach.y, 8.0, map_size - 8.0)
	if e.land_phase == 0:
		e.alt = move_toward(e.alt, float(e.def.get("alt", 20.0)), 6.0 * dt)
		var da := e.pos.distance_to(approach)
		_jet_steer(e, approach, dt, 0.55 if da < 45.0 else 1.0)
		e.timer += dt
		if da < 20.0 or e.timer > 14.0:
			e.land_phase = 1
			e.timer = 0.0
	else:
		var want := atan2(dir.x, dir.y)
		var d := e.pos.distance_to(pad)
		var frac := clampf(d / 55.0, 0.0, 1.0)
		e.alt = float(e.def.get("alt", 20.0)) * frac * 0.9
		# slow final: a 10 m/s jet with 120 deg/s turn spirals onto the pad from anywhere
		_jet_steer(e, pad, dt, 0.28 + 0.4 * frac)
		if d < 4.0:
			e.flight = "taxi_in"
			e.alt = 0.0
			e.pos = pad
			e.yaw = want
			e.land_phase = 0
			for i in range(e.clip.size()):
				if e.clip[i] <= 0:
					e.reload_t[i] = 8.0
			e.state = "idle"
			e.target_id = -1
			if not e.resume.is_empty():
				var r: Dictionary = e.resume
				e.resume = {}
				if r["state"] == "guard":
					e.state = "guard"
					e.guard_pos = r["goal"]
					e.guard_radius = GUARD_RADIUS

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

# ---- transports (Generals: Humvee 5 infantry with fire ports, Chinook 8 slots, vehicles take 3) ----
func _cargo_used(t: Ent) -> int:
	var n := 0
	for id in t.cargo:
		var u: Ent = ents.get(id)
		if u != null and u.alive:
			n += u.slot_cost()
	return n

func _can_board(u: Ent, t: Ent) -> bool:
	if t == null or not t.alive or u == t or not t.def.has("cargo") or not allied(u.owner, t.owner):
		return false
	if u.is_building or u.is_air() or u.def.get("builder", false) and not t.def.get("cargo_veh", false):
		return false
	if u.cat() == "veh" and not t.def.get("cargo_veh", false):
		return false
	return _cargo_used(t) + u.slot_cost() <= int(t.def["cargo"])

## Walk to the transport and climb in.
func _do_board(e: Ent, dt: float) -> void:
	var t: Ent = ents.get(e.target_id)
	if not _can_board(e, t):
		_next_order(e)
		return
	if t.is_air() and t.state != "pickup" and (t.alt > 1.5 or t.state == "idle"):
		# a hovering Chinook comes down to pick up
		t.state = "pickup"
	if t.state == "pickup":
		t.timer = 4.0   # keep it waiting while someone is still walking over
	var d := e.pos.distance_to(t.pos) - t.radius - e.radius
	if d <= 1.2:
		e.inside_id = t.id
		t.cargo.append(e.id)
		e.state = "idle"
		e.target_id = -1
		e.path = PackedVector2Array()
		for p in range(players.size()):
			if known[p].has(e.id):
				session.s_despawn(players[p]["peer"], e.id, "loaded")
				known[p].erase(e.id)
		events.append({"k": "load", "p": t.pos, "d": [t.id], "o": t.owner})
		return
	e.repath_t -= dt
	if e.repath_t <= 0.0 or e.path.is_empty():
		e.repath_t = 0.6
		var goal := t.pos
		var gc := grid.cell_of(goal)
		if grid.is_solid(gc):
			gc = grid.nearest_free(gc)
		_set_path(e, grid.center_of(gc))
	_follow_path(e, dt)

## Transport: land (if flying) and let everyone out around it.
func _do_unload(e: Ent, dt: float) -> void:
	if e.is_air():
		e.alt = move_toward(e.alt, 0.5, 6.0 * dt)
		if e.alt > 1.0:
			return
	if e.cargo.is_empty():
		# came down for a pickup: wait a few seconds then lift off
		e.timer -= dt
		if e.timer <= 0.0:
			e.state = "idle"
		return
	var out: Array[int] = []
	for id in e.cargo:
		var u: Ent = ents.get(id)
		if u == null or not u.alive:
			continue
		var c := grid.nearest_free(grid.cell_of(e.pos + Vector2(randf_range(-3, 3), randf_range(-3, 3))))
		u.pos = grid.center_of(c)
		u.inside_id = -1
		u.state = "idle"
		u.guard_pos = u.pos
		u.last_pos = u.pos
		out.append(u.id)
	e.cargo.clear()
	e.state = "idle"
	events.append({"k": "unload", "p": e.pos, "d": [e.id], "o": e.owner})

## Passenger in a Humvee: shoots whatever the Humvee is fighting, or anything in reach.
func _tick_passenger(e: Ent, car: Ent, dt: float) -> void:
	var t: Ent = ents.get(car.target_id) if car.state == "attack" else null
	if t == null or not t.alive or _pick_weapon(e, t) < 0:
		e.acquire_t -= dt
		if e.acquire_t > 0.0:
			return
		e.acquire_t = 0.5
		t = null
		var best := 1e18
		for o: Ent in query(car.pos, 32.0):
			if o == car or not o.alive or o.owner < 0 or allied(o.owner, e.owner) or (_is_stealthed(o) and not o.detected):
				continue
			if _pick_weapon(e, o) < 0:
				continue
			var d := o.pos.distance_squared_to(car.pos)
			if d < best:
				best = d
				t = o
		if t == null:
			return
	var wi := _pick_weapon(e, t)
	if wi < 0:
		return
	var wd: Dictionary = Data.WEAPONS[e.weapon_ids()[wi]]
	if edge_dist(car.pos, t) <= _range(e, wd) and e.cds[wi] <= 0.0 and (int(wd.get("clip", 0)) == 0 or e.clip[wi] > 0):
		_fire(e, wi, t)
		# the tracer comes from the vehicle on screen
		var ev: Dictionary = events[events.size() - 1]
		if ev["k"] == "shot":
			ev["d"][0] = car.id

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
		# land beside the crates, then load one box at a time
		e.alt = move_toward(e.alt, 0.5, 5.0 * dt)
		if e.alt > 0.9:
			return
		e.timer += dt
		if e.timer >= 1.3:
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
		# one Chinook on the pad at a time: the others hold off to the side
		var user: Ent = ents.get(c.pad_user)
		if user == null or not user.alive or user.state != "gather" or user.carry == 0 or user.pos.distance_to(c.pos) > 8.0:
			c.pad_user = -1
		if c.pad_user >= 0 and c.pad_user != e.id:
			var hold := c.pos + Vector2(sin(float(e.id)), cos(float(e.id))) * 11.0
			if e.pos.distance_to(hold) > 2.0:
				_move_toward(e, hold, dt)
			e.alt = move_toward(e.alt, 10.0, 6.0 * dt)
			return
		var d := e.pos.distance_to(c.pos)
		if d > 3.0:
			_move_toward(e, c.pos, dt)
			return
		c.pad_user = e.id
		# land on the H and unload
		e.alt = move_toward(e.alt, 0.5, 5.0 * dt)
		if e.alt > 0.9:
			return
		e.timer += dt
		if e.timer >= 4.5:
			e.timer = 0.0
			var val := float(e.carry * Data.BOX_VALUE) * float(players[e.owner]["income_mult"])
			players[e.owner]["cash"] += val
			players[e.owner]["stats"]["cash_earned"] += int(val)
			events.append({"k": "cash", "p": c.pos, "d": [int(val), c.id], "o": e.owner, "only": e.owner})
			e.carry = 0
			c.pad_user = -1
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
		return PathGrid.rect_dist(p, t.pos, t.def["fp"], t.yaw)
	return p.distance_to(t.pos) - t.radius

func _approach_building(e: Ent, b: Ent, dt: float, reach := 4.2) -> bool:
	var d := edge_dist(e.pos, b)
	if d <= reach:
		e.path = PackedVector2Array()
		return true
	e.repath_t -= dt
	if e.path.is_empty() or e.repath_t <= 0.0:
		e.repath_t = 2.0
		_set_path(e, grid.center_of(grid.approach_cell(e.pos, b.cells)))
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
	players[b.owner]["stats"]["bld_built"] += 1
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
	if b == null or not b.alive or not allied(b.owner, e.owner):
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
	b.capture_tick = tick
	if debug and tick % 40 == 0:
		print("[Sim] capture %s#%d by p%d %.1f/%.0f" % [b.type, b.id, e.owner, b.capture_t, CAPTURE_TIME])
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
	# nobody standing next to it any more: the capture fades away
	if e.capture_by >= 0 and tick - e.capture_tick > 20:
		e.capture_t -= dt * 2.0
		if e.capture_t <= 0.0:
			e.capture_t = 0.0
			e.capture_by = -1
	if e.sold:
		e.progress -= dt / maxf(float(e.def["time"]) * 0.35, 2.0)
		if e.progress <= 0.0:
			var refund := float(e.def["cost"]) * Data.REFUND
			players[e.owner]["cash"] += refund
			session.s_msg(players[e.owner]["peer"], "%s sold for $%d" % [e.def["name"], int(refund)])
			destroy(e, "sold")
		return
	if not e.complete:
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
		# research keeps its pace under low power (so control rods can't strand you)
		var r: Dictionary = e.research[0]
		r["t"] += dt
		if r["t"] >= r["total"]:
			e.research.pop_front()
			_finish_upgrade(e, r["id"])
	if e.def.has("income"):
		e.income_t += dt
		if e.income_t >= float(e.def["income"]["every"]):
			e.income_t = 0.0
			var amt := float(e.def["income"]["amount"]) * float(pl["income_mult"])
			if e.type == "supply_drop_zone":
				# a cargo plane flies over and drops the crate; the money lands when it does
				strikes.append({"k": "supply_cash", "p": e.pos, "t": time + 6.0, "owner": e.owner, "amt": amt, "bid": e.id})
				events.append({"k": "supply_drop", "p": e.pos, "d": [e.pos.x, e.pos.y, e.id], "o": e.owner, "all": true})
			else:
				pl["cash"] += amt
				pl["stats"]["cash_earned"] += int(amt)
				events.append({"k": "cash", "p": e.pos, "d": [int(amt), e.id], "o": e.owner, "only": e.owner})
	if e.plan_t > 0.0:
		e.plan_t -= dt
		if e.plan_t <= 0.0:
			_recompute_plans()
			session.s_msg(pl["peer"], "%s plan active" % Data.PLANS[e.plan]["name"])
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
	players[b.owner]["stats"]["units_built"] += 1
	var u: Ent
	if d.get("jet", false):
		var idx := 0
		for o: Ent in ents.values():
			if o.alive and o.home_id == b.id and o.is_jet():
				idx += 1
		u = spawn(type, b.owner, _pad_pos(b, idx))
		u.home_id = b.id
		u.flight = "parked"
		u.alt = 0.0
		u.yaw = 0.0
	elif d.get("cat", "") == "air":
		u = spawn(type, b.owner, _helipad_pos(b) if b.def.get("runway", false) else b.pos)
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
	events.append({"k": "produced", "p": b.pos, "d": [b.id, u.id], "o": b.owner})
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
			if o.is_jet() and o.flight != "parked":
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
				# gun run first (a line of 30mm hits), then two missiles per jet on the target
				var dir := Vector2.from_angle(s["heading"])
				for i in range(int(s["level"])):
					var side := dir.orthogonal() * ((i - 1) * 6.0)
					for j in range(-4, 3):
						var hp_ := p + dir * (j * 5.0) + side
						shots.append({"t": time + 0.1 * (j + 4), "wid": "a10_gun", "tid": -1, "pos": hp_, "dmg": 45.0, "aid": -1, "owner": s["owner"]})
					for k in range(2):
						shots.append({"t": time + 1.1 + k * 0.25, "wid": "a10_missile", "tid": -1, "pos": p + side + dir * (k * 4.0), "dmg": 150.0, "aid": -1, "owner": s["owner"]})
			"fab":
				shots.append({"t": time, "wid": "fab", "tid": -1, "pos": p, "dmg": 600.0, "aid": -1, "owner": s["owner"]})
			"supply_cash":
				var own: int = s["owner"]
				var zone: Ent = ents.get(int(s["bid"]))
				if zone != null and zone.alive and zone.owner == own:
					var amt: float = s["amt"]
					players[own]["cash"] += amt
					players[own]["stats"]["cash_earned"] += int(amt)
					events.append({"k": "cash", "p": p, "d": [int(amt), zone.id], "o": own, "only": own})
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
		if steer.x >= 0.0 and b.get("steer", true):
			b["p"] = (b["p"] as Vector2).move_toward(steer, 7.0 * dt)
		b["next"] -= dt
		if b["next"] <= 0.0:
			b["next"] = 0.25
			var pos: Vector2 = b["p"]
			events.append({"k": "beam", "p": pos, "d": [pos.x, pos.y, int(b.get("bid", -1)), b["owner"]], "o": b["owner"], "all": true})
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
			elif players[p]["plan"] == "search" and not e.is_building and not e.is_air():
				r *= 1.2
			v.stamp(e.pos, r)
		var keep := []
		for r in v.reveals:
			if time < r["until"]:
				v.stamp(r["pos"], r["radius"])
				keep.append(r)
		v.reveals = keep
		if players[p]["peer"] >= 0:
			session.s_fog(players[p]["peer"], _team_fog(p))
		# ghost buildings that died out of sight
		var done := []
		for id in pending_despawn[p]:
			if team_visible(p, pending_despawn[p][id]):
				session.s_despawn(players[p]["peer"], id, "gone")
				known[p].erase(id)
				done.append(id)
		for id in done:
			pending_despawn[p].erase(id)
	# stealth detection: Search and Destroy lets ground units detect stealth in their vision
	for e: Ent in ents.values():
		e.detected = false
	var detectors: Array = []
	for e: Ent in ents.values():
		if e.alive and e.owner >= 0 and not e.is_building and not e.is_air() and players[e.owner]["plan"] == "search":
			detectors.append(e)
	if not detectors.is_empty():
		for e: Ent in ents.values():
			if not e.alive or not _is_stealthed(e):
				continue
			for d: Ent in detectors:
				if not allied(d.owner, e.owner) and d.pos.distance_to(e.pos) <= d.vision * 1.2:
					e.detected = true
					break

## Bit-packed union of every allied player's vision.
func _team_fog(p: int) -> PackedByteArray:
	var v: Vision = visions[p]
	var out := PackedByteArray()
	out.resize((v.size * v.size + 7) / 8)
	out.fill(0)
	for i in range(players.size()):
		if not allied(p, i):
			continue
		var vis: PackedByteArray = visions[i].vis
		for k in range(vis.size()):
			if vis[k] == 1:
				out[k >> 3] = out[k >> 3] | (1 << (k & 7))
	return out

func _visible_to(p: int, e: Ent) -> bool:
	if e.inside_id >= 0:
		return false
	if allied(e.owner, p):
		return true
	if e.is_building:
		# a structure is visible if any of its footprint corners or its centre is in view
		if not team_visible(p, e.pos):
			var fp: Vector2i = e.def["fp"]
			var half := Vector2(fp) * PathGrid.CELL * 0.5
			var seen := false
			for c in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
				if team_visible(p, e.pos + c.rotated(-e.yaw)):
					seen = true
					break
			if not seen:
				if time - e.last_fire_t < 6.0 and e.last_target_owner >= 0 and allied(e.last_target_owner, p):
					return true
				return false
		return true
	if not team_visible(p, e.pos):
		# no invisible attackers: anything shooting at us (or lining up to) stays visible
		# until it breaks off, like Generals
		if not _is_stealthed(e):
			if time - e.last_fire_t < 6.0 and e.last_target_owner >= 0 and allied(e.last_target_owner, p):
				return true
			if e.state == "attack" or e.state == "attack_ground":
				var tg: Ent = ents.get(e.target_id)
				if tg != null and tg.alive and allied(tg.owner, p) and e.pos.distance_to(tg.pos) < 90.0:
					return true
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
		if players[p]["peer"] < 0:
			events_seen_by_bot(p)
			continue
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
			var aux2 := 0
			if e.is_building and not e.complete:
				var bd: Ent = ents.get(e.builder_id)
				aux2 = 1 if (bd != null and bd.alive and bd.state == "build" and bd.target_id == e.id) else 0
			elif e.is_building:
				aux2 = e.capture_by + 1 if e.capture_by >= 0 and e.capture_t > 0.0 else 0
			elif e.clip.size() > 1:
				aux2 = e.clip[1]
			buf.put_u8(aux2)
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
			if ev.get("ally_only", false) and not allied(ev.get("o", -1), p):
				continue
			if ev.get("all", false) or allied(ev.get("o", -1), p) or team_visible(p, ev["p"]) or ev.has("only"):
				evs.append([ev["k"], ev["d"]])
		if not evs.is_empty():
			session.s_events(players[p]["peer"], evs)
	events.clear()

func events_seen_by_bot(_p: int) -> void:
	pass

func _steering_beam(p: int) -> bool:
	for b in beams:
		if b["owner"] == p and b.get("steer", true):
			return true
	return false

func _plans_array() -> Array:
	var out := []
	for pl in players:
		out.append(pl["plan"])
	return out

func _all_upgrades() -> Array:
	var out := []
	for pl in players:
		out.append(pl["upgrades"].keys())
	return out

func _teams_array() -> Array:
	var out := []
	for pl in players:
		out.append(pl["team"])
	return out

func _send_pstates() -> void:
	var sw := {}
	var sw_bld := {}
	for e: Ent in ents.values():
		if e.alive and e.is_building and e.def.has("superweapon") and e.complete and e.owner >= 0:
			var remaining := 0.0 if e.sw_ready else float(e.def["superweapon"]) - e.sw_t
			sw_bld[e.id] = remaining
			if not sw.has(e.owner) or remaining < sw[e.owner]:
				sw[e.owner] = remaining
	var docks := {}
	for e: Ent in ents.values():
		if e.alive and e.type == "supply_dock":
			docks[e.id] = e.boxes
	for p in range(players.size()):
		var pl: Dictionary = players[p]
		if pl["peer"] < 0:
			continue
		var st := {
			"cash": int(pl["cash"]), "pp": pl["pp"], "pu": pl["pu"], "low": pl["low"], "rank": pl["rank"], "xp": int(pl["xp"]),
			"next": Data.RANK_XP[pl["rank"]] if pl["rank"] < 5 else -1, "points": pl["points"], "powers": pl["powers"].duplicate(),
			"cds": {}, "upgrades": pl["upgrades"].keys(), "research": {}, "queues": {}, "rally": {}, "sw": sw, "docks": docks,
			"tick": tick, "time": time, "upg_done": {}, "hp": {}, "xp_units": {}, "guard": {}, "teams": _teams_array(), "beam": _steering_beam(p), "sw_bld": sw_bld,
			"plans": _plans_array(), "all_upgrades": _all_upgrades(), "defeated": pl["defeated"], "plan_bld": {}, "air_load": {}, "cargo": {}, "research_q": {},
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
					var rq := []
					for r in e.research:
						rq.append(r["id"])
					st["research_q"][e.id] = rq
				if e.has_rally:
					st["rally"][e.id] = [e.rally.x, e.rally.y]
				if not e.upg_done.is_empty():
					st["upg_done"][e.id] = e.upg_done.keys()
				if e.def.get("plans", false):
					st["plan_bld"][e.id] = [e.plan, clampf(1.0 - e.plan_t / Data.PLAN_SWITCH, 0.0, 1.0)]
				if e.def.get("runway", false):
					st["air_load"][e.id] = [_airfield_load(e), int(e.def.get("pads", 4))]
			st["hp"][e.id] = [int(e.hp), int(e.max_hp)]
			if not e.cargo.is_empty():
				var types := []
				for cid in e.cargo:
					var cu: Ent = ents.get(cid)
					if cu != null and cu.alive:
						types.append(cu.type)
				st["cargo"][e.id] = types
			if not e.is_building and e.guard_radius > 0.0 and (e.state == "guard" or (not e.resume.is_empty() and e.resume["state"] == "guard")):
				st["guard"][e.id] = [e.guard_pos.x, e.guard_pos.y, e.guard_radius]
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
	var all_teams := {}
	for pl in players:
		all_teams[pl["team"]] = true
	if solo or all_teams.size() <= 1:
		# sandbox / co-op with no opponent: only ends when everybody is gone
		if alive_players.is_empty():
			game_over = true
			session.s_gameover(-1, report())
		return
	var teams_alive := {}
	for p in alive_players:
		teams_alive[players[p]["team"]] = true
	if teams_alive.size() <= 1:
		game_over = true
		winner = -1
		if teams_alive.size() == 1:
			winner = int(teams_alive.keys()[0])
		session.s_gameover(winner, report())

## End-of-match statistics for every player.
func report() -> Array:
	var out := []
	for p in range(players.size()):
		var pl: Dictionary = players[p]
		var st: Dictionary = pl["stats"].duplicate()
		st["name"] = pl["name"]
		st["ai"] = pl["peer"] < 0
		st["rank"] = pl["rank"]
		st["xp"] = int(pl["xp"])
		st["defeated"] = pl["defeated"]
		st["team"] = pl["team"]
		st["time"] = int(time)
		out.append(st)
	return out

# ---------------------------------------------------------------------------
# Commands (from clients)
# ---------------------------------------------------------------------------
func cmd(p: int, c: Dictionary) -> void:
	if p < 0 or game_over:
		return
	var t: String = c.get("t", "")
	match t:
		"move", "amove", "attack", "attack_ground", "stop", "guard", "gather", "repair", "capture":
			var q: bool = c.get("q", false)
			for id in c.get("ids", []):
				var e: Ent = ents.get(int(id))
				if e == null or not e.alive or e.owner != p or e.is_building or e.inside_id >= 0:
					continue
				if q and e.state != "idle":
					e.queue.append(c)
				else:
					e.queue.clear()
					e.resume = {}
					_apply_unit_cmd(e, c)
		"load":
			var car: Ent = ents.get(int(c.get("tid", -1)))
			for id in c.get("ids", []):
				var e: Ent = ents.get(int(id))
				if e == null or not e.alive or e.owner != p or e.inside_id >= 0 or not _can_board(e, car):
					continue
				e.queue.clear()
				e.resume = {}
				e.state = "board"
				e.target_id = car.id
				e.path = PackedVector2Array()
				e.repath_t = 0.0
		"unload":
			for id in c.get("ids", []):
				var e: Ent = ents.get(int(id))
				if e != null and e.alive and e.owner == p and e.def.has("cargo") and not e.cargo.is_empty():
					e.queue.clear()
					e.state = "unload"
					e.path = PackedVector2Array()
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
		"sw_stop":
			for b in beams:
				if b["owner"] == p:
					b["steer"] = false
		"cheat_cash":
			if solo or debug:
				players[p]["cash"] += 10000.0
		"plan":
			var b: Ent = ents.get(int(c.get("id", -1)))
			var plan := str(c.get("plan", ""))
			if b != null and b.alive and b.owner == p and b.complete and b.def.get("plans", false) and Data.PLANS.has(plan) and b.plan != plan:
				b.plan = plan
				b.plan_t = Data.PLAN_SWITCH
				_recompute_plans()
				session.s_msg(players[p]["peer"], "Battle plan: %s (ready in %ds)" % [Data.PLANS[plan]["name"], int(Data.PLAN_SWITCH)])
		"beacon":
			var bp := Vector2(clampf(float(c.get("x", 0.0)), 0.0, map_size), clampf(float(c.get("y", 0.0)), 0.0, map_size))
			events.append({"k": "beacon", "p": bp, "d": [bp.x, bp.y, p], "o": p, "ally_only": true})
		"surrender":
			if not players[p]["defeated"]:
				players[p]["defeated"] = true
				for e: Ent in ents.values():
					if e.alive and e.owner == p:
						destroy(e, "sold")
				for pl in players:
					if pl["peer"] >= 0:
						session.s_msg(pl["peer"], "%s surrendered" % players[p]["name"])
				_check_victory()
		"pause":
			# only when no other human is in the match
			var humans := 0
			for pl in players:
				if pl["peer"] >= 0:
					humans += 1
			if humans <= 1:
				paused = bool(c.get("on", false))
				session.s_paused(paused)

func _apply_unit_cmd(e: Ent, c: Dictionary) -> void:
	var t: String = c["t"]
	var ids: Array = c.get("ids", [])
	match t:
		"move", "amove":
			var goal := Vector2(float(c["x"]), float(c["y"]))
			goal = _formation_goal(e, ids, goal)
			if e.is_building or not e.can_move():
				return
			e.guard_radius = 0.0
			_order_move(e, goal, t)
		"attack":
			var tgt: Ent = ents.get(int(c.get("tid", -1)))
			if tgt == null or not tgt.alive:
				return
			var force: bool = c.get("force", false)
			if allied(tgt.owner, e.owner) and not force:
				return
			if tgt.owner < 0 and tgt.def.get("neutral", false) and not tgt.def.get("capturable", false) and not force:
				return
			if _pick_weapon(e, tgt) < 0:
				if e.can_move() and not force:
					_order_move(e, tgt.pos)
				return
			e.state = "attack"
			e.target_id = tgt.id
			e.path = PackedVector2Array()
			e.repath_t = 0.0
			e.guard_pos = Vector2.ZERO
			e.guard_radius = 0.0
			# groups fan out around the target instead of queueing behind the first tank
			var k := ids.find(e.id)
			e.flank = 0.0 if ids.size() <= 1 or k < 0 else clampf((k - (ids.size() - 1) * 0.5) * 0.3, -1.4, 1.4)
		"attack_ground":
			if not e.has_weapons():
				return
			e.state = "attack_ground"
			e.target_id = -1
			e.goal = Vector2(float(c["x"]), float(c["y"]))
			e.path = PackedVector2Array()
			e.guard_pos = Vector2.ZERO
			e.guard_radius = 0.0
		"stop":
			e.clear_orders()
			e.resume = {}
			e.guard_pos = e.pos
			e.guard_radius = 0.0
		"guard":
			e.clear_orders()
			e.resume = {}
			e.state = "guard"
			e.guard_radius = clampf(float(c.get("r", _guard_reach(e))), 12.0, 90.0)
			if c.has("x"):
				e.guard_pos = _formation_goal(e, ids, Vector2(float(c["x"]), float(c["y"])))
				if not e.is_air():
					_set_path(e, e.guard_pos)
			else:
				e.guard_pos = e.pos
		"gather":
			if e.def.get("gatherer", 0) <= 0 or not e.cargo.is_empty():
				return
			var dock: Ent = ents.get(int(c.get("tid", -1)))
			e.state = "gather"
			e.dock_id = dock.id if dock != null and dock.type == "supply_dock" else -1
			e.target_id = -1
		"repair":
			if not e.def.get("builder", false):
				return
			var b: Ent = ents.get(int(c.get("tid", -1)))
			if b == null or not b.alive or not b.is_building or not allied(b.owner, e.owner):
				return
			e.state = "repair" if b.complete else "build"
			e.target_id = b.id
			e.path = PackedVector2Array()
			e.repath_t = 0.0
		"capture":
			if e.type != "ranger":
				return
			if not players[e.owner]["upgrades"].has("capture"):
				session.s_msg(players[e.owner]["peer"], "Requires the Capture Building upgrade (Barracks)")
				return
			var b: Ent = ents.get(int(c.get("tid", -1)))
			if b == null or not b.alive or not b.is_building or allied(b.owner, e.owner) or b.type == "supply_dock":
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
	var yaw := wrapf(float(c.get("yaw", 0.0)), -PI, PI)
	var pos := PathGrid.snap_center(Vector2(float(c["x"]), float(c["y"])), d["fp"], yaw)
	if not placement_ok(p, type, pos, yaw):
		session.s_msg(pl["peer"], "Cannot build there")
		return
	pl["cash"] -= float(d["cost"])
	var site := spawn(type, p, pos, false, yaw)
	_clear_footprint(site)
	site.builder_id = dz.id
	dz.queue.clear()
	dz.resume = {}
	dz.state = "build"
	dz.target_id = site.id
	dz.path = PackedVector2Array()
	dz.repath_t = 0.0
	events.append({"k": "place", "p": pos, "d": [site.id], "o": p})

func placement_ok(p: int, type: String, pos: Vector2, yaw := 0.0) -> bool:
	var d: Dictionary = Data.BUILDINGS[type]
	var fp: Vector2i = d["fp"]
	var half := Vector2(fp) * 1.0
	var r := half.length()
	if pos.x - r < 6.0 or pos.y - r < 6.0 or pos.x + r > map_size - 6.0 or pos.y + r > map_size - 6.0:
		return false
	if not grid.footprint_free(pos, fp, 1, yaw):
		return false
	# only ENEMY units standing in the footprint block placement; our own get moved out
	for o: Ent in query(pos, r + 1.0):
		if o.is_building or o.is_air() or o.owner < 0 or allied(o.owner, p):
			continue
		if PathGrid.rect_dist(o.pos, pos, fp, yaw) < o.radius:
			return false
	return true

## Friendly units standing where a structure goes step out of the footprint.
func _clear_footprint(site: Ent) -> void:
	var fp: Vector2i = site.def["fp"]
	var r := Vector2(fp).length() + 2.0
	for o: Ent in query(site.pos, r):
		if o.is_building or o.is_air() or not o.can_move():
			continue
		if PathGrid.rect_dist(o.pos, site.pos, fp, site.yaw) < o.radius + 0.5:
			var away := (o.pos - site.pos)
			if away.length() < 0.1:
				away = Vector2(1, 0)
			var goal := site.pos + away.normalized() * (r + o.radius)
			var c := grid.nearest_free(grid.cell_of(goal))
			if o.state == "idle" or o.state == "guard":
				var was_guard := o.state == "guard"
				var gp := o.guard_pos
				var gr := o.guard_radius
				_order_move(o, grid.center_of(c))
				if was_guard:
					o.resume = {"state": "guard", "goal": gp, "r": gr}

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
	if b == null or not b.alive or b.owner != p or not b.is_building or b.def.get("neutral", false) or b.sold:
		return
	# refund queued production / research right away, then "unbuild" the structure;
	# the sale money only arrives when it has fully sunk (destroyed meanwhile = nothing)
	var refund := 0.0
	for q in b.prod:
		refund += float(Data.UNITS[q["type"]]["cost"])
	for r in b.research:
		refund += float(Data.UPGRADES[r["id"]]["cost"])
	b.prod.clear()
	b.research.clear()
	players[p]["cash"] += refund
	b.sold = true
	if b.complete:
		b.progress = 1.0
	b.complete = false
	b.builder_id = -1
	_recompute_power(p)
	session.s_msg(players[p]["peer"], "Selling %s" % b.def["name"])

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
			strikes.append({"k": "a10", "p": pos, "t": time + 3.2, "owner": p, "level": int(pl["powers"][pid]), "heading": heading})
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
			strikes.append({"k": "fab", "p": pos, "t": time + 5.5, "owner": p})
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
	beams.append({"owner": p, "p": pos, "until": time + 10.0, "next": 0.0, "bid": b.id, "steer": true})
	for o in range(players.size()):
		session.s_msg(players[o]["peer"], "Particle Cannon fired" if o == p else "Warning: enemy Particle Cannon fired!")

# ---------------------------------------------------------------------------
# Headless probe (--simtest): drive a tank across a ridge and verify it never
# enters a solid cell.
# ---------------------------------------------------------------------------
## --simtest=load: a tank boards a Chinook, then is unloaded again.
func probe_load() -> void:
	bots.clear()
	var s: Vector2 = map["starts"][players[0]["slot"]]
	var tank := spawn("crusader", 0, s + Vector2(20, 0))
	var heli := spawn("chinook", 0, s + Vector2(30, 6))
	heli.state = "idle"
	cmd(0, {"t": "load", "ids": [tank.id], "tid": heli.id})
	print("[Probe] tank state after load cmd: ", tank.state, " target ", tank.target_id)
	for i in range(600):
		step(TICK)
		if i % 60 == 0:
			print("[Probe] t=%d tank=%s inside=%d pos=%s heli=%s alt=%.1f cargo=%s" % [i, tank.state, tank.inside_id, tank.pos.round(), heli.state, heli.alt, str(heli.cargo)])
		if tank.inside_id >= 0 and i > 100:
			print("[Probe] boarded at tick ", i)
			break
	cmd(0, {"t": "unload", "ids": [heli.id]})
	for i in range(200):
		step(TICK)
	print("[Probe] after unload: inside=%d heli=%s cargo=%s tank=%s" % [tank.inside_id, heli.state, str(heli.cargo), tank.state])

func probe_ridge() -> void:
	bots.clear()
	var tank := spawn("crusader", 0, Vector2(100, 40))
	var goal := Vector2(190, 140)
	cmd(0, {"t": "move", "ids": [tank.id], "x": goal.x, "y": goal.y})
	print("[Probe] path: ", tank.path)
	var violations := 0
	for i in range(1500):
		step(TICK)
		if grid.is_solid_pos(tank.pos):
			violations += 1
			if violations < 5:
				print("[Probe] IN SOLID at tick %d pos %s" % [i, tank.pos])
		if i % 100 == 0:
			print("[Probe] t=%d pos=%s state=%s path_i=%d/%d" % [i, tank.pos.round(), tank.state, tank.path_i, tank.path.size()])
		if tank.state == "idle" and i > 20:
			print("[Probe] arrived at tick %d pos %s" % [i, tank.pos.round()])
			break
	print("[Probe] solid violations: ", violations)
	var solid := 0
	var total := 0
	for pr in map["props"]:
		if pr.get("kind", "") == "mountain":
			for c in PathGrid.footprint_cells(pr["p"], pr["fp"]):
				total += 1
				if grid.is_solid(c):
					solid += 1
	print("[Probe] mountain cells solid: %d / %d" % [solid, total])
