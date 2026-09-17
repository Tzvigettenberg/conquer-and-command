class_name ClientView
extends Node3D
## Everything the local player sees: replicated puppets, map, fog, camera, HUD, FX.

var map: Dictionary
var my_index := 0                  # -1 = observer (sees everything, commands nothing)
var observer := false
var my_faction := "usa"
var puppets: Dictionary = {}       # id -> Puppet
var pstate: Dictionary = {}
var map_view: MapView
var fx: Fx
var camera: RtsCamera
var ctl: Controller
var hud: Hud
var icons: Icons
var grid := PathGrid.new()         # client-side copy for placement previews
var alerts: Array = []
var game_over := false
var args: Dictionary = {}
var names: Array = []
var last_snapshot_tick := 0
var last_unlock_sig := ""
var session: Session

func setup(m: Dictionary, index: int, lobby: Array, _args: Dictionary) -> void:
	map = m
	my_index = index
	observer = index < 0
	args = _args
	session = get_parent().session
	names = m.get("player_names", []).duplicate()
	if names.is_empty():
		for p in lobby:
			names.append(p["name"])
	var facs: Array = m.get("player_factions", [])
	if index >= 0 and index < facs.size():
		my_faction = str(facs[index])
	grid.setup(float(m["size"]))
	for pr in m["props"]:
		var fp: Vector2i = pr["fp"]
		if fp != Vector2i.ZERO and pr.get("kind", "") != "civ":
			grid.set_cells(PathGrid.footprint_cells(pr["p"], fp), true)
	for rd in m.get("ridges", []):
		grid.set_cells(PathGrid.capsule_cells(rd["a"], rd["b"], float(rd["w"]) + 0.5), true)
	map_view = MapView.new()
	map_view.name = "MapView"
	add_child(map_view)
	map_view.setup(m)
	fx = Fx.new()
	fx.name = "Fx"
	add_child(fx)
	camera = RtsCamera.new()
	camera.name = "Camera"
	add_child(camera)
	var slots_arr: Array = m.get("player_slots", [])
	var start := Vector2(float(m["size"]) * 0.5, float(m["size"]) * 0.5)
	if not observer:
		start = m["starts"][int(slots_arr[index]) if index < slots_arr.size() else index]
	camera.setup(float(m["size"]), start + Vector2(0, 10))
	camera.yaw = float(m["start_yaw"][index]) if not observer else 0.0
	camera.edge_scroll = bool(Settings.load_cfg().get("edge_scroll", true))
	camera._apply()
	ctl = Controller.new()
	ctl.name = "Controller"
	add_child(ctl)
	ctl.setup(self)
	icons = Icons.new()
	icons.name = "Icons"
	add_child(icons)
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(self, ctl)
	icons.ready_changed.connect(func() -> void: hud.refresh_selection())
	Audio.I.eva("welcome", 0.0)
	if observer:
		map_view.reveal_all()
		map_view.disable_fog()
		on_msg("Observer mode: you see everything and command nothing.  Enter: chat   Esc: menu")
	else:
		on_msg("Welcome, %s. You are %s, playing %s." % [names[index] if index < names.size() else "Commander", Data.TEAM_NAMES[index], Data.FACTIONS[my_faction]["name"]])
	if args.has("test"):
		_run_test(str(args["test"]))
	if args.has("zoom"):
		camera.height = float(args["zoom"])
		camera._apply()
	if args.has("look"):
		var xy := str(args["look"]).split(",")
		camera.jump_to(Vector2(float(xy[0]), float(xy[1])))
	if args.has("showcase"):
		# debug: every unit (or structure, --showcase=buildings) model in a grid by the base;
		# --showcase_faction=x limits it to one side
		var i := 0
		var want_fac := str(args.get("showcase_faction", ""))
		var blds := str(args["showcase"]) == "buildings"
		var cols := 8 if not blds else 4
		var step := 9.0 if not blds else 26.0
		var centre := Vector2(float(m["size"]) * 0.5, float(m["size"]) * 0.5)
		var mid := start + (centre - start).normalized() * (38.0 if not blds else 75.0)
		var c0 := mid - Vector2(cols * step * 0.5 - step * 0.5, (5.0 if not blds else 26.0))
		for t in (Data.BUILDINGS if blds else Data.UNITS):
			if want_fac != "" and Data.faction_of(t) != want_fac:
				continue
			if blds and Data.BUILDINGS[t].get("neutral", false):
				continue
			var mdl := Visuals.make_model(t, my_index)
			mdl.position = Vector3(c0.x + (i % cols) * step, 0, c0.y + (i / cols) * step)
			mdl.rotation.y = 0.6 if not blds else 0.0
			add_child(mdl)
			var lbl := Label3D.new()
			lbl.text = Data.def(t)["name"]
			lbl.font_size = 64
			lbl.pixel_size = 0.012
			lbl.position = mdl.position + Vector3(0, 0.3, (4.5 if not blds else 14.0))
			lbl.rotation.x = -PI * 0.5
			lbl.modulate = Color(1, 1, 1)
			lbl.outline_size = 16
			add_child(lbl)
			i += 1
		camera.jump_to(mid + Vector2(0, 4.0 if not blds else 12.0))
		camera.yaw = 0.0
		camera._apply()
	if args.has("fxdemo"):
		# debug: explosions and missiles near the base every second
		var fxt := Timer.new()
		fxt.wait_time = 1.0
		fxt.autostart = true
		fxt.timeout.connect(func() -> void:
			var c := Vector3(start.x + randf_range(-20, 20), 0, start.y + 20 + randf_range(-10, 10))
			fx.explosion(c, [1.0, 1.6, 3.0][randi() % 3])
			fx.shot(Vector3(start.x - 30, 2, start.y + 10), c + Vector3(6, 0, 0), "md_missile")
			fx.shot(Vector3(start.x + 30, 2, start.y - 10), c + Vector3(-6, 0, 0), "tomahawk"))
		add_child(fxt)
	if args.has("select"):
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			var p := _own(str(args["select"]))
			if p != null:
				ctl.set_selection([p.id]))
	if args.has("screenshot"):
		_screenshots(str(args["screenshot"]))
	if args.has("exit_after"):
		get_tree().create_timer(float(args["exit_after"])).timeout.connect(func() -> void:
			print("[Test] exiting")
			get_tree().quit())

func _screenshots(dir: String) -> void:
	var n := 0
	while is_inside_tree():
		await get_tree().create_timer(float(args.get("shot_every", 8.0))).timeout
		if not is_inside_tree():
			return
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/shot_%02d.png" % [dir, n]
		img.save_png(path)
		print("[Shot] saved ", path)
		n += 1

func send(c: Dictionary) -> void:
	if observer:
		return   # spectators never touch the sim
	session.send_cmd(c)

# ---------------------------------------------------------------------------
# Replication callbacks
# ---------------------------------------------------------------------------
func on_spawn(id: int, type: String, owner: int, pos: Vector2, alt: float, yaw: float, extra: Dictionary) -> void:
	var p: Puppet = puppets.get(id)
	if p != null:
		if p.team != owner:
			# captured: rebuild the visual with the new colours
			p.queue_free()
			puppets.erase(id)
			_unblock(p)
		else:
			p.complete = extra.get("complete", p.complete)
			p.boxes = extra.get("boxes", p.boxes)
			return
	p = Puppet.new()
	p.name = "E%d" % id
	add_child(p)
	p.setup(id, type, owner, pos, alt, yaw, extra, owner == my_index)
	puppets[id] = p
	if p.is_building:
		p.set_meta("cells", PathGrid.footprint_cells(pos, Data.BUILDINGS[type]["fp"], yaw))
		grid.set_cells(p.get_meta("cells"), true)

func _unblock(p: Puppet) -> void:
	if p.is_building and p.has_meta("cells"):
		grid.set_cells(p.get_meta("cells"), false)

func on_despawn(id: int, reason: String) -> void:
	var p: Puppet = puppets.get(id)
	if p == null:
		return
	puppets.erase(id)
	_unblock(p)
	if reason == "killed":
		Audio.I.death(p.type, p.cur_pos)
		if p.cat == "inf":
			fx.death(p.type, p.cur_pos, p.cur_yaw, p.detach_model())
		elif p.cat == "air" and p.cur_pos.y > 1.0:
			fx.crash(p.type, p.cur_pos, p.cur_yaw, p.detach_model(), Vector3(p.vel.x, 0, p.vel.z).length())
		else:
			fx.death(p.type, p.cur_pos, p.cur_yaw)
	elif reason == "sold" and p.team == my_index:
		Audio.I.ui("sell")
	ctl.selected.erase(id)
	p.queue_free()
	ctl._refresh_sig()

func on_state(bytes: PackedByteArray) -> void:
	var buf := StreamPeerBuffer.new()
	buf.data_array = bytes
	var tick := buf.get_u32()
	if tick < last_snapshot_tick:
		return
	last_snapshot_tick = tick
	var n := buf.get_u16()
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(n):
		var id := buf.get_u16()
		var x := buf.get_16() / 20.0
		var y := buf.get_16() / 20.0
		var alt := buf.get_u16() / 20.0
		var yaw := buf.get_u8() / 255.0 * TAU
		var tyaw := buf.get_u8() / 255.0 * TAU
		var hpf := buf.get_u8() / 255.0
		var flags := buf.get_u8()
		var aux := buf.get_u8()
		var aux2 := buf.get_u8()
		var p: Puppet = puppets.get(id)
		if p == null:
			continue
		p.apply_state(Vector2(x, y), alt, yaw, tyaw, hpf, flags, aux, aux2, now)
	# hide units that stopped being replicated (left our vision); structures go dim and still
	for p in puppets.values():
		if not p.ghost and p.is_stale(now):
			p.set_ghost(true)
			if p.selected:
				ctl.selected.erase(p.id)
				p.selected = false
				ctl._refresh_sig()
		elif not p.is_building and p.ghost and not p.is_stale(now):
			p.ghost = false
			p.visible = true

func on_events(evs: Array) -> void:
	for ev in evs:
		var k: String = ev[0]
		var d: Array = ev[1]
		match k:
			"shot":
				var a: Puppet = puppets.get(int(d[0]))
				var from := Vector3(0, 0, 0)
				if a != null:
					from = a.cur_pos + Vector3(0, 1.2 if a.cat == "inf" else (1.8 if not a.is_building else 3.0), 0)
					if a.cat == "air":
						from = a.cur_pos + Vector3(0, -0.5, 0)
				else:
					continue
				fx.shot(from, Vector3(d[2], float(d[4]) + 0.8, d[3]), str(d[1]), int(d[6]) if d.size() > 6 else -1)
				Audio.I.weapon(str(d[1]), from)
			"hit":
				var wd: Dictionary = Data.WEAPONS.get(str(d[0]), {})
				if str(d[0]) == "fab":
					fx.explosion(Vector3(d[1], 0, d[2]), 9.0)
					Audio.I.sfx("explosion_large", Vector3(d[1], 2, d[2]), 8.0, 0.0, 0.5)
				elif str(d[0]) == "nuke":
					fx.nuke_blast(Vector3(d[1], 0, d[2]))
					Audio.I.sfx("explosion_large", Vector3(d[1], 2, d[2]), 10.0, 0.0, 0.5)
					Audio.I.sfx("explosion_large", Vector3(d[1], 2, d[2]), 8.0, 0.0, 0.5)
					camera.shake(2.5)
				elif str(d[0]) in ["scud_storm", "carpet_bomb", "anthrax_bomb", "demo_charge", "terrorist_bomb", "bombtruck_bomb"]:
					fx.explosion(Vector3(d[1], 0, d[2]), 4.0 if str(d[0]) != "terrorist_bomb" else 2.5)
					Audio.I.sfx("explosion_large", Vector3(d[1], 2, d[2]), 4.0, 0.0, 0.3)
				else:
					fx.impact(Vector3(d[1], float(d[3]), d[2]), wd.get("style", "shell"), str(d[0]))
					Audio.I.impact(wd.get("style", "shell"), Vector3(d[1], float(d[3]), d[2]))
			"pd":
				# point-defence laser burns an incoming missile out of the air
				var dp: Puppet = puppets.get(int(d[0]))
				var hit_at := Vector3(d[1], float(d[3]), d[2])
				var sid := int(d[4]) if d.size() > 4 else -1
				var live := fx.kill_projectile(sid)
				if live.x > -9000.0:
					hit_at = live
				if dp != null:
					fx.laser(dp.cur_pos + Vector3(0, 2.2, 0), hit_at)
					Audio.I.sfx("laser_zap", dp.cur_pos, -4.0, 0.1, 0.1)
				fx.explosion(hit_at, 0.6)
			"die":
				pass   # despawn carries the visual death
			"cash":
				var b: Puppet = puppets.get(int(d[1])) if d.size() > 1 else null
				var at := b.cur_pos + Vector3(0, float(b.def.get("height", 6.0)) * 0.7, 0) if b != null else Vector3(0, 0, 0)
				if b != null:
					fx.floating_text(at, "+$%d" % int(d[0]), Color(1.0, 0.9, 0.3))
					Audio.I.sfx("cash", at, -4.0, 0.05, 0.3)
			"alert":
				alerts.append({"p": Vector2(d[0], d[1]), "t": Time.get_ticks_msec() / 1000.0})
				Audio.I.ui("alert", -8.0)
				while alerts.size() > 8:
					alerts.pop_front()
			"load", "unload":
				var tp: Puppet = puppets.get(int(d[0]))
				if tp != null:
					Audio.I.sfx("metal_hit", tp.cur_pos, 0.0, 0.1, 0.2)
					Audio.I.sfx("ui_click", tp.cur_pos, -2.0, 0.0, 0.1)
					if k == "load":
						tp.flash_cargo()
			"supply_drop":
				fx.supply_drop(Vector3(d[0], 0, d[1]), int(ev[1][2]) if false else _owner_of(int(d[2])))
			"upgraded":
				Audio.I.upgrade_voice(str(d[0]))
			"produced":
				var fac: Puppet = puppets.get(int(d[0]))
				if fac != null:
					fac.open_door(3.2)
					if fac.type == "war_factory":
						Audio.I.sfx("door", fac.cur_pos + Vector3(0, 2, 0), -6.0, 0.05, 0.5)
			"beacon":
				var who := int(d[2])
				alerts.append({"p": Vector2(d[0], d[1]), "t": Time.get_ticks_msec() / 1000.0, "beacon": true})
				fx.beacon(Vector3(d[0], 0, d[1]), Data.TEAM_COLORS[who % Data.TEAM_COLORS.size()])
				on_msg("%s placed a beacon (Space to jump there)" % (names[who] if who < names.size() else "Ally"))
				Audio.I.ui("alert", -6.0)
			"beam":
				var src: Puppet = puppets.get(int(d[2])) if d.size() > 2 else null
				fx.particle_beam(Vector3(d[0], 0, d[1]), int(d[3]) if d.size() > 3 else -1, src.cur_pos + Vector3(0, 10.5, 0) if src != null else Vector3(-1, -1, -1))
				Audio.I.sfx("superweapon_fire", Vector3(d[0], 5, d[1]), 4.0, 0.05, 1.5)
			"strike":
				fx.strike(str(d[0]), Vector3(d[1], 0, d[2]), float(d[3]), int(d[4]) if d.size() > 4 else 1)
				match str(d[0]):
					"a10":
						Audio.I.sfx("jet_flyby", Vector3(d[1], 20, d[2]), 4.0)
						Audio.I.eva("a10", 2.0)
					"paradrop":
						Audio.I.sfx("plane_pass", Vector3(d[1], 30, d[2]), 4.0)
						Audio.I.eva("paradrop", 2.0)
					"fuel_air_bomb":
						Audio.I.sfx("jet_flyby", Vector3(d[1], 30, d[2]), 4.0)
						Audio.I.eva("fuel_air_bomb", 2.0)
					"spy_satellite":
						Audio.I.sfx("satellite", Vector3(d[1], 5, d[2]), 0.0)
						Audio.I.eva("spy_satellite", 2.0)
					"emergency_repair":
						Audio.I.sfx("repair", Vector3(d[1], 2, d[2]), 0.0)
						Audio.I.eva("emergency_repair", 2.0)
					"artillery_barrage":
						Audio.I.sfx("artillery_fire", Vector3(d[1], 2, d[2]), 2.0)
					"carpet_bomb", "anthrax_bomb":
						Audio.I.sfx("plane_pass", Vector3(d[1], 30, d[2]), 4.0)
					"cash_hack":
						Audio.I.sfx("cash", Vector3(d[1], 2, d[2]), 0.0)
					"spectre_gunship":
						Audio.I.sfx("plane_pass", Vector3(d[1], 40, d[2]), 4.0)
					"intel", "spy_drone":
						Audio.I.sfx("satellite", Vector3(d[1], 5, d[2]), 0.0)
			"zone":
				fx.zone(str(d[0]), Vector3(d[1], 0, d[2]), float(d[3]), float(d[4]))
			"gunship_shot":
				fx.gunship_shot(Vector3(d[0], 0, d[1]), Vector3(d[2], 0, d[3]), int(d[4]) == 1)
			"sw_launch":
				fx.sw_launch(str(d[0]), Vector3(d[1], 0, d[2]), Vector3(d[3], 0, d[4]), float(d[5]))
				Audio.I.sfx("superweapon_fire", Vector3(d[1], 5, d[2]), 6.0)
				Audio.I.eva("superweapon_launched", 2.0)
			"place":
				var b0: Puppet = puppets.get(int(d[0]))
				if b0 != null:
					Audio.I.sfx("place_building", b0.cur_pos, 0.0, 0.05, 0.2)
			"built":
				var b: Puppet = puppets.get(int(d[0]))
				if b != null:
					fx.placed(b.cur_pos, Data.footprint_size(b.type), b.cur_yaw)
					Audio.I.sfx("chime", b.cur_pos, -6.0, 0.0, 0.2)

func _process(_dt: float) -> void:
	_update_links(_dt)
	if camera != null and camera.cam != null:
		Audio.I.listener_pos = camera.listener.global_position if camera.listener != null else camera.cam.global_position

func contrail(a: Vector3, b: Vector3) -> void:
	if fx.items.size() < 1400:
		fx.contrail(a, b)

func leave_track(pos: Vector3, yaw: float, half_w: float, tracked: bool) -> void:
	if fx.items.size() < 900:
		fx.track(pos, yaw, half_w, tracked)

func on_fog(bytes: PackedByteArray) -> void:
	if observer:
		return   # never sent to observers anyway; the map is fully revealed
	if args.has("reveal"):
		map_view.reveal_all()   # debug: --reveal shows the whole map
		return
	if bytes.size() < 4:
		return
	var raw := bytes.slice(4).decompress(bytes.decode_u32(0), FileAccess.COMPRESSION_FASTLZ)
	if not raw.is_empty():
		map_view.update_fog(raw)

## Upgrade / battle-plan visuals for every puppet we can see.
func _push_extras(st: Dictionary) -> void:
	var all_upg: Array = st.get("all_upgrades", [])
	var plans: Array = st.get("plans", [])
	var upg_done: Dictionary = st.get("upg_done", {})
	for pu in puppets.values():
		var p: Puppet = pu
		if p.team < 0:
			if p.is_building and p.def.get("garrison", false):
				p.set_garrison(st.get("cargo", {}).get(p.id, []), int(st.get("garrison", {}).get(p.id, -2)))
			continue
		var keys: Array = []
		if p.team < all_upg.size():
			keys = Array(all_upg[p.team]).duplicate()
		if upg_done.has(p.id):
			for k in upg_done[p.id]:
				keys.append(k)
		if p.type == "strategy_center" and p.team < plans.size() and str(plans[p.team]) != "":
			keys.append("plan_" + str(plans[p.team]))
		if p.def.has("superweapon") and (p.team == my_index and sw_remaining(p.id) <= 0.0 or p.team != my_index and sw_ready(p.team)):
			keys.append("sw_ready")
		keys.sort()
		p.set_extras(keys)
		if p.is_building and p.def.has("cargo"):
			p.set_garrison(st.get("cargo", {}).get(p.id, []), int(st.get("garrison", {}).get(p.id, -2)))

## Patriot data-links: cyan lines between batteries close enough to share targets.
var link_nodes: Array = []
var link_t := 0.0
func _update_links(dt: float) -> void:
	return   # data-link lines were more confusing than helpful; batteries still assist each other in the sim
	link_t -= dt
	if link_t > 0.0:
		return
	link_t = 1.0
	for n in link_nodes:
		n.queue_free()
	link_nodes.clear()
	var pats: Array = []
	for pu in puppets.values():
		var p: Puppet = pu
		if p.type == "patriot" and p.complete and not p.ghost and p.team >= 0:
			pats.append(p)
	for i in range(pats.size()):
		for j in range(i + 1, pats.size()):
			var a: Puppet = pats[i]
			var b: Puppet = pats[j]
			if a.team != b.team:
				continue
			if a.cur_pos.distance_to(b.cur_pos) > World.PATRIOT_LINK:
				continue
			var hot := (a.flags & 2) != 0 or (b.flags & 2) != 0
			var col := Color(0.4, 0.9, 1.0, 0.9 if hot else 0.45)
			var beam := fx._beam_mesh(a.cur_pos + Vector3(0, 2.6, 0), b.cur_pos + Vector3(0, 2.6, 0), col, 0.12 if hot else 0.07)
			add_child(beam)
			link_nodes.append(beam)

func _owner_of(id: int) -> int:
	var p: Puppet = puppets.get(id)
	return p.team if p != null else -1

func send_chat(text: String, allies: bool) -> void:
	if session.world != null:
		if observer:
			session.relay_chat(-1, "[%s] %s" % [Main.I.my_name, text], false)
		else:
			session.relay_chat(my_index, text, allies)
	else:
		session.rpc_id(1, "srv_chat", text, allies)

func on_chat(from: int, text: String, allies: bool) -> void:
	hud.chat_line(from, text, allies)

func on_pstate(st: Dictionary) -> void:
	var unlock_sig := str(st.get("powers", {})) + str(st.get("upgrades", [])) + str(st.get("rank", 0))
	pstate = st
	_push_extras(st)
	if unlock_sig != last_unlock_sig:
		# a promotion or upgrade just landed: the command cards must re-evaluate what is unlocked
		last_unlock_sig = unlock_sig
		if hud != null:
			hud.refresh_selection()
	var docks: Dictionary = st.get("docks", {})
	for id in docks:
		var p: Puppet = puppets.get(int(id))
		if p != null and p.type == "supply_dock" and p.boxes != int(docks[id]):
			p.set_crates(int(docks[id]))

func on_msg(text: String) -> void:
	print("[MSG p%d] %s" % [my_index, text])
	if hud:
		hud.add_message(text)
	Audio.I.eva_for_message(text)
	if "Insufficient funds" in text:
		hud.flash_cash()
	elif "Cannot build" in text or "Requires" in text or "Airfield full" in text or "Limit reached" in text:
		Audio.I.ui("ui_error", -6.0)
	if "Low power" in text:
		Audio.I.ui("power_down", -2.0)

func on_gameover(winner: int, rep: Array = []) -> void:
	game_over = true
	var my_team := my_index
	var teams: Array = pstate.get("teams", [])
	if my_index < teams.size():
		my_team = int(teams[my_index])
	var text := "DEFEAT"
	if winner == -2:
		text = "DISCONNECTED"
	elif observer:
		text = "GAME OVER" if winner < 0 else "TEAM %d WINS" % (winner + 1)
	elif winner == my_team:
		text = "VICTORY"
	elif winner == -1:
		text = "GAME OVER"
	hud.show_gameover(text, rep)
	map_view.reveal_all()
	ctl.cancel_mode()
	if observer:
		if winner != -2:
			Audio.I.play_music("victory")
	elif winner == my_team:
		Audio.I.ui("victory")
		Audio.I.eva("victory", 0.0)
		Audio.I.play_music("victory")
	elif winner != -2:
		Audio.I.ui("defeat")
		Audio.I.play_music("defeat")
		Audio.I.eva("defeat", 0.0)

func on_paused(on: bool) -> void:
	hud.set_paused(on)

## Faction of any player (from the map handshake / pstate).
func faction_of(team_idx: int) -> String:
	var facs: Array = pstate.get("factions", map.get("player_factions", []))
	if team_idx >= 0 and team_idx < facs.size():
		return str(facs[team_idx])
	return "usa"

## Can this player pick / use this general's power?
func power_for_me(pid: String) -> bool:
	var f := str(Data.POWERS[pid].get("faction", "usa"))
	return f == "all" or f == my_faction

## Name of a player's superweapon (for the countdown strip).
func sw_name(team_idx: int) -> String:
	for pu in puppets.values():
		if pu.team == team_idx and pu.is_building and pu.def.has("superweapon"):
			return pu.def["name"]
	var f := faction_of(team_idx)
	for bt in Data.BUILDINGS:
		if Data.BUILDINGS[bt].has("superweapon") and Data.faction_of(bt) == f:
			return Data.BUILDINGS[bt]["name"]
	return "Superweapon"

func is_ally(team_idx: int) -> bool:
	if observer:
		return false
	if team_idx == my_index:
		return true
	if team_idx < 0:
		return false
	var teams: Array = pstate.get("teams", [])
	if my_index < teams.size() and team_idx < teams.size():
		return teams[my_index] == teams[team_idx]
	return false

# ---------------------------------------------------------------------------
# Helpers for HUD / controller
# ---------------------------------------------------------------------------
func can_afford(cost: int) -> bool:
	return int(pstate.get("cash", 0)) >= cost

func has_building(type: String) -> bool:
	for p in puppets.values():
		if p.team == my_index and p.type == type and p.complete:
			return true
	return false

func count_own(type: String) -> int:
	var n := 0
	for p in puppets.values():
		if p.team == my_index and p.type == type:
			n += 1
	return n

func has_upgrade(uid: String, bid := -1) -> bool:
	if pstate.get("upgrades", []).has(uid):
		return true
	if bid >= 0:
		var ud: Dictionary = pstate.get("upg_done", {})
		if ud.has(bid) and ud[bid].has(uid):
			return true
	return false

## Is this upgrade being researched (anywhere, or - for per-building upgrades like
## control rods - at this particular building)?
func is_researching(uid: String, bid := -1) -> bool:
	var rq: Dictionary = pstate.get("research_q", {})
	if bid >= 0 and Data.UPGRADES[uid].get("per_building", false):
		return rq.has(bid) and rq[bid].has(uid)
	for b in rq:
		if rq[b].has(uid):
			return true
	return false

func airfield_full(bid: int) -> bool:
	var al: Dictionary = pstate.get("air_load", {})
	if not al.has(bid):
		return false
	return int(al[bid][0]) >= int(al[bid][1])

func building_prereq_text(type: String) -> String:
	var d: Dictionary = Data.BUILDINGS[type]
	for r in d.get("prereq", []):
		if not has_building(r):
			return "Needs %s" % Data.BUILDINGS[r]["name"]
	if d.has("prereq_any"):
		var ok := false
		for r in d["prereq_any"]:
			if has_building(r):
				ok = true
		if not ok:
			return "Needs %s" % Data.BUILDINGS[d["prereq_any"][0]]["name"]
	if d.has("limit") and count_own(type) >= int(d["limit"]):
		return "Max %d" % int(d["limit"])
	return ""

func unit_prereq_text(type: String) -> String:
	var d: Dictionary = Data.UNITS[type]
	for r in d.get("prereq", []):
		if not has_building(r):
			return "Needs %s" % Data.BUILDINGS[r]["name"]
	if d.has("needs_power"):
		if int(pstate.get("powers", {}).get(d["needs_power"], 0)) <= 0:
			return "Needs promotion (%s)" % Data.POWERS[d["needs_power"]]["name"]
	if d.has("limit") and count_own(type) >= int(d["limit"]):
		return "Limit reached"
	return ""

func sw_ready(owner: int) -> bool:
	var sw: Dictionary = pstate.get("sw", {})
	return sw.has(owner) and float(sw[owner]) <= 0.0

## This particular cannon's charge (each one is its own weapon).
func sw_remaining(bid: int) -> float:
	var swb: Dictionary = pstate.get("sw_bld", {})
	return float(swb.get(bid, 0.0))

func placement_ok(type: String, pos: Vector2, yaw := 0.0) -> bool:
	var d: Dictionary = Data.BUILDINGS[type]
	var fp: Vector2i = d["fp"]
	var r := Vector2(fp).length()
	var size := float(map["size"])
	if pos.x - r < 6.0 or pos.y - r < 6.0 or pos.x + r > size - 6.0 or pos.y + r > size - 6.0:
		return false
	if not grid.footprint_free(pos, fp, 1, yaw):
		return false
	if not map_view.is_explored(pos):
		return false
	return true

# ---------------------------------------------------------------------------
# Scripted smoke test (headless verification): --test=smoke
# ---------------------------------------------------------------------------
func _own(type: String) -> Puppet:
	for p in puppets.values():
		if p.team == my_index and p.type == type:
			return p
	return null

func _own_ids(filter: Callable) -> Array:
	var out := []
	for p in puppets.values():
		if p.team == my_index and filter.call(p):
			out.append(p.id)
	return out

func _enemy_start() -> Vector2:
	var slots_arr: Array = map.get("player_slots", [])
	for i in range(slots_arr.size()):
		if i != my_index:
			return map["starts"][int(slots_arr[i])]
	return Vector2(float(map["size"]) * 0.5, float(map["size"]) * 0.5)

func _run_test(kind: String) -> void:
	print("[Test] scenario %s as player %d" % [kind, my_index])
	if kind == "observe":
		# spectator probe: everything replicated, scoreboard populated, commands ignored
		while is_inside_tree():
			await get_tree().create_timer(10.0).timeout
			if not is_inside_tree():
				return
			var per_team := {}
			for p in puppets.values():
				per_team[p.team] = per_team.get(p.team, 0) + 1
			var board: Array = pstate.get("board", [])
			var bl := []
			for b in board:
				bl.append("%s $%d u%d b%d%s" % [b["name"], b["cash"], b["units"], b["blds"], " DEFEATED" if b["defeated"] else ""])
			print("[Test obs] t=%.0f puppets=%s board=[%s]" % [pstate.get("time", 0.0), str(per_team), " | ".join(bl)])
			send({"t": "surrender"})   # must be a no-op for spectators
		return
	if kind == "faction":
		await _faction_test()
		return
	await get_tree().create_timer(1.5).timeout
	var cc := _own("command_center")
	var dz := _own("dozer")
	if cc == null or dz == null:
		print("[Test] FAIL: no command center / dozer")
		return
	var base := Vector2(cc.cur_pos.x, cc.cur_pos.z)
	var dir := 1.0 if my_index == 0 else -1.0
	var plan := [
		["power_plant", base + Vector2(22, 0) * dir],
		["barracks", base + Vector2(0, 22) * dir],
		["supply_center", base + Vector2(24, 24) * dir],
		["war_factory", base + Vector2(-22, 24) * dir],
		["patriot", base + Vector2(30, -12) * dir],
		["strategy_center", base + Vector2(-28, -6) * dir],
	]
	for step in plan:
		var pos: Vector2 = PathGrid.snap_center(step[1], Data.BUILDINGS[step[0]]["fp"])
		send({"t": "build", "id": dz.id, "type": step[0], "x": pos.x, "y": pos.y})
		print("[Test] ordered %s at %s" % [step[0], pos])
		var waited := 0.0
		while waited < 90.0:
			await get_tree().create_timer(1.0).timeout
			waited += 1.0
			var b := _own(step[0])
			if b != null and b.complete:
				print("[Test] %s complete after %.0fs (cash %d)" % [step[0], waited, pstate.get("cash", 0)])
				break
			if b == null and waited > 6.0:
				print("[Test] WARN %s never placed" % step[0])
				break
	# production
	send({"t": "cheat_cash"})
	if args.has("screenshot"):
		ctl.set_selection([dz.id])          # build menu in the shots
		await get_tree().create_timer(9.0).timeout
		hud._toggle_promo()
		await get_tree().create_timer(9.0).timeout
		hud.close_promo()
	var bar := _own("barracks")
	if bar:
		for i in range(4):
			send({"t": "produce", "id": bar.id, "type": "ranger"})
		send({"t": "produce", "id": bar.id, "type": "missile_defender"})
	var wf := _own("war_factory")
	var stc := _own("strategy_center")
	if stc:
		send({"t": "plan", "id": stc.id, "plan": "bombardment"})
	if wf and args.has("screenshot"):
		ctl.set_selection([wf.id])
	if wf:
		for i in range(3):
			send({"t": "produce", "id": wf.id, "type": "crusader"})
		send({"t": "produce", "id": wf.id, "type": "humvee"})
		send({"t": "upgrade", "id": wf.id, "uid": "tow"})
	var sc := _own("supply_center")
	if sc:
		send({"t": "produce", "id": sc.id, "type": "chinook"})
	if args.has("screenshot"):
		await get_tree().create_timer(9.0).timeout
		if stc:
			ctl.set_selection([stc.id])
		await get_tree().create_timer(9.0).timeout
		if wf:
			ctl.set_selection([wf.id])
	if bar:
		send({"t": "upgrade", "id": bar.id, "uid": "capture"})
		send({"t": "upgrade", "id": bar.id, "uid": "capture"})   # duplicate must be rejected
	send({"t": "cheat_cash"})
	send({"t": "cheat_cash"})
	# airfield + a raptor to exercise the flight model
	var af_pos := PathGrid.snap_center(base + Vector2(-30, -20) * dir, Data.BUILDINGS["airfield"]["fp"], 0.6)
	send({"t": "build", "id": dz.id, "type": "airfield", "x": af_pos.x, "y": af_pos.y, "yaw": 0.6})
	await get_tree().create_timer(45.0).timeout
	var af := _own("airfield")
	if af and af.complete:
		send({"t": "produce", "id": af.id, "type": "raptor"})
		print("[Test] airfield done, raptor queued")
	else:
		print("[Test] WARN airfield not complete")
	_report()
	# capture the nearest derrick with two rangers: walk there first so it is revealed
	var dpos: Vector2 = map["derricks"][0]
	for dd in map["derricks"]:
		if dd.distance_to(base) < dpos.distance_to(base):
			dpos = dd
	var walkers := _own_ids(func(p: Puppet) -> bool: return p.type == "ranger")
	if walkers.size() >= 2:
		send({"t": "move", "ids": walkers.slice(0, 2), "x": dpos.x, "y": dpos.y + 6.0, "q": false})
		print("[Test] rangers walking to derrick at %s" % dpos)
	await get_tree().create_timer(45.0).timeout
	var derrick: Puppet = null
	for pp in puppets.values():
		if pp.type == "oil_derrick" and (derrick == null or pp.cur_pos.distance_to(Vector3(base.x, 0, base.y)) < derrick.cur_pos.distance_to(Vector3(base.x, 0, base.y))):
			derrick = pp
	var rangers := _own_ids(func(p: Puppet) -> bool: return p.type == "ranger")
	if derrick != null and rangers.size() >= 2:
		send({"t": "capture", "ids": rangers.slice(0, 2), "tid": derrick.id})
		print("[Test] capturing derrick %d at %s" % [derrick.id, derrick.cur_pos])
	await get_tree().create_timer(30.0).timeout
	var raptor := _own("raptor")
	var enemy_base0: Vector2 = _enemy_start()
	if raptor:
		send({"t": "attack_ground", "ids": [raptor.id], "x": enemy_base0.x, "y": enemy_base0.y})
		print("[Test] raptor force-attacking enemy base")
	if derrick != null:
		print("[Test] derrick owner now %d" % derrick.team)
	_report()
	# send the army toward the enemy base
	var enemy_base: Vector2 = _enemy_start()
	var army := _own_ids(func(p: Puppet) -> bool: return not p.is_building and p.cat != "air" and not p.def.get("builder", false))
	print("[Test] attack-moving %d units to %s" % [army.size(), enemy_base])
	send({"t": "amove", "ids": army, "x": enemy_base.x, "y": enemy_base.y, "q": false})
	for i in range(6):
		await get_tree().create_timer(15.0).timeout
		_report()
	print("[Test] done")

## Spiral out from the base for a legal footprint (client-side placement check).
func _find_spot(type: String, base: Vector2) -> Vector2:
	var fp: Vector2i = Data.BUILDINGS[type]["fp"]
	var r := 14.0
	while r < 90.0:
		var n := int(TAU * r / 4.0)
		for i in range(n):
			var a := TAU * i / n
			var cand := PathGrid.snap_center(base + Vector2(cos(a), sin(a)) * r, fp)
			if placement_ok(type, cand, 0.0):
				return cand
		r += 6.0
	return Vector2(-1, -1)

## Generic per-faction smoke: build the opening of the faction's build order, train
## everything each structure offers, research, fire powers, load a transport / tunnel,
## and keep selecting things so the HUD renders every kind of card.
func _faction_test() -> void:
	await get_tree().create_timer(1.5).timeout
	var fd: Dictionary = Data.FACTIONS[my_faction]
	print("[Test] faction %s" % my_faction)
	var cc := _own(fd["cc"])
	var dz := _own(fd["builder"])
	if cc == null or dz == null:
		print("[Test] FAIL: no command center / builder for %s" % my_faction)
		return
	var base := Vector2(cc.cur_pos.x, cc.cur_pos.z)
	send({"t": "cheat_cash"})
	send({"t": "cheat_cash"})
	send({"t": "cheat_cash"})
	var order: Array = fd["build_order"]
	var built := {}
	for i in range(mini(order.size(), 9)):
		var bt: String = order[i]
		if built.has(bt) and Data.role_of(bt) != "power":
			continue
		var pos := _find_spot(bt, base)
		if pos.x < 0:
			print("[Test] WARN no spot for %s" % bt)
			continue
		var b0 := _own(bt)
		var n0 := count_own(bt)
		send({"t": "build", "id": dz.id, "type": bt, "x": pos.x, "y": pos.y, "yaw": 0.0})
		print("[Test] ordered %s at %s" % [bt, pos])
		var waited := 0.0
		while waited < 80.0:
			await get_tree().create_timer(1.0).timeout
			waited += 1.0
			if not is_inside_tree():
				return
			var done := false
			for pp in puppets.values():
				if pp.team == my_index and pp.type == bt and pp.complete and (b0 == null or pp.id != b0.id or n0 == 0):
					done = true
			if done:
				print("[Test] %s complete after %.0fs (cash %d)" % [bt, waited, pstate.get("cash", 0)])
				built[bt] = true
				break
			if count_own(bt) <= n0 and waited > 6.0:
				print("[Test] WARN %s never placed (%s)" % [bt, unit_prereq_text(bt) if Data.UNITS.has(bt) else building_prereq_text(bt)])
				break
		send({"t": "cheat_cash"})
	# train everything, research everything, once
	for pp in puppets.values():
		if pp.team != my_index or not pp.is_building or not pp.complete:
			continue
		for ut in pp.def.get("produces", []):
			send({"t": "produce", "id": pp.id, "type": ut})
		for uid in pp.def.get("upgrades", []):
			send({"t": "upgrade", "id": pp.id, "uid": uid})
		if pp.def.get("plans", false):
			send({"t": "plan", "id": pp.id, "plan": "bombardment"})
	print("[Test] production queued everywhere")
	# cycle the selection through every own thing while the army builds
	var t := 0.0
	while t < 75.0:
		await get_tree().create_timer(2.5).timeout
		t += 2.5
		if not is_inside_tree():
			return
		var own := []
		for pp in puppets.values():
			if pp.team == my_index and not pp.ghost:
				own.append(pp)
		if not own.is_empty():
			ctl.set_selection([own[randi() % own.size()].id])
		send({"t": "cheat_cash"})
	_report()
	# transports / tunnels: put infantry in the first thing with cargo, then unload
	var carrier: Puppet = null
	var inf := []
	for pp in puppets.values():
		if pp.team != my_index or pp.ghost:
			continue
		if pp.def.has("cargo") and carrier == null and (not pp.is_building or pp.complete):
			carrier = pp
		elif pp.cat == "inf" and pp.def.has("weapons") and not pp.def["weapons"].is_empty():
			inf.append(pp.id)
	if carrier != null and not inf.is_empty():
		send({"t": "load", "ids": inf.slice(0, 4), "tid": carrier.id})
		print("[Test] loading %d infantry into %s" % [mini(4, inf.size()), carrier.type])
		await get_tree().create_timer(25.0).timeout
		print("[Test] cargo of %s: %s" % [carrier.type, str(pstate.get("cargo", {}).get(carrier.id, []))])
		send({"t": "unload", "ids": [carrier.id]})
		await get_tree().create_timer(6.0).timeout
		print("[Test] after unload cargo: %s" % str(pstate.get("cargo", {}).get(carrier.id, [])))
	# powers: buy what we can, fire abilities at the enemy start
	for k in range(3):
		for pid in fd["powers"]:
			send({"t": "buy_power", "pid": pid})
	var en := _enemy_start()
	for pid in fd["strike_powers"]:
		send({"t": "power", "pid": pid, "x": en.x, "y": en.y})
	send({"t": "power", "pid": "emergency_repair", "x": base.x, "y": base.y})
	# send the army at the enemy
	var army := _own_ids(func(p: Puppet) -> bool: return not p.is_building and not p.def.get("builder", false) and int(p.def.get("gatherer", 0)) == 0)
	if not army.is_empty():
		send({"t": "amove", "ids": army, "x": en.x, "y": en.y, "q": false})
		print("[Test] %d units attack-moving to %s" % [army.size(), en])
	await get_tree().create_timer(40.0).timeout
	_report()
	print("[Test] faction %s done" % my_faction)

func _report() -> void:
	var counts := {}
	var enemy := 0
	for p in puppets.values():
		if p.team == my_index:
			counts[p.type] = counts.get(p.type, 0) + 1
		elif p.team >= 0 and not p.ghost:
			enemy += 1
	print("[Test p%d] t=%.0f cash=%d power=%s/%s own=%s enemies_visible=%d" % [my_index, pstate.get("time", 0.0), pstate.get("cash", 0), str(pstate.get("pp", 0)), str(pstate.get("pu", 0)), str(counts), enemy])
	var hps := []
	for p in puppets.values():
		if p.team == my_index and p.is_building:
			hps.append("%s:%.3f" % [p.type, p.hp_frac])
	print("[Test p%d] building hp: %s" % [my_index, " ".join(hps)])
