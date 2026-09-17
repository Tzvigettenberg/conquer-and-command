class_name Icons
extends Node
## Renders unit / building / upgrade / power icons at runtime from the actual
## models (SubViewport snapshots), so the command bar always matches the art.

signal ready_changed

const SIZE := 128

var vp: SubViewport
var cam: Camera3D
var holder: Node3D
var icons: Dictionary = {}       # key -> Texture2D
var queue: Array = []
var busy := false

func _ready() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true   # otherwise the icon models sit in the game world at the map corner
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.85)
	e.ambient_light_energy = 0.9
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 30.0
	vp.add_child(cam)
	cam.current = true
	holder = Node3D.new()
	vp.add_child(holder)
	# everything, up front
	for t in Data.UNITS:
		queue.append(["unit", t])
	for t in Data.BUILDINGS:
		queue.append(["building", t])
	for u in Data.UPGRADES:
		queue.append(["upgrade", u])
	for p in Data.POWERS:
		queue.append(["power", p])
	for k in Data.PLANS:
		queue.append(["plan", k])

func get_icon(key: String) -> Texture2D:
	return icons.get(key)

func _process(_dt: float) -> void:
	if busy or queue.is_empty():
		return
	busy = true
	_render_next()

func _render_next() -> void:
	var item: Array = queue.pop_front()
	var kind: String = item[0]
	var key: String = item[1]
	for c in holder.get_children():
		c.queue_free()
	var model_type := key
	var badge := ""
	match kind:
		"upgrade":
			model_type = _upgrade_model(key)
			badge = "up"
		"power":
			model_type = _power_model(key)
			badge = "star"
		"plan":
			model_type = {"bombardment": "firebase", "hold": "patriot", "search": "pathfinder"}.get(key, "strategy_center")
			badge = "plan"
	var model := Visuals.make_model(model_type, -1)
	holder.add_child(model)
	var aabb := Visuals.model_aabb(model)
	var centre := aabb.get_center()
	var r := maxf(aabb.size.length() * 0.5, 0.5)
	var dir := Vector3(0.75, 0.55, 1.0).normalized()
	if Data.is_building(model_type):
		dir = Vector3(0.6, 0.7, 1.0).normalized()
	cam.position = centre + dir * (r / tan(deg_to_rad(cam.fov * 0.5)) * 1.05)
	cam.look_at(centre, Vector3.UP)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if badge != "":
		_draw_badge(img, badge)
	_draw_frame(img, kind)
	icons[key] = ImageTexture.create_from_image(img)
	busy = false
	if queue.is_empty():
		for c in holder.get_children():
			c.queue_free()
		ready_changed.emit()

func _upgrade_model(uid: String) -> String:
	match uid:
		"control_rods":
			return "power_plant"
		"capture":
			return "ranger"
		"supply_lines":
			return "chinook"
		"tow":
			return "humvee"
		"rocket_pods":
			return "comanche"
		"laser_missiles":
			return "raptor"
		"composite_armor":
			return "crusader"
		"advanced_training":
			return "missile_defender"
		"chain_guns":
			return "gattling_tank"
		"black_napalm":
			return "mig"
		"uranium_shells":
			return "battlemaster"
		"nationalism":
			return "red_guard"
		"subliminal_messaging":
			return "speaker_tower"
		"scorpion_rocket":
			return "scorpion"
		"ap_bullets":
			return "rebel"
		"ap_rockets":
			return "rpg_trooper"
		"junk_repair":
			return "marauder"
		"anthrax_beta":
			return "toxin_tractor"
	return "ranger"

func _power_model(pid: String) -> String:
	match pid:
		"paladin":
			return "paladin"
		"stealth_fighter":
			return "stealth_fighter"
		"pathfinder":
			return "pathfinder"
		"spy_satellite":
			return "command_center"
		"a10":
			return "raptor"
		"emergency_repair":
			return "dozer"
		"paradrop":
			return "chinook"
		"fuel_air_bomb":
			return "aurora"
		"cash_hack":
			return "hacker"
		"artillery_barrage":
			return "inferno_cannon"
		"frenzy":
			return "red_guard"
		"nuke_cannon":
			return "nuke_cannon"
		"carpet_bomb":
			return "mig"
		"rebel_ambush":
			return "rebel"
		"marauder":
			return "marauder"
		"cash_bounty":
			return "black_market"
		"anthrax_bomb":
			return "toxin_tractor"
		"sneak_attack":
			return "tunnel_network"
	return "command_center"

func _draw_badge(img: Image, badge: String) -> void:
	var s := img.get_width()
	var col := Color(0.35, 0.95, 0.4) if badge == "up" else (Color(0.4, 0.75, 1.0) if badge == "plan" else Color(1.0, 0.85, 0.2))
	var cx := s - 26
	var cy := s - 26
	for y in range(-18, 19):
		for x in range(-18, 19):
			var inside := false
			if badge == "up":
				# arrow: triangle head + stem
				inside = (y < 2 and absi(x) <= (y + 16) * 0.75 and y >= -16) or (y >= 2 and y <= 14 and absi(x) <= 5)
			elif badge == "plan":
				# crossed X on a disc
				inside = Vector2(x, y).length() <= 16.0 and (absi(x - y) <= 3 or absi(x + y) <= 3)
			else:
				var ang := atan2(float(y), float(x))
				var rad := Vector2(x, y).length()
				var star := 10.0 + 7.0 * cos(5.0 * ang)
				inside = rad <= star
			if inside:
				var px := cx + x
				var py := cy + y
				if px >= 0 and py >= 0 and px < s and py < s:
					img.set_pixel(px, py, col)

func _draw_frame(img: Image, kind: String) -> void:
	var s := img.get_width()
	var col := Color(0.55, 0.6, 0.7, 0.9)
	if kind == "building":
		col = Color(0.8, 0.7, 0.4, 0.9)
	elif kind == "upgrade":
		col = Color(0.4, 0.9, 0.5, 0.9)
	elif kind == "power":
		col = Color(1.0, 0.8, 0.3, 0.9)
	elif kind == "plan":
		col = Color(0.4, 0.75, 1.0, 0.9)
	for i in range(s):
		for t in range(2):
			img.set_pixel(i, t, col)
			img.set_pixel(i, s - 1 - t, col)
			img.set_pixel(t, i, col)
			img.set_pixel(s - 1 - t, i, col)
