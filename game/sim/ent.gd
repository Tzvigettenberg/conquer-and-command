class_name Ent
extends RefCounted
## One simulated object (unit or building). Server-side only.

var id: int
var type: String
var def: Dictionary
var owner: int = -1            # player index, -1 = neutral
var is_building := false
var pos := Vector2.ZERO        # x, z in metres
var alt := 0.0                 # height above ground (air units)
var yaw := 0.0                 # radians, 0 = +Z
var turret_yaw := 0.0
var hp := 1.0
var max_hp := 1.0
var radius := 1.0
var vision := 20.0
var speed := 0.0
var alive := true
var dying := false

# ---- orders ----
var state := "idle"            # idle move attack amove guard gather build repair capture return land
var target_id := -1
var goal := Vector2.ZERO
var path := PackedVector2Array()
var path_i := 0
var repath_t := 0.0
var queue: Array = []          # queued commands (shift-click)
var guard_pos := Vector2.ZERO
var stuck_t := 0.0
var last_pos := Vector2.ZERO

# ---- combat ----
var cds: Array[float] = []     # per weapon cooldown remaining
var clip: Array[int] = []      # per weapon shots left in clip
var reload_t: Array[float] = []
var xp := 0.0
var level := 0
var last_fire_t := -100.0
var stealth := false           # def stealth flag
var revealed_until := -1.0     # stealth broken until this sim time
var detected := false          # stealth detected this tick
var kills := 0

# ---- buildings ----
var complete := true
var progress := 0.0            # construction 0..1 (site)
var builder_id := -1
var cells: Array[Vector2i] = []
var prod: Array = []           # [{type, t, total}] production queue
var research: Array = []       # [{id, t, total}]
var rally := Vector2.ZERO
var has_rally := false
var powered := true
var sw_t := 0.0                # superweapon charge timer (seconds elapsed)
var sw_ready := false
var income_t := 0.0
var boxes := 0                 # supply dock contents
var capture_by := -1           # player capturing
var capture_t := 0.0
var upg_done: Dictionary = {}  # per-building upgrades (control rods)
var pads: Array = []           # airfield: entity ids parked
var sold := false

# ---- gatherer / jets ----
var carry := 0                 # boxes carried
var dock_id := -1
var center_id := -1
var home_id := -1              # jet home airfield
var landed := false
var ammo_empty := false

func setup(_id: int, _type: String, _owner: int, _pos: Vector2) -> void:
	id = _id
	type = _type
	def = Data.def(_type)
	owner = _owner
	pos = _pos
	last_pos = _pos
	is_building = Data.is_building(_type)
	max_hp = float(def.get("hp", 100.0))
	hp = max_hp
	speed = float(def.get("speed", 0.0))
	vision = float(def.get("vision", 20.0))
	stealth = bool(def.get("stealth", false))
	if is_building:
		var fp: Vector2 = Vector2(def["fp"]) * 2.0
		radius = maxf(fp.x, fp.y) * 0.5
		boxes = int(def.get("boxes", 0))
	else:
		radius = float(def.get("radius", 1.0))
	var ws: Array = def.get("weapons", [])
	for w in ws:
		cds.append(0.0)
		var wd: Dictionary = Data.WEAPONS[w]
		clip.append(int(wd.get("clip", 0)))
		reload_t.append(0.0)

func is_air() -> bool:
	return def.get("cat", "") == "air"

func is_jet() -> bool:
	return bool(def.get("jet", false))

func cat() -> String:
	return def.get("cat", "bld")

func weapon_ids() -> Array:
	return def.get("weapons", [])

func has_weapons() -> bool:
	return not weapon_ids().is_empty()

func can_move() -> bool:
	return not is_building and speed > 0.0

func hp_frac() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)

func dist_to(p: Vector2) -> float:
	return pos.distance_to(p)

func vet_dmg() -> float:
	return Data.VET_DMG[level]

func clear_orders() -> void:
	state = "idle"
	target_id = -1
	path = PackedVector2Array()
	path_i = 0
	queue.clear()

# ---- misc runtime ----
var resume: Dictionary = {}    # order to resume after an interrupt (attack-move)
var timer := 0.0               # generic per-state timer (loading boxes, etc.)
var acquire_t := 0.0           # throttle for target scans
var attacked_t := -100.0       # last time the owner was notified about this entity
