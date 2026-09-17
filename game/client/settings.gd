class_name Settings
extends RefCounted
## Persistent user settings (user://settings.cfg): volumes, edge scrolling.

const PATH := "user://settings.cfg"
static var cache: Dictionary = {}

static func load_cfg() -> Dictionary:
	if not cache.is_empty():
		return cache
	var cf := ConfigFile.new()
	cache = {"master": 1.0, "sfx": 1.0, "voice": 1.0, "music": 0.8, "edge_scroll": true}
	if cf.load(PATH) == OK:
		for k in cache:
			cache[k] = cf.get_value("settings", k, cache[k])
	return cache

static func set_value(key: String, v) -> void:
	load_cfg()
	cache[key] = v
	var cf := ConfigFile.new()
	for k in cache:
		cf.set_value("settings", k, cache[k])
	cf.save(PATH)

static func apply() -> void:
	var c := load_cfg()
	if Audio.I != null:
		Audio.I.set_volumes(float(c["master"]), float(c["sfx"]), float(c["voice"]), float(c["music"]))
