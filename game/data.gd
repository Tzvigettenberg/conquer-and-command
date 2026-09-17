extends Node
## Static game data. Numbers are lifted from the Zero Hour INI files
## (Weapon.ini / Armor.ini / Locomotor.ini / FactionBuilding.ini / America*.ini)
## and converted to metres with SCALE = 0.2 (1 Generals world unit = 0.2 m).
## Damage, HP, cost and build times are unchanged.

const SCALE := 0.2
const STARTING_CASH := 10000
const BOX_VALUE := 75            # ValuePerSupplyBox
const REFUND := 0.5              # SellPercentage / RefundPercent
const LOW_POWER_SPEED := 0.5     # production speed while under-powered
const VET_XP := [100, 150, 300]  # ExperienceRequired thresholds (veteran / elite / heroic)
const VET_DMG := [1.0, 1.1, 1.25, 1.5]
const VET_HP := [1.0, 1.2, 1.4, 1.6]
const RANK_XP := [0, 1000, 2500, 5000, 9000]   # player xp needed for rank 1..5
const MAX_QUEUE := 9

## Strategy Center battle plans (Zero Hour): one active plan per player; switching takes PLAN_SWITCH s.
const PLAN_SWITCH := 12.0
const PLANS := {
	"bombardment": {"name": "Bombardment", "desc": "Ground units deal 20% more damage. The Strategy Center arms its artillery cannon.", "icon": "plan_bombardment"},
	"hold": {"name": "Hold the Line", "desc": "Ground units take 10% less damage. The Strategy Center is reinforced (x2 armour).", "icon": "plan_hold"},
	"search": {"name": "Search and Destroy", "desc": "Ground units get 20% more range and vision, and detect stealth.", "icon": "plan_search"},
}

const PREFAB := "res://Assets/Synty/PolygonMilitary/Prefabs/"

# ---------------------------------------------------------------------------
# Armor: multiplier applied per damage type (Armor.ini). Missing = 100%.
# ---------------------------------------------------------------------------
const ARMOR := {
	"HumanArmor": {"CRUSH": 2.0, "ARMOR_PIERCING": 0.1, "INFANTRY_MISSILE": 0.1, "FLAME": 1.5,
		"PARTICLE_BEAM": 1.5, "SNIPER": 2.0, "LASER": 0.5, "JET_MISSILES": 0.5, "AURORA_BOMB": 1.0},
	"TankArmor": {"CRUSH": 0.5, "SMALL_ARMS": 0.25, "GATTLING": 0.1, "COMANCHE_VULCAN": 0.25, "FLAME": 0.25,
		"SNIPER": 0.0, "LASER": 0.0, "PARTICLE_BEAM": 1.0, "AA": 0.0},
	"HumveeArmor": {"JET_MISSILES": 0.3, "CRUSH": 0.5, "SMALL_ARMS": 0.5, "GATTLING": 0.5, "COMANCHE_VULCAN": 0.5,
		"INFANTRY_MISSILE": 0.5, "SNIPER": 0.0, "LASER": 0.0, "FLAME": 0.5, "AA": 0.0},
	"DozerArmor": {"CRUSH": 0.5, "SMALL_ARMS": 0.25, "GATTLING": 0.1, "COMANCHE_VULCAN": 0.25, "FLAME": 0.25,
		"SNIPER": 0.0, "LASER": 0.0, "AA": 0.0},
	"AvengerArmor": {"JET_MISSILES": 0.23, "CRUSH": 0.5, "SMALL_ARMS": 0.5, "GATTLING": 0.5, "COMANCHE_VULCAN": 0.5,
		"INFANTRY_MISSILE": 0.5, "SNIPER": 0.0, "LASER": 0.0, "AA": 0.0},
	"StructureArmor": {"SMALL_ARMS": 0.5, "GATTLING": 0.1, "COMANCHE_VULCAN": 0.5, "SNIPER": 0.0, "LASER": 0.0,
		"INFANTRY_MISSILE": 0.5, "PARTICLE_BEAM": 2.0, "AURORA_BOMB": 2.5, "FLAME": 0.5, "CRUSH": 0.0, "AA": 0.0},
	"StructureArmorTough": {"SMALL_ARMS": 0.5, "GATTLING": 0.1, "COMANCHE_VULCAN": 0.5, "SNIPER": 0.0, "LASER": 0.0,
		"INFANTRY_MISSILE": 0.5, "PARTICLE_BEAM": 0.25, "AURORA_BOMB": 2.5, "FLAME": 0.5, "EXPLOSION": 0.8, "CRUSH": 0.0, "AA": 0.0},
	"BaseDefenseArmor": {"SMALL_ARMS": 0.5, "GATTLING": 0.25, "COMANCHE_VULCAN": 0.5, "SNIPER": 0.0, "LASER": 0.0,
		"INFANTRY_MISSILE": 0.25, "PARTICLE_BEAM": 2.0, "AURORA_BOMB": 2.0, "JET_MISSILES": 0.25, "FLAME": 0.5, "CRUSH": 0.0, "AA": 0.0},
	"FireBaseArmor": {"SMALL_ARMS": 0.5, "GATTLING": 0.3, "COMANCHE_VULCAN": 0.5, "SNIPER": 1.0, "LASER": 0.0,
		"INFANTRY_MISSILE": 0.25, "PARTICLE_BEAM": 2.0, "AURORA_BOMB": 2.0, "JET_MISSILES": 0.4, "FLAME": 0.5, "CRUSH": 0.0, "AA": 0.0},
	"AirplaneArmor": {"SMALL_ARMS": 1.2, "GATTLING": 1.2, "INFANTRY_MISSILE": 1.2, "LASER": 0.0, "JET_MISSILES": 0.25,
		"SNIPER": 0.0, "CRUSH": 0.0, "ARMOR_PIERCING": 0.5, "AA": 1.0},
	"ComancheArmor": {"SMALL_ARMS": 1.2, "GATTLING": 1.2, "EXPLOSION": 1.3, "INFANTRY_MISSILE": 1.2, "LASER": 0.0,
		"SNIPER": 0.0, "CRUSH": 0.0, "ARMOR_PIERCING": 0.5, "AA": 1.0},
	"ChinookArmor": {"DEFAULT": 0.5, "INFANTRY_MISSILE": 0.25, "SNIPER": 0.0, "CRUSH": 0.0, "AA": 1.0},
	"InvulnerableArmor": {"DEFAULT": 0.0},
}

# ---------------------------------------------------------------------------
# Weapons. range/min_range in metres, cd = seconds between shots, speed = projectile m/s (0 = hitscan)
# aa/ag = can target airborne / ground. style drives client FX.
# ---------------------------------------------------------------------------
const WEAPONS := {
	"ranger_rifle": {"dmg": 5.0, "type": "SMALL_ARMS", "range": 20.0, "cd": 0.1, "clip": 3, "reload": 0.7, "speed": 0.0, "aa": false, "ag": true, "style": "bullet"},
	"md_missile": {"dmg": 40.0, "type": "INFANTRY_MISSILE", "range": 35.0, "cd": 1.0, "speed": 120.0, "radius": 1.5, "dmg2": 12.0, "radius2": 4.0, "aa": true, "ag": true, "style": "missile"},
	"pathfinder_rifle": {"dmg": 100.0, "type": "SNIPER", "range": 60.0, "cd": 2.0, "speed": 0.0, "aa": false, "ag": true, "style": "bullet"},
	"burton_rifle": {"dmg": 100.0, "type": "SNIPER", "range": 50.0, "cd": 1.5, "speed": 0.0, "aa": false, "ag": true, "style": "bullet"},
	"humvee_gun": {"dmg": 10.0, "type": "COMANCHE_VULCAN", "range": 30.0, "cd": 0.2, "speed": 0.0, "aa": false, "ag": true, "style": "bullet"},
	"humvee_tow": {"dmg": 40.0, "type": "INFANTRY_MISSILE", "range": 35.0, "cd": 2.5, "speed": 120.0, "radius": 1.5, "dmg2": 12.0, "radius2": 4.0, "aa": true, "ag": true, "style": "missile"},
	"crusader_gun": {"dmg": 60.0, "type": "ARMOR_PIERCING", "range": 30.0, "cd": 2.0, "speed": 80.0, "radius": 1.2, "dmg2": 15.0, "radius2": 3.5, "aa": false, "ag": true, "style": "shell"},
	"paladin_gun": {"dmg": 60.0, "type": "ARMOR_PIERCING", "range": 30.0, "cd": 2.0, "speed": 60.0, "radius": 1.2, "dmg2": 15.0, "radius2": 3.5, "aa": false, "ag": true, "style": "shell"},
	"tomahawk": {"dmg": 150.0, "type": "EXPLOSION", "range": 70.0, "min_range": 20.0, "cd": 7.0, "speed": 40.0, "radius": 2.0, "dmg2": 50.0, "radius2": 5.0, "aa": false, "ag": true, "style": "cruise"},
	"avenger_laser": {"dmg": 25.0, "type": "AA", "range": 40.0, "cd": 0.4, "speed": 0.0, "aa": true, "ag": false, "style": "beam"},
	"pd_laser": {"dmg": 0.0, "type": "AA", "range": 22.0, "cd": 0.0, "speed": 0.0, "aa": true, "ag": false, "style": "beam"},
	"comanche_cannon": {"dmg": 6.0, "type": "COMANCHE_VULCAN", "range": 40.0, "cd": 0.1, "speed": 0.0, "aa": false, "ag": true, "style": "bullet"},
	"comanche_rockets": {"dmg": 30.0, "type": "EXPLOSION", "range": 40.0, "cd": 0.2, "clip": 20, "reload": 12.0, "speed": 100.0, "radius": 1.0, "dmg2": 10.0, "radius2": 8.0, "aa": false, "ag": true, "style": "missile", "upgrade": "rocket_pods"},
	"raptor_missile": {"dmg": 100.0, "type": "JET_MISSILES", "range": 64.0, "min_range": 8.0, "cd": 0.15, "clip": 4, "reload": -1.0, "speed": 200.0, "radius": 2.0, "dmg2": 30.0, "radius2": 5.0, "aa": true, "ag": true, "style": "missile"},
	"stealth_missile": {"dmg": 100.0, "type": "JET_MISSILES", "range": 44.0, "min_range": 8.0, "cd": 0.2, "clip": 2, "reload": -1.0, "speed": 200.0, "radius": 2.0, "dmg2": 30.0, "radius2": 5.0, "aa": false, "ag": true, "style": "missile"},
	"aurora_bomb": {"dmg": 400.0, "type": "AURORA_BOMB", "range": 30.0, "cd": 0.5, "clip": 1, "reload": -1.0, "speed": 60.0, "radius": 4.0, "dmg2": 120.0, "radius2": 9.0, "aa": false, "ag": true, "style": "bomb"},
	"patriot": {"dmg": 30.0, "type": "EXPLOSION", "range": 45.0, "cd": 0.25, "clip": 4, "reload": 2.0, "speed": 100.0, "radius": 1.5, "dmg2": 10.0, "radius2": 3.5, "aa": true, "ag": true, "style": "missile", "needs_power": true},
	"sc_cannon": {"dmg": 90.0, "type": "EXPLOSION", "range": 70.0, "min_range": 12.0, "cd": 3.0, "speed": 60.0, "radius": 2.5, "dmg2": 30.0, "radius2": 6.0, "aa": false, "ag": true, "style": "shell", "plan": "bombardment"},
	"firebase_gun": {"dmg": 75.0, "type": "EXPLOSION", "range": 55.0, "min_range": 10.0, "cd": 2.0, "speed": 60.0, "radius": 2.0, "dmg2": 25.0, "radius2": 5.0, "aa": false, "ag": true, "style": "shell"},
	"a10_gun": {"dmg": 45.0, "type": "COMANCHE_VULCAN", "range": 0.0, "cd": 1.0, "speed": 0.0, "radius": 3.0, "aa": false, "ag": true, "style": "bullet"},
	"a10_missile": {"dmg": 150.0, "type": "EXPLOSION", "range": 0.0, "cd": 1.0, "speed": 0.0, "radius": 6.0, "aa": false, "ag": true, "style": "missile"},
	"fab": {"dmg": 600.0, "type": "EXPLOSION", "range": 0.0, "cd": 1.0, "speed": 0.0, "radius": 30.0, "aa": false, "ag": true, "style": "bomb"},
	"particle": {"dmg": 120.0, "type": "PARTICLE_BEAM", "range": 0.0, "cd": 0.25, "speed": 0.0, "radius": 6.0, "aa": false, "ag": true, "style": "beam"},
}

# ---------------------------------------------------------------------------
# Units. speed m/s, vision m, radius m (collision), length m (visual fit).
# ---------------------------------------------------------------------------
const UNITS := {
	"dozer": {"name": "Construction Dozer", "cost": 1000, "time": 5.0, "hp": 250.0, "armor": "DozerArmor", "speed": 6.0, "turn": 90.0,
		"vision": 40.0, "radius": 1.3, "length": 4.4, "cat": "veh", "from": "command_center", "weapons": [], "builder": true, "crusher": true,
		"model": "Vehicles/SM_Veh_Truck_01.tscn", "wreck": "Vehicles/Destroyed/SM_Veh_Truck_01_Destroyed.tscn", "desc": "Builds and repairs structures."},
	"ranger": {"name": "Ranger", "cost": 225, "time": 5.0, "hp": 180.0, "armor": "HumanArmor", "speed": 4.0, "turn": 500.0,
		"vision": 20.0, "radius": 0.4, "length": 1.65, "cat": "inf", "from": "barracks", "weapons": ["ranger_rifle"], "crushable": true,
		"model": "Characters/SM_Chr_Soldier_Male_01.tscn", "desc": "Anti-infantry. Can capture structures (upgrade)."},
	"missile_defender": {"name": "Missile Defender", "cost": 300, "time": 5.0, "hp": 100.0, "armor": "HumanArmor", "speed": 4.0, "turn": 500.0,
		"vision": 30.0, "radius": 0.4, "length": 1.65, "cat": "inf", "from": "barracks", "weapons": ["md_missile"], "crushable": true,
		"model": "Characters/SM_Chr_Soldier_Male_02.tscn", "desc": "Anti-vehicle and anti-air missiles."},
	"pathfinder": {"name": "Pathfinder", "cost": 600, "time": 10.0, "hp": 120.0, "armor": "HumanArmor", "speed": 6.0, "turn": 500.0,
		"vision": 40.0, "radius": 0.4, "length": 1.65, "cat": "inf", "from": "barracks", "weapons": ["pathfinder_rifle"], "crushable": true,
		"needs_power": "pathfinder", "stealth": true,
		"model": "Characters/SM_Chr_Ghillie_Male_01.tscn", "desc": "Long-range sniper. Stealthed while still."},
	"burton": {"name": "Colonel Burton", "cost": 1500, "time": 20.0, "hp": 200.0, "armor": "HumanArmor", "speed": 6.0, "turn": 500.0,
		"vision": 30.0, "radius": 0.4, "length": 1.65, "cat": "inf", "from": "barracks", "weapons": ["burton_rifle"], "crushable": false,
		"prereq": ["strategy_center"], "limit": 1, "stealth": true,
		"model": "Characters/SM_Chr_Leader_Male_01.tscn", "desc": "Hero. Stealthed when not firing. One per player."},
	"humvee": {"name": "Humvee", "cost": 700, "time": 10.0, "hp": 240.0, "armor": "HumveeArmor", "speed": 12.0, "turn": 180.0,
		"vision": 30.0, "radius": 1.1, "length": 3.6, "cat": "veh", "from": "war_factory", "weapons": ["humvee_gun", "humvee_tow"], "cargo": 5, "fire_ports": true,
		"model": "Vehicles/SM_Veh_Light_Armored_Car_01.tscn", "wreck": "Vehicles/Destroyed/SM_Veh_Light_Armored_Car_01_Destroyed.tscn",
		"desc": "Fast anti-infantry scout. Carries 5 infantry who fire from inside. TOW missiles with upgrade."},
	"crusader": {"name": "Crusader Tank", "cost": 900, "time": 10.0, "hp": 480.0, "armor": "TankArmor", "speed": 6.0, "turn": 180.0,
		"vision": 30.0, "radius": 1.4, "length": 4.4, "cat": "veh", "from": "war_factory", "weapons": ["crusader_gun"], "crusher": true, "turret": true,
		"model": "Vehicles/SM_Veh_Tank_USA_01.tscn", "wreck": "Vehicles/Destroyed/SM_Veh_Tank_USA_Destroyed_01.tscn", "desc": "Main battle tank."},
	"paladin": {"name": "Paladin Tank", "cost": 1100, "time": 12.0, "hp": 500.0, "armor": "TankArmor", "speed": 6.0, "turn": 180.0,
		"vision": 30.0, "radius": 1.5, "length": 4.8, "cat": "veh", "from": "war_factory", "weapons": ["paladin_gun"], "crusher": true, "turret": true,
		"needs_power": "paladin",
		"model": "Vehicles/SM_Veh_Tank_German_01.tscn", "wreck": "Vehicles/Destroyed/SM_Veh_Tank_German_01_Destroyed.tscn", "desc": "Heavy tank. Requires General's promotion."},
	"tomahawk": {"name": "Tomahawk Launcher", "cost": 1200, "time": 20.0, "hp": 180.0, "armor": "TankArmor", "speed": 6.0, "turn": 180.0,
		"vision": 36.0, "radius": 1.4, "length": 4.5, "cat": "veh", "from": "war_factory", "weapons": ["tomahawk"], "prereq": ["strategy_center"],
		"model": "Vehicles/SM_Veh_Rocket_Truck_01.tscn", "wreck": "Vehicles/Destroyed/SM_Veh_Rocket_Truck_01_Destroyed.tscn", "desc": "Long-range cruise missile artillery."},
	"ambulance": {"name": "Ambulance", "cost": 600, "time": 10.0, "hp": 240.0, "armor": "HumveeArmor", "speed": 12.0, "turn": 180.0,
		"vision": 20.0, "radius": 1.1, "length": 3.6, "cat": "veh", "from": "war_factory", "weapons": [], "heal": {"cat": "inf", "radius": 1.1, "rate": 10.0},
		"model": "Vehicles/SM_Veh_Van_01.tscn", "wreck": "Vehicles/Destroyed/SM_Veh_Van_Destroyed_01.tscn", "desc": "Heals nearby infantry."},
	"avenger": {"name": "Avenger", "cost": 2000, "time": 10.0, "hp": 300.0, "armor": "AvengerArmor", "speed": 6.0, "turn": 180.0,
		"vision": 30.0, "radius": 1.2, "length": 4.0, "cat": "veh", "from": "war_factory", "weapons": ["avenger_laser"], "prereq": ["strategy_center"], "turret": true,
		"model": "Vehicles/SM_Veh_Radar_Tank_01.tscn", "wreck": "Vehicles/Destroyed/SM_Veh_Radar_Tank_01_Destroyed.tscn", "desc": "Anti-air laser platform."},
	"chinook": {"name": "Chinook", "cost": 1200, "time": 10.0, "hp": 300.0, "armor": "ChinookArmor", "speed": 22.0, "turn": 180.0,
		"vision": 60.0, "radius": 2.4, "length": 6.0, "cat": "air", "alt": 14.0, "from": "supply_center", "weapons": [], "gatherer": 8, "cargo": 8, "cargo_veh": true,
		"model": "Vehicles/SM_Veh_Helicopter_Transport_01.tscn", "wreck": "Vehicles/Destroyed/SM_Veh_Helicopter_Transport_01_Destroyed.tscn", "desc": "Collects supplies ($600 per load)."},
	"comanche": {"name": "Comanche", "cost": 1500, "time": 20.0, "hp": 220.0, "armor": "ComancheArmor", "speed": 24.0, "turn": 180.0,
		"vision": 40.0, "radius": 2.0, "length": 5.5, "cat": "air", "alt": 16.0, "from": "airfield", "weapons": ["comanche_cannon", "comanche_rockets"],
		"model": "Vehicles/SM_Veh_Helicopter_Attack_01.tscn", "wreck": "Vehicles/Destroyed/SM_Veh_Helicopter_Attack_01_Destroyed.tscn", "desc": "Attack helicopter. Rocket pods with upgrade."},
	"raptor": {"name": "Raptor", "cost": 1400, "time": 20.0, "hp": 160.0, "armor": "AirplaneArmor", "speed": 35.0, "turn": 120.0,
		"vision": 40.0, "radius": 2.4, "length": 6.5, "cat": "air", "alt": 20.0, "jet": true, "from": "airfield", "weapons": ["raptor_missile"],
		"model": "Vehicles/SM_Veh_Jet_01.tscn", "wreck": "Vehicles/Destroyed/SM_Veh_Jet_Destroyed_01.tscn", "desc": "Air superiority fighter. 4 missiles, rearms at Airfield."},
	"stealth_fighter": {"name": "Stealth Fighter", "cost": 1600, "time": 25.0, "hp": 120.0, "armor": "AirplaneArmor", "speed": 35.0, "turn": 180.0,
		"vision": 36.0, "radius": 2.4, "length": 6.5, "cat": "air", "alt": 20.0, "jet": true, "from": "airfield", "weapons": ["stealth_missile"],
		"needs_power": "stealth_fighter", "stealth": true,
		"model": "Vehicles/SM_Veh_Jet_02.tscn", "wreck": "Vehicles/Destroyed/SM_Veh_Jet_Destroyed_02.tscn", "desc": "Stealthed bomber. Requires General's promotion."},
	"aurora": {"name": "Aurora Bomber", "cost": 2500, "time": 30.0, "hp": 80.0, "armor": "AirplaneArmor", "speed": 36.0, "turn": 180.0,
		"vision": 36.0, "radius": 2.6, "length": 7.5, "cat": "air", "alt": 22.0, "jet": true, "from": "airfield", "weapons": ["aurora_bomb"], "prereq": ["strategy_center"],
		"model": "Vehicles/SM_Veh_Jet_02.tscn", "wreck": "Vehicles/Destroyed/SM_Veh_Jet_Destroyed_02.tscn", "desc": "Supersonic bomber. Devastating vs structures."},
}

# ---------------------------------------------------------------------------
# Buildings. fp = footprint in grid cells (2 m each). power +/-.
# ---------------------------------------------------------------------------
const BUILDINGS := {
	"command_center": {"name": "Command Center", "cost": 2000, "time": 45.0, "hp": 5000.0, "armor": "StructureArmorTough", "fp": Vector2i(6, 7),
		"power": 0, "vision": 60.0, "produces": ["dozer"], "model": "Buildings/SM_Bld_Hall_01.tscn", "height": 14.0,
		"desc": "Builds Dozers. Provides radar and General's powers."},
	"power_plant": {"name": "Cold Fusion Reactor", "cost": 800, "time": 10.0, "hp": 800.0, "armor": "StructureArmor", "fp": Vector2i(3, 3),
		"power": 5, "vision": 40.0, "upgrades": ["control_rods"], "model": "Buildings/SM_Bld_GasTower_01.tscn", "height": 10.0,
		"desc": "+5 power (+10 with Control Rods)."},
	"barracks": {"name": "Barracks", "cost": 600, "time": 10.0, "hp": 1000.0, "armor": "StructureArmor", "fp": Vector2i(5, 5),
		"power": 0, "vision": 40.0, "produces": ["ranger", "missile_defender", "pathfinder", "burton"], "upgrades": ["capture"],
		"heal": {"cat": "inf", "radius": 14.0, "rate": 8.0}, "model": "Buildings/SM_Bld_Barracks_01.tscn", "height": 7.0,
		"desc": "Trains infantry. Heals nearby infantry."},
	"supply_center": {"name": "Supply Center", "cost": 2000, "time": 10.0, "hp": 2000.0, "armor": "StructureArmor", "fp": Vector2i(5, 5),
		"power": -1, "vision": 40.0, "prereq": ["power_plant"], "produces": ["chinook"], "upgrades": ["supply_lines"], "free_unit": "chinook",
		"model": "Buildings/SM_Bld_Hangar_Open_01.tscn", "height": 8.0, "desc": "Supply drop-off. Comes with a free Chinook."},
	"war_factory": {"name": "War Factory", "cost": 2000, "time": 15.0, "hp": 2000.0, "armor": "StructureArmor", "fp": Vector2i(6, 6),
		"power": -1, "vision": 40.0, "prereq": ["supply_center"], "produces": ["humvee", "crusader", "paladin", "tomahawk", "ambulance", "avenger"],
		"upgrades": ["tow"], "heal": {"cat": "veh", "radius": 16.0, "rate": 15.0}, "model": "Buildings/SM_Bld_Hangar_01.tscn", "height": 9.0,
		"desc": "Builds vehicles. Repairs nearby vehicles."},
	"airfield": {"name": "Airfield", "cost": 1000, "time": 30.0, "hp": 1500.0, "armor": "StructureArmor", "fp": Vector2i(11, 8),
		"power": -1, "vision": 40.0, "prereq": ["supply_center"], "produces": ["raptor", "comanche", "stealth_fighter", "aurora"],
		"upgrades": ["rocket_pods", "laser_missiles"], "heal": {"cat": "air", "radius": 18.0, "rate": 15.0}, "pads": 4,
		"model": "Buildings/SM_Bld_ControlTower_01.tscn", "height": 9.0, "runway": true, "desc": "Builds aircraft. Jets rearm and repair here (4 pads)."},
	"strategy_center": {"name": "Strategy Center", "cost": 2500, "time": 60.0, "hp": 1500.0, "armor": "StructureArmor", "fp": Vector2i(6, 5),
		"power": -2, "vision": 80.0, "prereq_any": ["war_factory", "airfield"], "upgrades": ["composite_armor", "advanced_training", "supply_lines"],
		"weapons": ["sc_cannon"], "turret": true, "plans": true, "limit": 1,
		"model": "Buildings/SM_Bld_Hall_02.tscn", "height": 9.0, "desc": "Unlocks advanced units and upgrades. Choose a battle plan: Bombardment, Hold the Line or Search and Destroy."},
	"supply_drop_zone": {"name": "Supply Drop Zone", "cost": 2500, "time": 45.0, "hp": 1000.0, "armor": "StructureArmor", "fp": Vector2i(3, 3),
		"power": -4, "vision": 20.0, "prereq": ["strategy_center"], "income": {"amount": 1500, "every": 120.0},
		"model": "Buildings/SM_Bld_Plywood_Shed_01.tscn", "height": 4.0, "desc": "$1500 airdropped every 2 minutes."},
	"patriot": {"name": "Patriot Missile System", "cost": 1000, "time": 25.0, "hp": 1000.0, "armor": "BaseDefenseArmor", "fp": Vector2i(2, 2),
		"power": -3, "vision": 50.0, "prereq": ["power_plant"], "weapons": ["patriot"], "turret": true,
		"model": "Vehicles/SM_Veh_Rocket_Truck_01.tscn", "height": 4.0, "desc": "Guided-missile base defense (ground + air). Needs power."},
	"firebase": {"name": "Firebase", "cost": 1000, "time": 25.0, "hp": 1000.0, "armor": "FireBaseArmor", "fp": Vector2i(3, 3),
		"power": 0, "vision": 40.0, "prereq": ["power_plant"], "weapons": ["firebase_gun"], "turret": true, "cargo": 4, "fire_ports": true,
		"model": "Buildings/SM_Bld_Tent_Sandbags_01.tscn", "height": 3.5, "desc": "155mm artillery emplacement. Garrison up to 4 infantry - they fire from the sandbags."},
	"particle_cannon": {"name": "Particle Cannon", "cost": 5000, "time": 60.0, "hp": 4000.0, "armor": "StructureArmorTough", "fp": Vector2i(7, 4),
		"power": -10, "vision": 30.0, "prereq": ["strategy_center"], "superweapon": 240.0,
		"model": "Buildings/SM_Bld_OilTower_01.tscn", "height": 14.0, "desc": "Superweapon. Steerable orbital beam every 4 minutes."},
	# ---- neutral / map ----
	"supply_dock": {"name": "Supply Dock", "cost": 0, "time": 0.0, "hp": 5000.0, "armor": "InvulnerableArmor", "fp": Vector2i(4, 4),
		"power": 0, "vision": 0.0, "neutral": true, "boxes": 400, "model": "Props/Military/SM_Prop_Crate_Stack_Cover_01.tscn", "height": 4.0,
		"desc": "Supplies. $30,000 worth."},
	"oil_derrick": {"name": "Oil Derrick", "cost": 0, "time": 0.0, "hp": 1000.0, "armor": "StructureArmor", "fp": Vector2i(2, 3),
		"power": 0, "vision": 20.0, "neutral": true, "capturable": true, "income": {"amount": 200, "every": 12.0}, "capture_bonus": 1000,
		"model": "Buildings/SM_Bld_OilTower_01.tscn", "height": 12.0, "desc": "$200 every 12 s. Capture with Rangers ($1000 bonus)."},
}

const UPGRADES := {
	"control_rods": {"name": "Control Rods", "cost": 500, "time": 30.0, "desc": "Reactor output +5.", "per_building": true},
	"capture": {"name": "Capture Building", "cost": 1000, "time": 30.0, "desc": "Rangers can capture structures."},
	"supply_lines": {"name": "Supply Lines", "cost": 800, "time": 30.0, "desc": "+10% supply income."},
	"tow": {"name": "TOW Missiles", "cost": 1200, "time": 30.0, "desc": "Humvees fire TOW missiles (ground + air)."},
	"rocket_pods": {"name": "Rocket Pods", "cost": 800, "time": 30.0, "desc": "Comanches fire rocket pods at vehicles."},
	"laser_missiles": {"name": "Laser Guided Missiles", "cost": 1500, "time": 45.0, "desc": "Aircraft missile damage +25%."},
	"composite_armor": {"name": "Composite Armor", "cost": 2000, "time": 45.0, "desc": "Crusader / Paladin HP +25%."},
	"advanced_training": {"name": "Advanced Training", "cost": 1500, "time": 45.0, "desc": "Units gain experience twice as fast."},
}

## General's powers. rank = rank required, points = promotion points cost.
## kind: unlock (permanent) or ability with cooldown (seconds) and radius.
const POWERS := {
	"paladin": {"name": "Paladin Tank", "rank": 1, "kind": "unlock", "desc": "Unlocks the Paladin at the War Factory."},
	"stealth_fighter": {"name": "Stealth Fighter", "rank": 1, "kind": "unlock", "desc": "Unlocks the Stealth Fighter at the Airfield."},
	"spy_satellite": {"name": "Spy Satellite", "rank": 1, "kind": "ability", "cd": 120.0, "radius": 60.0, "desc": "Reveals an area for 15 s."},
	"a10": {"name": "A-10 Strike", "rank": 1, "kind": "ability", "cd": 240.0, "radius": 10.0, "levels": 3, "desc": "A-10s strafe the target. Each level adds a jet."},
	"pathfinder": {"name": "Pathfinder", "rank": 3, "kind": "unlock", "desc": "Unlocks the Pathfinder sniper at the Barracks."},
	"emergency_repair": {"name": "Emergency Repair", "rank": 3, "kind": "ability", "cd": 120.0, "radius": 20.0, "desc": "Fully repairs vehicles in the area."},
	"paradrop": {"name": "Paradrop", "rank": 3, "kind": "ability", "cd": 240.0, "radius": 6.0, "desc": "Drops 4 Rangers at the target."},
	"fuel_air_bomb": {"name": "Fuel Air Bomb", "rank": 5, "kind": "ability", "cd": 300.0, "radius": 30.0, "auto": true, "desc": "Massive thermobaric strike."},
}

const TEAM_COLORS := [Color(0.25, 0.55, 1.0), Color(1.0, 0.25, 0.2), Color(0.3, 0.9, 0.35), Color(1.0, 0.85, 0.2), Color(0.85, 0.35, 1.0), Color(1.0, 0.55, 0.15)]
const TEAM_NAMES := ["Blue", "Red", "Green", "Yellow", "Purple", "Orange"]

static func def(type: String) -> Dictionary:
	if UNITS.has(type):
		return UNITS[type]
	if BUILDINGS.has(type):
		return BUILDINGS[type]
	return {}

static func is_building(type: String) -> bool:
	return BUILDINGS.has(type)

static func armor_mult(armor: String, dmg_type: String) -> float:
	var a: Dictionary = ARMOR.get(armor, {})
	if a.has(dmg_type):
		return a[dmg_type]
	return a.get("DEFAULT", 1.0)

static func footprint_size(type: String) -> Vector2:
	var d := def(type)
	if d.has("fp"):
		return Vector2(d["fp"]) * 2.0
	return Vector2(d.get("radius", 1.0) * 2.0, d.get("radius", 1.0) * 2.0)
