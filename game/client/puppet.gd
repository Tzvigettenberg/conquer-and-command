class_name Puppet
extends Node3D
## Client-side replica of one sim entity. Interpolates between snapshots and
## drives the visual (model, turret, animation, selection ring, construction).

const INTERP_DELAY := 0.12

var id := 0
var type := ""
var def: Dictionary = {}
var team := -1
var is_building := false
var cat := ""
var radius := 1.0

var t0 := 0.0
var t1 := 0.0
var p0 := Vector3.ZERO
var p1 := Vector3.ZERO
var yaw0 := 0.0
var yaw1 := 0.0
var tyaw0 := 0.0
var tyaw1 := 0.0
var cur_pos := Vector3.ZERO
var cur_yaw := 0.0
var hp_frac := 1.0
var flags := 0
var aux := 0
var level := 0
var complete := true
var last_update := 0.0
var selected := false
var hovered := false
var boxes := 0
var ghost := false

var model: Node3D
var turret: Node3D = null
var sel_ring: MeshInstance3D
var team_ring: MeshInstance3D
var pad: MeshInstance3D = null
var anim: AnimationPlayer = null
var anim_state := ""
var rally_marker: Node3D = null
var stealth_alpha := 1.0

func setup(_id: int, _type: String, _team: int, pos: Vector2, alt: float, yaw: float, extra: Dictionary, mine: bool) -> void:
	id = _id
	type = _type
	def = Data.def(_type)
	team = _team
	is_building = Data.is_building(_type)
	cat = def.get("cat", "bld")
	complete = extra.get("complete", true)
	boxes = extra.get("boxes", 0)
	if is_building:
		var fp: Vector2 = Data.footprint_size(_type)
		radius = maxf(fp.x, fp.y) * 0.5
	else:
		radius = float(def.get("radius", 1.0))
	cur_pos = Vector3(pos.x, alt, pos.y)
	p0 = cur_pos
	p1 = cur_pos
	yaw0 = yaw
	yaw1 = yaw
	cur_yaw = yaw
	position = cur_pos
	rotation.y = yaw
	_build_visual(mine)

func _build_visual(mine: bool) -> void:
	model = Visuals.make_model(type, team)
	add_child(model)
	if model.has_meta("turret"):
		turret = model.get_meta("turret")
	if is_building:
		var fp: Vector2 = Data.footprint_size(type)
		var col := Color(0.32, 0.31, 0.3)
		if def.get("neutral", false):
			col = Color(0.4, 0.38, 0.33)
		pad = Visuals.box(Vector3(fp.x, 0.12, fp.y), col)
		pad.position.y = 0.06
		add_child(pad)
		if def.get("runway", false):
			var rw := Visuals.box(Vector3(fp.x * 0.9, 0.05, 5.0), Color(0.2, 0.2, 0.2))
			rw.position = Vector3(0, 0.14, -5.0)
			add_child(rw)
			for i in range(4):
				var m := Visuals.box(Vector3(4.0, 0.02, 4.0), Color(0.5, 0.5, 0.1, 0.6), true)
				m.position = Vector3(-7.5 + i * 5.0, 0.18, -5.0)
				add_child(m)
		if team >= 0:
			var flag := Visuals.box(Vector3(0.15, 3.0, 0.15), Color(0.3, 0.3, 0.3))
			flag.position = Vector3(fp.x * 0.5 - 0.6, 1.5, fp.y * 0.5 - 0.6)
			add_child(flag)
			var banner := Visuals.box(Vector3(1.2, 0.7, 0.05), Data.TEAM_COLORS[team], true)
			banner.position = Vector3(fp.x * 0.5 - 0.0, 2.6, fp.y * 0.5 - 0.6)
			add_child(banner)
	else:
		team_ring = Visuals.disc(radius * 0.9, Color(Data.TEAM_COLORS[team], 0.55) if team >= 0 else Color(0.5, 0.5, 0.5, 0.5))
		add_child(team_ring)
	sel_ring = Visuals.ring(radius * (1.15 if not is_building else 0.75), Color(0.3, 1.0, 0.3) if mine else Color(1.0, 0.9, 0.3))
	sel_ring.visible = false
	add_child(sel_ring)
	if cat == "inf":
		_setup_anim()
	_apply_construction()

func _setup_anim() -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel: Skeleton3D = skels[0]
	for p in model.find_children("*", "AnimationPlayer", true, false):
		p.stop()
		p.active = false
	if not is_inside_tree():
		return
	var libs := AnimRetarget.build_libraries(skel)
	if libs.is_empty() or libs["full"].get_animation_list().is_empty():
		return
	anim = AnimationPlayer.new()
	skel.add_child(anim)
	anim.root_node = NodePath("..")
	anim.add_animation_library("f", libs["full"])
	_play("idle")

func _play(clip: String, blend := 0.15) -> void:
	if anim == null or anim_state == clip:
		return
	if not anim.has_animation("f/" + clip):
		return
	anim.play("f/" + clip, blend)
	anim_state = clip

func apply_state(pos: Vector2, alt: float, yaw: float, tyaw: float, hpf: float, fl: int, ax: int, now: float) -> void:
	p0 = p1
	yaw0 = yaw1
	tyaw0 = tyaw1
	t0 = t1
	p1 = Vector3(pos.x, alt, pos.y)
	yaw1 = yaw
	tyaw1 = tyaw
	t1 = now
	if t0 == 0.0:
		t0 = now - 0.1
		p0 = p1
		yaw0 = yaw1
		tyaw0 = tyaw1
		cur_pos = p1
		cur_yaw = yaw1
	hp_frac = hpf
	flags = fl
	aux = ax
	level = (fl >> 6) & 3
	var was_complete := complete
	complete = (fl & 8) == 0 if is_building else true
	if is_building and was_complete != complete:
		_apply_construction()
	last_update = now
	ghost = false

func _apply_construction() -> void:
	if not is_building:
		return
	if complete:
		model.scale = Vector3.ONE
		model.position.y = 0.0
	else:
		var f := clampf(aux / 100.0, 0.02, 1.0)
		model.scale = Vector3(1, f, 1)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var rt := now - INTERP_DELAY
	var span := t1 - t0
	if span > 0.0001 and t1 > 0.0:
		var a := clampf((rt - t0) / span, 0.0, 1.25)
		cur_pos = p0.lerp(p1, a)
		cur_yaw = lerp_angle(yaw0, yaw1, minf(a, 1.0))
		if turret != null:
			turret.rotation.y = lerp_angle(tyaw0, tyaw1, minf(a, 1.0)) - cur_yaw
	position = cur_pos
	rotation.y = cur_yaw
	if is_building and not complete:
		var f := clampf(aux / 100.0, 0.02, 1.0)
		model.scale = Vector3(1, f, 1)
	if is_building and (flags & 16) != 0 and complete:
		# unpowered: dim pulse
		var k := 0.5 + 0.5 * sin(now * 6.0)
		if pad:
			pad.material_override = Visuals.flat_mat(Color(0.4, 0.2 + 0.2 * k, 0.1), false)
	elif pad and is_building and team >= 0 and complete:
		pad.material_override = Visuals.flat_mat(Color(0.32, 0.31, 0.3), false)
	if anim != null:
		if (flags & 2) != 0:
			_play("fire", 0.05)
		elif (flags & 1) != 0:
			_play("run")
		else:
			_play("idle")
	# own stealthed units render translucent-ish
	var want_alpha := 0.45 if (flags & 4) != 0 else 1.0
	if want_alpha != stealth_alpha:
		stealth_alpha = want_alpha
		model.visible = true
		if team_ring:
			team_ring.visible = want_alpha >= 1.0
	sel_ring.visible = selected or hovered
	if cat == "air" and team_ring:
		team_ring.position.y = -cur_pos.y + 0.03

func is_stale(now: float) -> bool:
	return not is_building and now - last_update > 0.7

func detach_model() -> Node3D:
	if model.get_parent() == self:
		remove_child(model)
	return model
