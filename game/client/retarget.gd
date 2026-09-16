class_name AnimRetarget
extends RefCounted
## Runtime Mixamo -> Synty retargeter (sampled global-space transfer), trimmed
## from the Incremental PvE project. Builds a full-body AnimationLibrary once
## and caches it; RTS infantry only need idle / run / fire / death.

const SAMPLE_FPS := 20.0

const CLIPS := {
	"idle": "res://mixamo/rifle_idle.fbx",
	"run": "res://mixamo/rifle_run.fbx",
	"fire": "res://mixamo/fire.fbx",
	"death": "res://mixamo/death.fbx",
}
const LOOPING := ["idle", "run"]

const BONE_MAP := {
	"hips": "Hips", "spine": "Spine_01", "spine1": "Spine_02", "spine2": "Spine_03", "neck": "Neck", "head": "Head",
	"leftshoulder": "Clavicle_L", "leftarm": "Shoulder_L", "leftforearm": "Elbow_L", "lefthand": "Hand_L",
	"rightshoulder": "Clavicle_R", "rightarm": "Shoulder_R", "rightforearm": "Elbow_R", "righthand": "Hand_R",
	"leftupleg": "UpperLeg_L", "leftleg": "LowerLeg_L", "leftfoot": "Ankle_L", "lefttoebase": "Ball_L",
	"rightupleg": "UpperLeg_R", "rightleg": "LowerLeg_R", "rightfoot": "Ankle_R", "righttoebase": "Ball_R",
}

static var _cached: Dictionary = {}
static var _tried := false

static func _normalize(bone_name: String) -> String:
	var n := bone_name.to_lower()
	n = n.replace("mixamorig:", "").replace("mixamorig_", "").replace("mixamorig", "")
	return n.replace("_", "").replace(":", "").replace(" ", "")

static func build_libraries(target: Skeleton3D) -> Dictionary:
	if not _cached.is_empty() or _tried:
		return _cached
	_tried = true
	var full := AnimationLibrary.new()
	for clip_name in CLIPS:
		var path: String = CLIPS[clip_name]
		if not ResourceLoader.exists(path):
			continue
		var anim := _retarget_clip(path, target)
		if anim == null:
			push_warning("[AnimRetarget] failed clip: " + str(clip_name))
			continue
		if clip_name in LOOPING:
			anim.loop_mode = Animation.LOOP_LINEAR
		full.add_animation(clip_name, anim)
	if full.get_animation_list().is_empty():
		return {}
	_cached = {"full": full}
	print("[AnimRetarget] built %d clips" % full.get_animation_list().size())
	return _cached

static func _bone_order(skel: Skeleton3D) -> Array:
	var order := []
	var placed := {}
	var remaining := range(skel.get_bone_count())
	while remaining.size() > 0:
		var next := []
		for i in remaining:
			var p := skel.get_bone_parent(i)
			if p == -1 or placed.has(p):
				order.append(i)
				placed[i] = true
			else:
				next.append(i)
		if next.size() == remaining.size():
			break
		remaining = next
	return order

static func _retarget_clip(path: String, target: Skeleton3D) -> Animation:
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var scene := packed.instantiate()
	var tree := target.get_tree()
	if tree == null or tree.current_scene == null:
		scene.queue_free()
		return null
	tree.current_scene.add_child(scene)
	if scene is Node3D:
		scene.position = Vector3(0, -500, 0)
		scene.visible = false
	var skels := scene.find_children("*", "Skeleton3D", true, false)
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if skels.is_empty() or players.is_empty():
		scene.queue_free()
		return null
	var src: Skeleton3D = skels.front()
	var src_player: AnimationPlayer = players.front()
	var anim_names := src_player.get_animation_list()
	if anim_names.is_empty():
		scene.queue_free()
		return null
	var pick := anim_names[0]
	for an in anim_names:
		if "mixamo" in str(an).to_lower():
			pick = an
			break
	var src_anim: Animation = src_player.get_animation(pick)
	var length := src_anim.length
	var src_by_norm := {}
	for i in range(src.get_bone_count()):
		src_by_norm[_normalize(src.get_bone_name(i))] = i
	var pair_for_tgt := {}
	for norm_name in BONE_MAP:
		var tgt_name: String = BONE_MAP[norm_name]
		var t_i := target.find_bone(tgt_name)
		if t_i >= 0 and src_by_norm.has(norm_name):
			pair_for_tgt[t_i] = src_by_norm[norm_name]
	if pair_for_tgt.is_empty():
		scene.queue_free()
		return null
	var src_hips: int = src_by_norm.get("hips", -1)
	var tgt_hips := target.find_bone("Hips")
	var pos_scale := 1.0
	if src_hips >= 0 and tgt_hips >= 0:
		var sh := src.get_bone_global_rest(src_hips).origin.y
		var th := target.get_bone_global_rest(tgt_hips).origin.y
		if sh > 0.01:
			pos_scale = th / sh
	var order := _bone_order(target)
	var out := Animation.new()
	out.length = length
	var rot_track := {}
	for t_i in pair_for_tgt:
		var track_i := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(track_i, NodePath(":" + target.get_bone_name(t_i)))
		rot_track[t_i] = track_i
	var pos_track := {}
	for t_i in pair_for_tgt:
		var parent := target.get_bone_parent(t_i)
		if parent < 0 or not pair_for_tgt.has(parent):
			var track_i := out.add_track(Animation.TYPE_POSITION_3D)
			out.track_set_path(track_i, NodePath(":" + target.get_bone_name(t_i)))
			pos_track[t_i] = track_i
	var frame_count := int(ceil(length * SAMPLE_FPS)) + 1
	for f in range(frame_count):
		var t := minf(f / SAMPLE_FPS, length)
		src_player.play(pick)
		src_player.seek(t, true)
		var g_xform := {}
		for idx in order:
			var parent := target.get_bone_parent(idx)
			var parent_t: Transform3D = g_xform.get(parent, Transform3D.IDENTITY)
			var xf: Transform3D
			if pair_for_tgt.has(idx):
				var s_i: int = pair_for_tgt[idx]
				var delta: Basis = src.get_bone_global_pose(s_i).basis * src.get_bone_global_rest(s_i).basis.inverse()
				var b: Basis = delta * target.get_bone_global_rest(idx).basis
				var origin: Vector3
				if pos_track.has(idx):
					var src_delta: Vector3 = (src.get_bone_global_pose(s_i).origin - src.get_bone_global_rest(s_i).origin) * pos_scale
					origin = target.get_bone_global_rest(idx).origin + Vector3(0, src_delta.y, 0)
					var local_pos: Vector3 = parent_t.affine_inverse() * origin
					out.position_track_insert_key(pos_track[idx], t, local_pos)
				else:
					origin = parent_t * target.get_bone_rest(idx).origin
				xf = Transform3D(b, origin)
				var local_q := (parent_t.basis.inverse() * b).get_rotation_quaternion().normalized()
				out.rotation_track_insert_key(rot_track[idx], t, local_q)
			else:
				xf = parent_t * target.get_bone_rest(idx)
			g_xform[idx] = xf
	scene.queue_free()
	return out
