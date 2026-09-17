class_name Audio
extends Node
## Sound effects, unit voices, EVA announcements and music.
## Assets live in res://audio (see audio/*/CREDITS.md). Everything degrades
## silently if a file is missing so the game never depends on audio.

const SFX_DIR := "res://audio/sfx/"
const VOICE_DIR := "res://audio/voice/"
const MUSIC_DIR := "res://audio/music/"
const MAX_3D := 40

static var I: Audio = null

var streams: Dictionary = {}          # path -> AudioStream (or null)
var pool3d: Array[AudioStreamPlayer3D] = []
var ui_player: AudioStreamPlayer
var voice_player: AudioStreamPlayer
var eva_player: AudioStreamPlayer
var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var ambience: AudioStreamPlayer
var eva_queue: Array = []
var eva_cd: Dictionary = {}           # name -> time allowed again
var voice_cd := 0.0
var sfx_cd: Dictionary = {}           # name -> last play time (spam limiter)
var music_list: Array = []
var music_i := 0
var music_fade := 0.0
var music_kind := ""
var listener_pos := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var voice_dirs: Dictionary = {}       # class -> {kind: count}

const WEAPON_SFX := {
	"ranger_rifle": "rifle_burst", "humvee_gun": "machinegun", "comanche_cannon": "machinegun",
	"crusader_gun": "tank_cannon", "paladin_gun": "tank_cannon", "md_missile": "missile_launch", "humvee_tow": "missile_launch",
	"patriot": "missile_launch", "raptor_missile": "missile_launch", "stealth_missile": "missile_launch", "comanche_rockets": "rocket_pod",
	"tomahawk": "missile_launch", "firebase_gun": "artillery_fire", "avenger_laser": "laser_zap", "pathfinder_rifle": "sniper_shot",
	"burton_rifle": "sniper_shot", "aurora_bomb": "bomb_whistle", "a10_gun": "gau8", "a10_missile": "missile_launch", "sc_cannon": "artillery_fire", "fab": "explosion_large", "particle": "superweapon_fire", "pd_laser": "laser_zap",
}
const IMPACT_SFX := {"bullet": "ricochet", "shell": "explosion_small", "missile": "explosion_small", "cruise": "explosion_medium", "bomb": "explosion_medium", "beam": ""}
const VOICE_CLASS := {"crusader": "tank", "paladin": "tank"}

func _ready() -> void:
	I = self
	rng.randomize()
	_ensure_bus("SFX")
	_ensure_bus("Voice")
	_ensure_bus("Music")
	ui_player = _player2d("SFX")
	voice_player = _player2d("Voice")
	eva_player = _player2d("Voice")
	music_a = _player2d("Music")
	music_b = _player2d("Music")
	ambience = _player2d("SFX")
	ambience.volume_db = -14.0
	eva_player.finished.connect(_eva_next)
	music_a.finished.connect(_music_next)
	music_b.finished.connect(_music_next)
	_index_voices()

func _ensure_bus(name: String) -> void:
	if AudioServer.get_bus_index(name) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, "Master")

func _player2d(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

func set_volumes(master: float, sfx: float, voice: float, music: float) -> void:
	for pair in [["Master", master], ["SFX", sfx], ["Voice", voice], ["Music", music]]:
		var i := AudioServer.get_bus_index(pair[0])
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(clampf(pair[1], 0.0001, 1.0)))

func _stream(path: String) -> AudioStream:
	if streams.has(path):
		return streams[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	streams[path] = s
	return s

func _index_voices() -> void:
	var dir := DirAccess.open(VOICE_DIR)
	if dir == null:
		return
	for cls in dir.get_directories():
		var d := DirAccess.open(VOICE_DIR + cls)
		if d == null:
			continue
		var kinds := {}
		for f in d.get_files():
			if f.ends_with(".ogg") or f.ends_with(".ogg.import"):
				var base := f.replace(".import", "").replace(".ogg", "")
				var us := base.rfind("_")
				if us > 0 and base.substr(us + 1).is_valid_int():
					var kind := base.substr(0, us)
					kinds[kind] = maxi(kinds.get(kind, 0), int(base.substr(us + 1)) + 1)
		voice_dirs[cls] = kinds

# ---------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------
func ui(name: String, vol_db := 0.0) -> void:
	var s := _stream(SFX_DIR + name + ".ogg")
	if s == null:
		return
	ui_player.stream = s
	ui_player.volume_db = vol_db
	ui_player.pitch_scale = 1.0
	ui_player.play()

## Positional one-shot. Spam-limited per name (min interval) so 30 rangers don't stack 30 bursts.
func sfx(name: String, pos: Vector3, vol_db := 0.0, pitch_var := 0.08, min_interval := 0.04) -> void:
	if name == "":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(sfx_cd.get(name, -10.0)) < min_interval:
		return
	sfx_cd[name] = now
	var s := _stream(SFX_DIR + name + ".ogg")
	if s == null:
		return
	var p := _get3d()
	if p == null:
		return
	p.stream = s
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = 1.0 + rng.randf_range(-pitch_var, pitch_var)
	p.play()

func _get3d() -> AudioStreamPlayer3D:
	for p in pool3d:
		if not p.playing:
			return p
	if pool3d.size() < MAX_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 18.0
		p.max_distance = 300.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 1.2
		add_child(p)
		pool3d.append(p)
		return p
	# steal the farthest one
	var best: AudioStreamPlayer3D = null
	var bd := -1.0
	for p in pool3d:
		var d := p.global_position.distance_to(listener_pos)
		if d > bd:
			bd = d
			best = p
	return best

## Looping positional player owned by the caller (engines, rotors, construction).
func make_loop(name: String, vol_db := -6.0) -> AudioStreamPlayer3D:
	var s := _stream(SFX_DIR + name + ".ogg")
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.stream = s
	p.unit_size = 10.0
	p.max_distance = 140.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.volume_db = vol_db
	p.autoplay = true
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	return p

func weapon(wid: String, pos: Vector3) -> void:
	var name: String = WEAPON_SFX.get(wid, "")
	var vol := 0.0
	match name:
		"rifle_burst", "machinegun":
			vol = -6.0
		"tank_cannon", "artillery_fire":
			vol = 2.0
		"superweapon_fire":
			vol = 6.0
	sfx(name, pos, vol, 0.1, 0.06 if name != "machinegun" else 0.15)

func impact(style: String, pos: Vector3) -> void:
	var name: String = IMPACT_SFX.get(style, "")
	if name == "":
		return
	if name == "ricochet" and rng.randf() > 0.35:
		return
	sfx(name, pos, -4.0 if name == "ricochet" else 0.0, 0.12, 0.08)

func death(type: String, pos: Vector3) -> void:
	var def := Data.def(type)
	if Data.is_building(type):
		sfx("explosion_large", pos, 4.0, 0.05, 0.2)
		sfx("building_collapse", pos, 2.0, 0.05, 0.2)
	elif def.get("cat", "") == "inf":
		sfx("scream" if rng.randf() < 0.5 else "grunt", pos, -2.0, 0.15, 0.1)
	else:
		sfx("explosion_medium", pos, 2.0, 0.1, 0.1)

# ---------------------------------------------------------------------------
# Voices
# ---------------------------------------------------------------------------
func voice(unit_type: String, kind: String, force := false) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not force and now < voice_cd:
		return
	var cls: String = VOICE_CLASS.get(unit_type, unit_type)
	var kinds: Dictionary = voice_dirs.get(cls, {})
	if not kinds.has(kind):
		return
	var n := int(kinds[kind])
	var path := "%s%s/%s_%d.ogg" % [VOICE_DIR, cls, kind, rng.randi() % n]
	var s := _stream(path)
	if s == null:
		return
	voice_player.stream = s
	voice_player.play()
	voice_cd = now + 0.7

func eva(name: String, cooldown := 4.0) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(eva_cd.get(name, -100.0)):
		return
	eva_cd[name] = now + cooldown
	if eva_queue.has(name) or eva_queue.size() > 3:
		return
	eva_queue.append(name)
	if not eva_player.playing:
		_eva_next()

func _eva_next() -> void:
	if eva_queue.is_empty():
		return
	var name: String = eva_queue.pop_front()
	var s := _stream(VOICE_DIR + "eva/" + name + ".ogg")
	if s == null:
		_eva_next()
		return
	eva_player.stream = s
	eva_player.play()

## Map a server text message to an EVA line (server messages are plain strings).
func eva_for_message(text: String) -> void:
	var t := text.to_lower()
	if t.begins_with("unit lost"):
		eva("unit_lost", 8.0)
	elif "insufficient funds" in t:
		eva("insufficient_funds", 3.0)
	elif "cannot build" in t:
		eva("cannot_build", 3.0)
	elif "low power" in t:
		eva("low_power", 15.0)
	elif "captured by the enemy" in t:
		eva("structure_captured_by_enemy", 2.0)
	elif "captured" in t:
		eva("building_captured", 2.0)
	elif "particle cannon ready" in t:
		eva("superweapon_ready", 2.0)
	elif "enemy particle cannon fired" in t:
		eva("enemy_superweapon_launch", 2.0)
	elif "particle cannon fired" in t:
		eva("superweapon_launch", 2.0)
	elif "upgrade complete" in t:
		eva("upgrade_complete", 2.0)
	elif t.ends_with(" complete"):
		eva("construction_complete", 2.0)
	elif t.ends_with(" ready"):
		eva("unit_ready", 2.5)
	elif t.ends_with(" lost"):
		eva("structure_lost", 6.0)
	elif "promoted" in t:
		eva("promotion", 2.0)
	elif "acquired" in t:
		eva("new_power", 2.0)
	elif "airfield full" in t:
		eva("airfield_full", 3.0)
	elif "capture building upgrade" in t:
		eva("capture_requires", 3.0)
	elif "requires" in t or "limit reached" in t:
		eva("requires", 3.0)
	elif "fuel air bomb inbound" in t:
		eva("enemy_fuel_air_bomb", 2.0)
	elif "under attack" in t:
		if "base" in t:
			eva("base_under_attack", 12.0)
		else:
			eva("units_under_attack", 12.0)
	elif "disconnected" in t:
		eva("player_disconnected", 2.0)
	elif "all structures lost" in t:
		eva("defeat", 100.0)

# ---------------------------------------------------------------------------
# Music / ambience
# ---------------------------------------------------------------------------
func play_music(kind: String) -> void:
	if kind == music_kind:
		return
	music_kind = kind
	music_list.clear()
	var dir := DirAccess.open(MUSIC_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with(kind + "_") and (f.ends_with(".ogg") or f.ends_with(".ogg.import")):
			var p := MUSIC_DIR + f.replace(".import", "")
			if not music_list.has(p):
				music_list.append(p)
	music_list.shuffle()
	music_i = 0
	music_a.stop()
	music_b.stop()
	_music_next()

func _music_next() -> void:
	if music_list.is_empty():
		return
	var path: String = music_list[music_i % music_list.size()]
	music_i += 1
	var s := _stream(path)
	if s == null:
		return
	var p := music_a if not music_a.playing else music_b
	p.stream = s
	p.volume_db = -9.0
	p.play()

func start_ambience() -> void:
	var s := _stream(SFX_DIR + "wind_loop.ogg")
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	ambience.stream = s
	ambience.play()

func stop_all() -> void:
	music_a.stop()
	music_b.stop()
	ambience.stop()
	eva_queue.clear()
	music_kind = ""
