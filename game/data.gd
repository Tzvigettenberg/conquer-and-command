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
	# ---- China ----
	"redguard_rifle": {"dmg": 5.0, "type": "SMALL_ARMS", "range": 20.0, "cd": 0.12, "clip": 3, "reload": 0.8, "speed": 0.0, "aa": false, "ag": true, "style": "bullet"},
	"th_rocket": {"dmg": 40.0, "type": "INFANTRY_MISSILE", "range": 35.0, "cd": 1.2, "speed": 120.0, "radius": 1.5, "dmg2": 12.0, "radius2": 4.0, "aa": true, "ag": true, "style": "missile"},
	"battlemaster_gun": {"dmg": 60.0, "type": "ARMOR_PIERCING", "range": 30.0, "cd": 2.2, "speed": 80.0, "radius": 1.2, "dmg2": 15.0, "radius2": 3.5, "aa": false, "ag": true, "style": "shell"},
	"gattling_gun": {"dmg": 7.0, "type": "GATTLING", "range": 30.0, "cd": 0.08, "speed": 0.0, "aa": true, "ag": true, "style": "bullet"},
	"dragon_flame": {"dmg": 9.0, "type": "FLAME", "range": 14.0, "cd": 0.1, "speed": 0.0, "radius": 1.6, "dmg2": 4.0, "radius2": 2.6, "aa": false, "ag": true, "style": "flame"},
	"inferno_shell": {"dmg": 70.0, "type": "FLAME", "range": 60.0, "min_range": 12.0, "cd": 4.0, "speed": 40.0, "radius": 3.0, "dmg2": 25.0, "radius2": 6.5, "aa": false, "ag": true, "style": "shell", "fire": true},
	"overlord_gun": {"dmg": 100.0, "type": "ARMOR_PIERCING", "range": 30.0, "cd": 2.2, "speed": 80.0, "radius": 1.5, "dmg2": 25.0, "radius2": 4.0, "aa": false, "ag": true, "style": "shell"},
	"nuke_shell": {"dmg": 300.0, "type": "EXPLOSION", "range": 90.0, "min_range": 22.0, "cd": 8.0, "speed": 50.0, "radius": 4.0, "dmg2": 100.0, "radius2": 10.0, "aa": false, "ag": true, "style": "shell", "zone": {"kind": "radiation", "r": 6.0, "dps": 10.0, "t": 8.0}},
	"mig_napalm": {"dmg": 80.0, "type": "FLAME", "range": 40.0, "min_range": 8.0, "cd": 0.2, "clip": 2, "reload": -1.0, "speed": 200.0, "radius": 3.0, "dmg2": 30.0, "radius2": 7.0, "aa": false, "ag": true, "style": "missile", "fire": true},
	"helix_gun": {"dmg": 8.0, "type": "GATTLING", "range": 35.0, "cd": 0.1, "speed": 0.0, "aa": true, "ag": true, "style": "bullet"},
	"gattling_cannon": {"dmg": 8.0, "type": "GATTLING", "range": 40.0, "cd": 0.06, "speed": 0.0, "aa": true, "ag": true, "style": "bullet", "needs_power": true},
	"arty_shell": {"dmg": 90.0, "type": "EXPLOSION", "range": 0.0, "cd": 1.0, "speed": 0.0, "radius": 3.5, "dmg2": 30.0, "radius2": 7.0, "aa": false, "ag": true, "style": "shell"},
	"carpet_bomb": {"dmg": 250.0, "type": "EXPLOSION", "range": 0.0, "cd": 1.0, "speed": 0.0, "radius": 8.0, "dmg2": 80.0, "radius2": 14.0, "aa": false, "ag": true, "style": "bomb"},
	"nuke": {"dmg": 1500.0, "type": "EXPLOSION", "range": 0.0, "cd": 1.0, "speed": 0.0, "radius": 14.0, "dmg2": 500.0, "radius2": 30.0, "aa": true, "ag": true, "style": "nuke", "zone": {"kind": "radiation", "r": 24.0, "dps": 15.0, "t": 25.0}},
	# ---- GLA ----
	"rebel_rifle": {"dmg": 5.0, "type": "SMALL_ARMS", "range": 20.0, "cd": 0.1, "clip": 3, "reload": 0.7, "speed": 0.0, "aa": false, "ag": true, "style": "bullet"},
	"rpg_rocket": {"dmg": 40.0, "type": "INFANTRY_MISSILE", "range": 35.0, "cd": 1.0, "speed": 120.0, "radius": 1.5, "dmg2": 12.0, "radius2": 4.0, "aa": true, "ag": true, "style": "missile"},
	"terrorist_bomb": {"dmg": 400.0, "type": "EXPLOSION", "range": 1.5, "cd": 1.0, "speed": 0.0, "radius": 5.0, "dmg2": 150.0, "radius2": 8.0, "aa": false, "ag": true, "style": "bomb", "suicide": true},
	"kell_rifle": {"dmg": 120.0, "type": "SNIPER", "range": 60.0, "cd": 2.5, "speed": 0.0, "aa": false, "ag": true, "style": "bullet"},
	"technical_gun": {"dmg": 9.0, "type": "COMANCHE_VULCAN", "range": 30.0, "cd": 0.15, "speed": 0.0, "aa": false, "ag": true, "style": "bullet"},
	"scorpion_gun": {"dmg": 50.0, "type": "ARMOR_PIERCING", "range": 28.0, "cd": 2.0, "speed": 80.0, "radius": 1.2, "dmg2": 12.0, "radius2": 3.5, "aa": false, "ag": true, "style": "shell"},
	"scorpion_rocket": {"dmg": 45.0, "type": "INFANTRY_MISSILE", "range": 32.0, "cd": 6.0, "speed": 100.0, "radius": 1.5, "dmg2": 15.0, "radius2": 4.0, "aa": false, "ag": true, "style": "missile", "upgrade": "scorpion_rocket"},
	"quad_gun": {"dmg": 8.0, "type": "GATTLING", "range": 32.0, "cd": 0.07, "speed": 0.0, "aa": true, "ag": true, "style": "bullet"},
	"buggy_rockets": {"dmg": 25.0, "type": "EXPLOSION", "range": 60.0, "min_range": 10.0, "cd": 0.15, "clip": 12, "reload": 8.0, "speed": 90.0, "radius": 1.2, "dmg2": 8.0, "radius2": 4.0, "aa": false, "ag": true, "style": "missile"},
	"toxin_spray": {"dmg": 7.0, "type": "FLAME", "range": 14.0, "cd": 0.1, "speed": 0.0, "radius": 1.6, "dmg2": 3.0, "radius2": 2.6, "aa": false, "ag": true, "style": "flame", "toxin": true},
	"marauder_gun": {"dmg": 65.0, "type": "ARMOR_PIERCING", "range": 30.0, "cd": 2.0, "speed": 80.0, "radius": 1.2, "dmg2": 15.0, "radius2": 3.5, "aa": false, "ag": true, "style": "shell"},
	"scud": {"dmg": 300.0, "type": "EXPLOSION", "range": 80.0, "min_range": 20.0, "cd": 10.0, "speed": 35.0, "radius": 5.0, "dmg2": 100.0, "radius2": 10.0, "aa": false, "ag": true, "style": "cruise", "zone": {"kind": "toxin", "r": 7.0, "dps": 8.0, "t": 12.0}},
	"bombtruck_bomb": {"dmg": 800.0, "type": "EXPLOSION", "range": 2.0, "cd": 1.0, "speed": 0.0, "radius": 8.0, "dmg2": 300.0, "radius2": 14.0, "aa": false, "ag": true, "style": "bomb", "suicide": true},
	"stinger": {"dmg": 40.0, "type": "INFANTRY_MISSILE", "range": 42.0, "cd": 0.4, "clip": 3, "reload": 3.0, "speed": 120.0, "radius": 1.5, "dmg2": 12.0, "radius2": 4.0, "aa": true, "ag": true, "style": "missile"},
	"tunnel_gun": {"dmg": 40.0, "type": "INFANTRY_MISSILE", "range": 38.0, "cd": 1.5, "speed": 120.0, "radius": 1.5, "dmg2": 12.0, "radius2": 4.0, "aa": true, "ag": true, "style": "missile"},
	"demo_charge": {"dmg": 400.0, "type": "EXPLOSION", "range": 0.0, "cd": 1.0, "speed": 0.0, "radius": 7.0, "dmg2": 120.0, "radius2": 11.0, "aa": false, "ag": true, "style": "bomb"},
	"scud_storm": {"dmg": 320.0, "type": "EXPLOSION", "range": 0.0, "cd": 1.0, "speed": 0.0, "radius": 8.0, "dmg2": 120.0, "radius2": 14.0, "aa": false, "ag": true, "style": "cruise", "zone": {"kind": "toxin", "r": 12.0, "dps": 12.0, "t": 25.0}},
	"anthrax_bomb": {"dmg": 200.0, "type": "FLAME", "range": 0.0, "cd": 1.0, "speed": 0.0, "radius": 20.0, "dmg2": 60.0, "radius2": 28.0, "aa": false, "ag": true, "style": "bomb", "zone": {"kind": "toxin", "r": 26.0, "dps": 20.0, "t": 15.0}},
	# ---- USA additions: drones, sentry, microwave, spectre ----
	"drone_gun": {"dmg": 4.0, "type": "SMALL_ARMS", "range": 24.0, "cd": 0.15, "speed": 0.0, "aa": false, "ag": true, "style": "bullet"},
	"drone_missile": {"dmg": 30.0, "type": "INFANTRY_MISSILE", "range": 30.0, "cd": 2.5, "speed": 120.0, "radius": 1.2, "dmg2": 8.0, "radius2": 3.0, "aa": false, "ag": true, "style": "missile"},
	"sentry_gun": {"dmg": 6.0, "type": "COMANCHE_VULCAN", "range": 26.0, "cd": 0.12, "speed": 0.0, "aa": false, "ag": true, "style": "bullet", "upgrade": "sentry_guns"},
	"microwave": {"dmg": 12.0, "type": "FLAME", "range": 18.0, "cd": 0.2, "speed": 0.0, "radius": 2.0, "dmg2": 6.0, "radius2": 3.5, "aa": false, "ag": true, "style": "microwave"},
	"spectre_gun": {"dmg": 30.0, "type": "COMANCHE_VULCAN", "range": 0.0, "cd": 1.0, "speed": 0.0, "radius": 2.0, "aa": false, "ag": true, "style": "bullet"},
	"spectre_howitzer": {"dmg": 120.0, "type": "EXPLOSION", "range": 0.0, "cd": 1.0, "speed": 0.0, "radius": 4.0, "dmg2": 40.0, "radius2": 8.0, "aa": false, "ag": true, "style": "shell"},
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
		"vision": 36.0, "radius": 2.6, "length": 7.5, "cat": "air", "alt": 22.0, "jet": true, "from": "airfield", "weapons": ["aurora_bomb"], "prereq": ["strategy_center"], "supersonic": true,
		"model": "Vehicles/SM_Veh_Jet_02.tscn", "wreck": "Vehicles/Destroyed/SM_Veh_Jet_Destroyed_02.tscn", "desc": "Supersonic bomber: untouchable on the way in, slow and vulnerable after the drop. Devastating vs structures."},
	# ---- China ----
	"china_dozer": {"name": "Construction Dozer", "faction": "china", "cost": 1000, "time": 5.0, "hp": 250.0, "armor": "DozerArmor", "speed": 6.0, "turn": 90.0,
		"vision": 40.0, "radius": 1.3, "length": 4.4, "cat": "veh", "from": "china_cc", "weapons": [], "builder": true, "crusher": true, "snd": "truck", "voice": "china_dozer",
		"desc": "Builds and repairs structures."},
	"red_guard": {"name": "Red Guard", "faction": "china", "cost": 300, "time": 6.0, "hp": 180.0, "armor": "HumanArmor", "speed": 4.0, "turn": 500.0,
		"vision": 20.0, "radius": 0.4, "length": 1.65, "cat": "inf", "from": "china_barracks", "weapons": ["redguard_rifle"], "crushable": true, "pair": true, "horde": true, "capture": true, "voice": "red_guard",
		"desc": "Trained in pairs. Anti-infantry; +25% damage in a horde of 5. Can capture structures (upgrade)."},
	"tank_hunter": {"name": "Tank Hunter", "faction": "china", "cost": 300, "time": 5.0, "hp": 120.0, "armor": "HumanArmor", "speed": 4.0, "turn": 500.0,
		"vision": 30.0, "radius": 0.4, "length": 1.65, "cat": "inf", "from": "china_barracks", "weapons": ["th_rocket"], "crushable": true, "horde": true, "voice": "tank_hunter",
		"desc": "Anti-vehicle and anti-air rockets. Horde bonus."},
	"hacker": {"name": "Hacker", "faction": "china", "cost": 625, "time": 10.0, "hp": 100.0, "armor": "HumanArmor", "speed": 4.0, "turn": 500.0,
		"vision": 24.0, "radius": 0.4, "length": 1.65, "cat": "inf", "from": "china_barracks", "weapons": [], "crushable": true, "hack": {"cash": 6, "every": 2.0}, "voice": "hacker",
		"desc": "Sits down and hacks the internet for cash ($6 every 2 s) whenever idle."},
	"black_lotus": {"name": "Black Lotus", "faction": "china", "cost": 1500, "time": 20.0, "hp": 150.0, "armor": "HumanArmor", "speed": 5.0, "turn": 500.0,
		"vision": 36.0, "radius": 0.4, "length": 1.65, "cat": "inf", "from": "china_barracks", "weapons": [], "crushable": true, "prereq": ["propaganda_center"], "limit": 1, "stealth": true,
		"capture": true, "capture_free": true, "capture_reach": 12.0, "voice": "black_lotus", "desc": "Hero. Stealthed; captures structures from a distance without any upgrade. One per player."},
	"supply_truck": {"name": "Supply Truck", "faction": "china", "cost": 600, "time": 8.0, "hp": 240.0, "armor": "HumveeArmor", "speed": 8.0, "turn": 180.0,
		"vision": 24.0, "radius": 1.2, "length": 4.0, "cat": "veh", "from": "china_supply", "weapons": [], "gatherer": 4, "load_t": 0.7, "unload_t": 2.0, "snd": "truck", "voice": "supply_truck",
		"desc": "Hauls 4 supply boxes ($300) per trip."},
	"battlemaster": {"name": "Battlemaster Tank", "faction": "china", "cost": 800, "time": 10.0, "hp": 400.0, "armor": "TankArmor", "speed": 6.0, "turn": 180.0,
		"vision": 30.0, "radius": 1.4, "length": 4.4, "cat": "veh", "from": "china_factory", "weapons": ["battlemaster_gun"], "crusher": true, "turret": true, "horde": true, "shells": true, "snd": "tank", "voice": "cn_tank",
		"desc": "Main battle tank. +25% damage in a horde of 5."},
	"gattling_tank": {"name": "Gattling Tank", "faction": "china", "cost": 800, "time": 10.0, "hp": 380.0, "armor": "TankArmor", "speed": 6.5, "turn": 180.0,
		"vision": 32.0, "radius": 1.3, "length": 4.2, "cat": "veh", "from": "china_factory", "weapons": ["gattling_gun"], "crusher": true, "turret": true, "snd": "tank", "voice": "cn_tank",
		"desc": "Anti-infantry and anti-air gattling gun."},
	"dragon_tank": {"name": "Dragon Tank", "faction": "china", "cost": 800, "time": 10.0, "hp": 300.0, "armor": "TankArmor", "speed": 6.0, "turn": 180.0,
		"vision": 24.0, "radius": 1.3, "length": 4.3, "cat": "veh", "from": "china_factory", "weapons": ["dragon_flame"], "crusher": true, "turret": true, "snd": "tank", "voice": "cn_tank",
		"desc": "Flamethrower tank. Roasts infantry and garrisons; burns structures."},
	"troop_crawler": {"name": "Troop Crawler", "faction": "china", "cost": 1400, "time": 15.0, "hp": 250.0, "armor": "HumveeArmor", "speed": 8.0, "turn": 180.0,
		"vision": 40.0, "radius": 1.4, "length": 5.0, "cat": "veh", "from": "china_factory", "weapons": [], "cargo": 8, "spawn_cargo": ["red_guard", "red_guard", "red_guard", "red_guard", "red_guard", "red_guard", "red_guard", "red_guard"], "snd": "truck", "voice": "troop_crawler",
		"desc": "Armoured transport that arrives packed with 8 Red Guards. Carries 8 infantry."},
	"inferno_cannon": {"name": "Inferno Cannon", "faction": "china", "cost": 900, "time": 12.0, "hp": 200.0, "armor": "TankArmor", "speed": 6.0, "turn": 180.0,
		"vision": 36.0, "radius": 1.3, "length": 4.4, "cat": "veh", "from": "china_factory", "weapons": ["inferno_shell"], "prereq": ["propaganda_center"], "snd": "tank", "voice": "cn_artillery",
		"desc": "Long-range napalm artillery."},
	"overlord": {"name": "Overlord Tank", "faction": "china", "cost": 2000, "time": 20.0, "hp": 1000.0, "armor": "TankArmor", "speed": 4.5, "turn": 120.0,
		"vision": 30.0, "radius": 1.9, "length": 6.0, "cat": "veh", "from": "china_factory", "weapons": ["overlord_gun"], "crusher": true, "turret": true, "prereq": ["propaganda_center"], "shells": true, "snd": "tank", "voice": "cn_tank",
		"desc": "Enormous twin-cannon tank. Crushes anything it drives over."},
	"nuke_cannon": {"name": "Nuke Cannon", "faction": "china", "cost": 1600, "time": 20.0, "hp": 250.0, "armor": "TankArmor", "speed": 5.0, "turn": 150.0,
		"vision": 40.0, "radius": 1.4, "length": 4.8, "cat": "veh", "from": "china_factory", "weapons": ["nuke_shell"], "prereq": ["propaganda_center"], "needs_power": "nuke_cannon", "snd": "tank", "voice": "cn_artillery",
		"desc": "Fires tactical nuclear shells at extreme range. Leaves radiation."},
	"mig": {"name": "MiG", "faction": "china", "cost": 1200, "time": 15.0, "hp": 100.0, "armor": "AirplaneArmor", "speed": 34.0, "turn": 130.0,
		"vision": 40.0, "radius": 2.4, "length": 6.5, "cat": "air", "alt": 20.0, "jet": true, "from": "china_airfield", "weapons": ["mig_napalm"], "snd": "jet", "voice": "mig",
		"desc": "Fighter-bomber with two napalm missiles. Rearms at the Airfield."},
	"helix": {"name": "Helix", "faction": "china", "cost": 1500, "time": 20.0, "hp": 600.0, "armor": "ChinookArmor", "speed": 18.0, "turn": 150.0,
		"vision": 40.0, "radius": 2.4, "length": 6.0, "cat": "air", "alt": 15.0, "from": "china_airfield", "weapons": ["helix_gun"], "cargo": 5, "snd": "heli", "voice": "helix",
		"desc": "Heavy helicopter with a gattling gun. Carries 5 infantry."},
	# ---- GLA ----
	"worker": {"name": "Worker", "faction": "gla", "cost": 200, "time": 5.0, "hp": 100.0, "armor": "HumanArmor", "speed": 4.2, "turn": 500.0,
		"vision": 24.0, "radius": 0.4, "length": 1.65, "cat": "inf", "from": "gla_cc", "weapons": [], "builder": true, "gatherer": 2, "load_t": 0.8, "unload_t": 0.6, "crushable": true, "voice": "worker",
		"desc": "Builds and repairs structures, and carries supplies ($150 per trip)."},
	"rebel": {"name": "Rebel", "faction": "gla", "cost": 150, "time": 5.0, "hp": 120.0, "armor": "HumanArmor", "speed": 4.2, "turn": 500.0,
		"vision": 20.0, "radius": 0.4, "length": 1.65, "cat": "inf", "from": "gla_barracks", "weapons": ["rebel_rifle"], "crushable": true, "capture": true, "voice": "rebel",
		"desc": "Cheap anti-infantry. Can capture structures (upgrade)."},
	"rpg_trooper": {"name": "RPG Trooper", "faction": "gla", "cost": 300, "time": 5.0, "hp": 100.0, "armor": "HumanArmor", "speed": 4.2, "turn": 500.0,
		"vision": 30.0, "radius": 0.4, "length": 1.65, "cat": "inf", "from": "gla_barracks", "weapons": ["rpg_rocket"], "crushable": true, "voice": "rpg_trooper",
		"desc": "Anti-vehicle and anti-air rockets."},
	"terrorist": {"name": "Terrorist", "faction": "gla", "cost": 200, "time": 5.0, "hp": 100.0, "armor": "HumanArmor", "speed": 5.0, "turn": 500.0,
		"vision": 20.0, "radius": 0.4, "length": 1.65, "cat": "inf", "from": "gla_barracks", "weapons": ["terrorist_bomb"], "crushable": true, "suicide": true, "voice": "terrorist",
		"desc": "Runs at the target and detonates. Devastating against vehicles and structures."},
	"jarmen_kell": {"name": "Jarmen Kell", "faction": "gla", "cost": 1500, "time": 20.0, "hp": 150.0, "armor": "HumanArmor", "speed": 6.0, "turn": 500.0,
		"vision": 40.0, "radius": 0.4, "length": 1.65, "cat": "inf", "from": "gla_barracks", "weapons": ["kell_rifle"], "crushable": false, "prereq": ["palace"], "limit": 1, "stealth": true, "voice": "jarmen_kell",
		"desc": "Hero sniper. Stealthed when not firing. One per player."},
	"technical": {"name": "Technical", "faction": "gla", "cost": 500, "time": 8.0, "hp": 220.0, "armor": "HumveeArmor", "speed": 13.0, "turn": 200.0,
		"vision": 30.0, "radius": 1.1, "length": 3.8, "cat": "veh", "from": "arms_dealer", "weapons": ["technical_gun"], "cargo": 5, "fire_ports": true, "turret": true, "snd": "humvee", "voice": "gla_truck",
		"desc": "Fast pickup with a machine gun. Carries 5 infantry who fire from the bed."},
	"scorpion": {"name": "Scorpion Tank", "faction": "gla", "cost": 600, "time": 10.0, "hp": 320.0, "armor": "TankArmor", "speed": 7.0, "turn": 180.0,
		"vision": 30.0, "radius": 1.3, "length": 4.2, "cat": "veh", "from": "arms_dealer", "weapons": ["scorpion_gun", "scorpion_rocket"], "crusher": true, "turret": true, "snd": "tank", "voice": "gla_tank",
		"desc": "Light tank. Fires a rocket too with the Scorpion Rocket upgrade."},
	"quad_cannon": {"name": "Quad Cannon", "faction": "gla", "cost": 700, "time": 10.0, "hp": 240.0, "armor": "HumveeArmor", "speed": 9.0, "turn": 180.0,
		"vision": 32.0, "radius": 1.2, "length": 4.0, "cat": "veh", "from": "arms_dealer", "weapons": ["quad_gun"], "turret": true, "snd": "truck", "voice": "quad_cannon",
		"desc": "Four-barrel anti-air and anti-infantry gun."},
	"rocket_buggy": {"name": "Rocket Buggy", "faction": "gla", "cost": 900, "time": 12.0, "hp": 150.0, "armor": "HumveeArmor", "speed": 13.0, "turn": 220.0,
		"vision": 40.0, "radius": 1.0, "length": 3.6, "cat": "veh", "from": "arms_dealer", "weapons": ["buggy_rockets"], "turret": true, "snd": "humvee", "voice": "rocket_buggy",
		"desc": "Fast long-range rocket artillery. 12 rockets, then reloads."},
	"toxin_tractor": {"name": "Toxin Tractor", "faction": "gla", "cost": 600, "time": 10.0, "hp": 300.0, "armor": "TankArmor", "speed": 7.0, "turn": 180.0,
		"vision": 24.0, "radius": 1.3, "length": 4.2, "cat": "veh", "from": "arms_dealer", "weapons": ["toxin_spray"], "turret": true, "snd": "truck", "voice": "toxin_tractor",
		"desc": "Sprays toxins that melt infantry and clear garrisons."},
	"marauder": {"name": "Marauder Tank", "faction": "gla", "cost": 800, "time": 12.0, "hp": 450.0, "armor": "TankArmor", "speed": 6.5, "turn": 180.0,
		"vision": 30.0, "radius": 1.4, "length": 4.6, "cat": "veh", "from": "arms_dealer", "weapons": ["marauder_gun"], "crusher": true, "turret": true, "needs_power": "marauder", "snd": "tank", "voice": "gla_tank",
		"desc": "Heavy tank. Requires General's promotion."},
	"scud_launcher": {"name": "SCUD Launcher", "faction": "gla", "cost": 1200, "time": 20.0, "hp": 180.0, "armor": "TankArmor", "speed": 6.0, "turn": 150.0,
		"vision": 36.0, "radius": 1.4, "length": 5.0, "cat": "veh", "from": "arms_dealer", "weapons": ["scud"], "prereq": ["palace"], "snd": "truck", "voice": "scud_launcher",
		"desc": "Long-range missile artillery. Warheads leave a toxin cloud."},
	"bomb_truck": {"name": "Bomb Truck", "faction": "gla", "cost": 1200, "time": 15.0, "hp": 220.0, "armor": "HumveeArmor", "speed": 8.0, "turn": 180.0,
		"vision": 24.0, "radius": 1.2, "length": 4.2, "cat": "veh", "from": "arms_dealer", "weapons": ["bombtruck_bomb"], "suicide": true, "snd": "truck", "voice": "gla_truck",
		"desc": "Drives into the target and detonates. Levels structures."},
	# ---- USA additions ----
	"scout_drone": {"name": "Scout Drone", "cost": 100, "time": 4.0, "hp": 60.0, "armor": "AirplaneArmor", "speed": 14.0, "turn": 400.0,
		"vision": 50.0, "radius": 0.5, "length": 1.2, "cat": "air", "alt": 5.0, "weapons": [], "drone": true, "detector": true, "snd": "", "voice": "",
		"desc": "Attached to a vehicle. Extends its vision and detects stealth."},
	"battle_drone": {"name": "Battle Drone", "cost": 200, "time": 4.0, "hp": 90.0, "armor": "AirplaneArmor", "speed": 14.0, "turn": 400.0,
		"vision": 30.0, "radius": 0.5, "length": 1.3, "cat": "air", "alt": 5.0, "weapons": ["drone_gun"], "drone": true, "repairs": 4.0, "snd": "", "voice": "",
		"desc": "Attached to a vehicle. Machine gun, and repairs its vehicle in the field."},
	"hellfire_drone": {"name": "Hellfire Drone", "cost": 500, "time": 5.0, "hp": 90.0, "armor": "AirplaneArmor", "speed": 14.0, "turn": 400.0,
		"vision": 30.0, "radius": 0.5, "length": 1.4, "cat": "air", "alt": 5.0, "weapons": ["drone_missile"], "drone": true, "snd": "", "voice": "",
		"desc": "Attached to a vehicle. Fires Hellfire missiles at vehicles and infantry."},
	"spy_drone": {"name": "Spy Drone", "cost": 0, "time": 0.0, "hp": 40.0, "armor": "AirplaneArmor", "speed": 0.0, "turn": 400.0,
		"vision": 55.0, "radius": 0.5, "length": 1.2, "cat": "air", "alt": 24.0, "weapons": [], "detector": true, "stealth": true, "lifetime": 90.0, "snd": "", "voice": "",
		"desc": "Loiters over the spot for 90 s, revealing everything below and detecting stealth."},
	"sentry_drone": {"name": "Sentry Drone", "cost": 800, "time": 10.0, "hp": 200.0, "armor": "HumveeArmor", "speed": 9.0, "turn": 300.0,
		"vision": 44.0, "radius": 0.9, "length": 2.6, "cat": "veh", "from": "war_factory", "weapons": ["sentry_gun"], "stealth": true, "detector": true, "turret": true, "snd": "humvee", "voice": "avenger",
		"desc": "Stealthed unmanned scout that detects stealth. Fires 20mm guns with the Sentry Drone Guns upgrade."},
	"microwave_tank": {"name": "Microwave Tank", "cost": 800, "time": 12.0, "hp": 400.0, "armor": "TankArmor", "speed": 6.0, "turn": 180.0,
		"vision": 30.0, "radius": 1.4, "length": 4.4, "cat": "veh", "from": "war_factory", "weapons": ["microwave"], "prereq": ["strategy_center"], "turret": true, "snd": "tank", "voice": "tank",
		"desc": "Cooks infantry, including anyone garrisoned inside a building."},
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
		"power": -1, "vision": 40.0, "prereq": ["supply_center"], "produces": ["humvee", "crusader", "paladin", "tomahawk", "ambulance", "avenger", "sentry_drone", "microwave_tank"],
		"upgrades": ["tow", "sentry_guns"], "heal": {"cat": "veh", "radius": 16.0, "rate": 15.0}, "model": "Buildings/SM_Bld_Hangar_01.tscn", "height": 9.0,
		"desc": "Builds vehicles. Repairs nearby vehicles."},
	"airfield": {"name": "Airfield", "cost": 1000, "time": 30.0, "hp": 1500.0, "armor": "StructureArmor", "fp": Vector2i(11, 8),
		"power": -1, "vision": 40.0, "prereq": ["supply_center"], "produces": ["raptor", "comanche", "stealth_fighter", "aurora"],
		"upgrades": ["rocket_pods", "laser_missiles", "countermeasures"], "heal": {"cat": "air", "radius": 18.0, "rate": 15.0}, "pads": 4,
		"model": "Buildings/SM_Bld_ControlTower_01.tscn", "height": 9.0, "runway": true, "desc": "Builds aircraft. Jets rearm and repair here (4 pads)."},
	"strategy_center": {"name": "Strategy Center", "cost": 2500, "time": 60.0, "hp": 1500.0, "armor": "StructureArmor", "fp": Vector2i(6, 5),
		"power": -2, "vision": 80.0, "prereq_any": ["war_factory", "airfield"], "upgrades": ["composite_armor", "advanced_training", "supply_lines", "chemical_suits"],
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
	# ---- China ----
	"china_cc": {"name": "Command Center", "faction": "china", "role": "cc", "cost": 2000, "time": 45.0, "hp": 5000.0, "armor": "StructureArmorTough", "fp": Vector2i(6, 7),
		"power": 0, "vision": 60.0, "produces": ["china_dozer"], "height": 14.0, "desc": "Builds Dozers. Provides radar and General's powers."},
	"china_reactor": {"name": "Nuclear Reactor", "faction": "china", "role": "power", "cost": 1000, "time": 12.0, "hp": 1000.0, "armor": "StructureArmor", "fp": Vector2i(4, 4),
		"power": 10, "vision": 40.0, "upgrades": ["uranium_shells"], "height": 10.0, "desc": "+10 power."},
	"china_barracks": {"name": "Barracks", "faction": "china", "role": "barracks", "cost": 500, "time": 10.0, "hp": 1000.0, "armor": "StructureArmor", "fp": Vector2i(5, 5),
		"power": 0, "vision": 40.0, "produces": ["red_guard", "tank_hunter", "hacker", "black_lotus"], "upgrades": ["capture"],
		"heal": {"cat": "inf", "radius": 14.0, "rate": 8.0}, "height": 7.0, "desc": "Trains infantry. Heals nearby infantry."},
	"china_supply": {"name": "Supply Center", "faction": "china", "role": "supply", "cost": 1500, "time": 10.0, "hp": 2000.0, "armor": "StructureArmor", "fp": Vector2i(5, 5),
		"power": -1, "vision": 40.0, "prereq": ["china_reactor"], "produces": ["supply_truck"], "free_unit": "supply_truck", "height": 8.0,
		"desc": "Supply drop-off. Comes with a free Supply Truck."},
	"china_factory": {"name": "War Factory", "faction": "china", "role": "factory", "cost": 2000, "time": 15.0, "hp": 2000.0, "armor": "StructureArmor", "fp": Vector2i(6, 6),
		"power": -1, "vision": 40.0, "prereq": ["china_supply"], "produces": ["battlemaster", "gattling_tank", "dragon_tank", "troop_crawler", "inferno_cannon", "overlord", "nuke_cannon"],
		"upgrades": ["chain_guns"], "heal": {"cat": "veh", "radius": 16.0, "rate": 15.0}, "height": 9.0, "desc": "Builds vehicles. Repairs nearby vehicles."},
	"china_airfield": {"name": "Airfield", "faction": "china", "role": "airfield", "cost": 1000, "time": 30.0, "hp": 1500.0, "armor": "StructureArmor", "fp": Vector2i(11, 8),
		"power": -1, "vision": 40.0, "prereq": ["china_supply"], "produces": ["mig", "helix"], "upgrades": ["black_napalm"], "heal": {"cat": "air", "radius": 18.0, "rate": 15.0}, "pads": 4,
		"height": 9.0, "runway": true, "desc": "Builds aircraft. MiGs rearm and repair here (4 pads)."},
	"propaganda_center": {"name": "Propaganda Center", "faction": "china", "role": "tech", "cost": 2000, "time": 45.0, "hp": 1000.0, "armor": "StructureArmor", "fp": Vector2i(5, 5),
		"power": -2, "vision": 60.0, "prereq": ["china_factory"], "upgrades": ["nationalism", "subliminal_messaging"], "limit": 1,
		"heal": {"cat": "any", "radius": 22.0, "rate": 6.0}, "height": 9.0, "desc": "Unlocks the Overlord, Inferno Cannon, Nuke Cannon and Black Lotus. Broadcasts healing propaganda."},
	"speaker_tower": {"name": "Speaker Tower", "faction": "china", "role": "support", "cost": 500, "time": 15.0, "hp": 500.0, "armor": "StructureArmor", "fp": Vector2i(2, 2),
		"power": -1, "vision": 30.0, "prereq": ["propaganda_center"], "heal": {"cat": "any", "radius": 26.0, "rate": 8.0}, "height": 8.0, "desc": "Heals all units nearby."},
	"gattling_cannon": {"name": "Gattling Cannon", "faction": "china", "role": "defense", "cost": 1200, "time": 25.0, "hp": 1000.0, "armor": "BaseDefenseArmor", "fp": Vector2i(2, 2),
		"power": -3, "vision": 50.0, "prereq": ["china_reactor"], "weapons": ["gattling_cannon"], "turret": true, "height": 5.0, "desc": "Rapid-fire base defense (ground + air). Needs power."},
	"bunker": {"name": "Bunker", "faction": "china", "role": "defense", "cost": 400, "time": 10.0, "hp": 1000.0, "armor": "FireBaseArmor", "fp": Vector2i(3, 3),
		"power": 0, "vision": 40.0, "prereq": ["china_barracks"], "cargo": 5, "fire_ports": true, "height": 3.0, "desc": "Garrison up to 5 infantry - they fire from the slits."},
	"china_nuke": {"name": "Nuclear Missile", "faction": "china", "role": "sw", "cost": 5000, "time": 60.0, "hp": 4000.0, "armor": "StructureArmorTough", "fp": Vector2i(6, 6),
		"power": -10, "vision": 30.0, "prereq": ["propaganda_center"], "superweapon": 300.0, "sw_kind": "nuke", "height": 12.0, "desc": "Superweapon. A nuclear warhead every 5 minutes; the fallout lingers."},
	# ---- GLA (no power needed) ----
	"gla_cc": {"name": "Command Center", "faction": "gla", "role": "cc", "cost": 2000, "time": 45.0, "hp": 5000.0, "armor": "StructureArmorTough", "fp": Vector2i(6, 7),
		"power": 0, "vision": 60.0, "produces": ["worker"], "height": 12.0, "desc": "Trains Workers. Provides radar and General's powers."},
	"supply_stash": {"name": "Supply Stash", "faction": "gla", "role": "supply", "cost": 1500, "time": 10.0, "hp": 1500.0, "armor": "StructureArmor", "fp": Vector2i(4, 4),
		"power": 0, "vision": 40.0, "produces": ["worker"], "free_units": ["worker", "worker"], "height": 6.0, "desc": "Supply drop-off. Comes with two Workers."},
	"gla_barracks": {"name": "Barracks", "faction": "gla", "role": "barracks", "cost": 500, "time": 10.0, "hp": 800.0, "armor": "StructureArmor", "fp": Vector2i(5, 5),
		"power": 0, "vision": 40.0, "produces": ["rebel", "rpg_trooper", "terrorist", "jarmen_kell"], "upgrades": ["capture"],
		"heal": {"cat": "inf", "radius": 14.0, "rate": 8.0}, "height": 6.0, "desc": "Trains infantry. Heals nearby infantry."},
	"arms_dealer": {"name": "Arms Dealer", "faction": "gla", "role": "factory", "cost": 2000, "time": 15.0, "hp": 2000.0, "armor": "StructureArmor", "fp": Vector2i(6, 6),
		"power": 0, "vision": 40.0, "prereq": ["supply_stash"], "produces": ["technical", "scorpion", "quad_cannon", "rocket_buggy", "toxin_tractor", "marauder", "scud_launcher", "bomb_truck"],
		"upgrades": ["scorpion_rocket"], "heal": {"cat": "veh", "radius": 16.0, "rate": 15.0}, "height": 8.0, "desc": "Builds vehicles. Repairs nearby vehicles."},
	"palace": {"name": "Palace", "faction": "gla", "role": "tech", "cost": 2500, "time": 45.0, "hp": 3000.0, "armor": "StructureArmorTough", "fp": Vector2i(6, 6),
		"power": 0, "vision": 60.0, "prereq": ["arms_dealer"], "upgrades": ["ap_bullets", "ap_rockets"], "cargo": 5, "fire_ports": true, "limit": 1, "height": 10.0,
		"desc": "Unlocks the SCUD Launcher, Jarmen Kell and the SCUD Storm. Garrison up to 5 infantry behind its walls."},
	"black_market": {"name": "Black Market", "faction": "gla", "role": "income", "cost": 2500, "time": 45.0, "hp": 1000.0, "armor": "StructureArmor", "fp": Vector2i(4, 4),
		"power": 0, "vision": 30.0, "prereq": ["arms_dealer"], "income": {"amount": 20, "every": 5.0}, "upgrades": ["junk_repair", "anthrax_beta"], "height": 6.0,
		"desc": "$20 every 5 s. Sells the Junk Repair and Anthrax Beta upgrades."},
	"tunnel_network": {"name": "Tunnel Network", "faction": "gla", "role": "defense", "cost": 800, "time": 20.0, "hp": 1000.0, "armor": "BaseDefenseArmor", "fp": Vector2i(2, 2),
		"power": 0, "vision": 40.0, "prereq": ["gla_barracks"], "weapons": ["tunnel_gun"], "turret": true, "cargo": 10, "tunnel": true, "height": 3.0,
		"desc": "Units that enter come out of any of your tunnels (10 shared slots). Rocket turret on top."},
	"stinger_site": {"name": "Stinger Site", "faction": "gla", "role": "defense", "cost": 900, "time": 20.0, "hp": 900.0, "armor": "BaseDefenseArmor", "fp": Vector2i(3, 3),
		"power": 0, "vision": 50.0, "prereq": ["gla_barracks"], "weapons": ["stinger"], "turret": true, "height": 2.5, "desc": "Three Stinger soldiers behind sandbags (ground + air)."},
	"demo_trap": {"name": "Demo Trap", "faction": "gla", "role": "trap", "cost": 300, "time": 6.0, "hp": 100.0, "armor": "StructureArmor", "fp": Vector2i(1, 1),
		"power": 0, "vision": 12.0, "prereq": ["gla_barracks"], "trap": "demo_charge", "stealth": true, "height": 1.0, "desc": "Hidden explosive. Detonates when an enemy walks over it."},
	"scud_storm": {"name": "SCUD Storm", "faction": "gla", "role": "sw", "cost": 5000, "time": 60.0, "hp": 4000.0, "armor": "StructureArmorTough", "fp": Vector2i(6, 6),
		"power": 0, "vision": 30.0, "prereq": ["palace"], "superweapon": 240.0, "sw_kind": "scud", "height": 10.0, "desc": "Superweapon. Nine toxin SCUDs every 4 minutes."},
	"detention_camp": {"name": "Detention Camp", "cost": 2000, "time": 30.0, "hp": 1500.0, "armor": "StructureArmor", "fp": Vector2i(5, 4),
		"power": -2, "vision": 40.0, "prereq": ["barracks"], "intel": {"cd": 120.0, "dur": 12.0}, "height": 6.0,
		"desc": "Intelligence: every 2 minutes, reveals every enemy unit and structure for 12 s."},
	# ---- civilian (garrisonable) ----
	"civ_house": {"name": "House", "cost": 0, "time": 0.0, "hp": 1500.0, "armor": "StructureArmor", "fp": Vector2i(4, 4),
		"power": 0, "vision": 0.0, "neutral": true, "garrison": true, "cargo": 8, "fire_ports": true, "height": 7.0,
		"desc": "Civilian house. Garrison up to 8 infantry - they fire from the windows and are safe from everything but flame, toxins and microwaves."},
	"civ_shop": {"name": "Shop", "cost": 0, "time": 0.0, "hp": 1200.0, "armor": "StructureArmor", "fp": Vector2i(4, 3),
		"power": 0, "vision": 0.0, "neutral": true, "garrison": true, "cargo": 6, "fire_ports": true, "height": 5.0,
		"desc": "Civilian shop. Garrison up to 6 infantry."},
	"civ_tower": {"name": "Apartment Block", "cost": 0, "time": 0.0, "hp": 2200.0, "armor": "StructureArmor", "fp": Vector2i(3, 3),
		"power": 0, "vision": 0.0, "neutral": true, "garrison": true, "cargo": 10, "fire_ports": true, "height": 12.0,
		"desc": "Civilian apartment block. Garrison up to 10 infantry."},
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
	# ---- China ----
	"chain_guns": {"name": "Chain Guns", "cost": 1500, "time": 30.0, "desc": "Gattling weapons +25% damage."},
	"black_napalm": {"name": "Black Napalm", "cost": 2000, "time": 45.0, "desc": "Flame weapons +25% damage."},
	"uranium_shells": {"name": "Uranium Shells", "cost": 2500, "time": 45.0, "desc": "Battlemaster / Overlord +25% damage."},
	"nationalism": {"name": "Nationalism", "cost": 2000, "time": 45.0, "desc": "Horde bonus doubles (+50% damage)."},
	"subliminal_messaging": {"name": "Subliminal Messaging", "cost": 2000, "time": 30.0, "desc": "Propaganda heals 50% faster."},
	# ---- GLA ----
	"scorpion_rocket": {"name": "Scorpion Rocket", "cost": 1000, "time": 30.0, "desc": "Scorpions fire a rocket as well."},
	"ap_bullets": {"name": "AP Bullets", "cost": 2000, "time": 45.0, "desc": "Small-arms damage +25%."},
	"ap_rockets": {"name": "AP Rockets", "cost": 2000, "time": 45.0, "desc": "Rocket damage +25%."},
	"junk_repair": {"name": "Junk Repair", "cost": 1500, "time": 45.0, "desc": "Vehicles slowly repair themselves anywhere."},
	"anthrax_beta": {"name": "Anthrax Beta", "cost": 2500, "time": 45.0, "desc": "Toxin weapons +25% damage."},
	# ---- USA additions ----
	"sentry_guns": {"name": "Sentry Drone Guns", "cost": 800, "time": 30.0, "desc": "Sentry Drones get 20mm cannons."},
	"countermeasures": {"name": "Countermeasures", "cost": 1000, "time": 30.0, "desc": "Aircraft take 25% less missile damage (flares)."},
	"chemical_suits": {"name": "Chemical Suits", "cost": 1000, "time": 30.0, "desc": "Infantry take far less toxin and radiation damage."},
}

## General's powers. rank = rank required, points = promotion points cost.
## kind: unlock (permanent) or ability with cooldown (seconds) and radius.
const POWERS := {
	"paladin": {"name": "Paladin Tank", "faction": "usa", "rank": 1, "kind": "unlock", "desc": "Unlocks the Paladin at the War Factory."},
	"stealth_fighter": {"name": "Stealth Fighter", "faction": "usa", "rank": 1, "kind": "unlock", "desc": "Unlocks the Stealth Fighter at the Airfield."},
	"spy_satellite": {"name": "Spy Satellite", "faction": "usa", "rank": 1, "kind": "ability", "cd": 120.0, "radius": 60.0, "desc": "Reveals an area for 15 s."},
	"a10": {"name": "A-10 Warthog Strike", "faction": "usa", "rank": 1, "kind": "ability", "cd": 240.0, "radius": 10.0, "levels": 3, "desc": "A-10 Warthogs strafe the target with the GAU-8 and missiles. Each level adds a jet."},
	"pathfinder": {"name": "Pathfinder", "faction": "usa", "rank": 3, "kind": "unlock", "desc": "Unlocks the Pathfinder sniper at the Barracks."},
	"emergency_repair": {"name": "Emergency Repair", "faction": "all", "rank": 3, "kind": "ability", "cd": 120.0, "radius": 20.0, "desc": "Fully repairs vehicles in the area."},
	"paradrop": {"name": "Paradrop", "faction": "usa", "rank": 3, "kind": "ability", "cd": 240.0, "radius": 6.0, "desc": "Drops 4 Rangers at the target."},
	"fuel_air_bomb": {"name": "Fuel Air Bomb", "faction": "usa", "rank": 5, "kind": "ability", "cd": 300.0, "radius": 30.0, "auto": true, "desc": "Massive thermobaric strike."},
	# ---- China ----
	"cash_hack": {"name": "Cash Hack", "faction": "china", "rank": 1, "kind": "ability", "cd": 150.0, "radius": 20.0, "desc": "Steals $1000 from the owner of the targeted enemy structure."},
	"artillery_barrage": {"name": "Artillery Barrage", "faction": "china", "rank": 1, "kind": "ability", "cd": 180.0, "radius": 14.0, "levels": 3, "desc": "Shells rain on the area. Each level adds more shells."},
	"frenzy": {"name": "Frenzy", "faction": "china", "rank": 3, "kind": "ability", "cd": 180.0, "radius": 25.0, "desc": "Your units in the area deal +30% damage for 30 s."},
	"nuke_cannon": {"name": "Nuke Cannon", "faction": "china", "rank": 3, "kind": "unlock", "desc": "Unlocks the Nuke Cannon at the War Factory."},
	"carpet_bomb": {"name": "Carpet Bomb", "faction": "china", "rank": 5, "kind": "ability", "cd": 300.0, "radius": 30.0, "auto": true, "desc": "A bomber lays a line of heavy bombs across the target."},
	# ---- GLA ----
	"rebel_ambush": {"name": "Rebel Ambush", "faction": "gla", "rank": 1, "kind": "ability", "cd": 180.0, "radius": 8.0, "levels": 3, "desc": "Rebels appear at the target. Each level adds more rebels."},
	"marauder": {"name": "Marauder Tank", "faction": "gla", "rank": 1, "kind": "unlock", "desc": "Unlocks the Marauder at the Arms Dealer."},
	"cash_bounty": {"name": "Cash Bounty", "faction": "gla", "rank": 1, "kind": "unlock", "desc": "Every kill pays 10% of the victim's cost."},
	"anthrax_bomb": {"name": "Anthrax Bomb", "faction": "gla", "rank": 3, "kind": "ability", "cd": 240.0, "radius": 26.0, "desc": "A plane drops a toxin bomb; the cloud lingers."},
	"sneak_attack": {"name": "Sneak Attack", "faction": "gla", "rank": 5, "kind": "ability", "cd": 300.0, "radius": 6.0, "auto": true, "desc": "A tunnel entrance surfaces at the target, connected to your network."},
	"spy_drone": {"name": "Spy Drone", "faction": "usa", "rank": 1, "kind": "ability", "cd": 90.0, "radius": 20.0, "desc": "A stealthy drone loiters over the spot for 90 s, revealing the area and any stealth."},
	"spectre_gunship": {"name": "Spectre Gunship", "faction": "usa", "rank": 3, "kind": "ability", "cd": 240.0, "radius": 25.0, "desc": "An AC-130 circles the area for 20 s, hammering everything below with cannon and howitzer."},
}

## Playable sides. cc / builder = what you start with; the rest is what the bot looks for.
const FACTIONS := {
	"usa": {"name": "USA", "cc": "command_center", "builder": "dozer", "desc": "High-tech army: air power, lasers, Particle Cannon.",
		"build_order": ["power_plant", "barracks", "supply_center", "war_factory", "power_plant", "patriot", "supply_center", "war_factory", "airfield", "power_plant", "strategy_center", "patriot", "patriot", "firebase", "power_plant", "detention_camp", "supply_drop_zone", "particle_cannon", "power_plant"],
		"inf": ["ranger", "ranger", "missile_defender"], "veh": ["crusader", "crusader", "humvee", "tomahawk", "microwave_tank"], "air": ["raptor", "comanche", "aurora"],
		"upgrades": [["barracks", "capture"], ["war_factory", "tow"], ["power_plant", "control_rods"], ["strategy_center", "composite_armor"], ["airfield", "rocket_pods"], ["strategy_center", "advanced_training"], ["strategy_center", "supply_lines"], ["airfield", "laser_missiles"]],
		"powers": ["a10", "paladin", "spy_satellite", "spectre_gunship", "emergency_repair", "paradrop", "pathfinder", "stealth_fighter", "spy_drone"], "strike_powers": ["a10", "spectre_gunship", "fuel_air_bomb"]},
	"china": {"name": "China", "cc": "china_cc", "builder": "china_dozer", "desc": "Mass and firepower: hordes, flame, the Overlord and the Nuclear Missile.",
		"build_order": ["china_reactor", "china_barracks", "china_supply", "china_factory", "gattling_cannon", "china_supply", "bunker", "china_factory", "propaganda_center", "china_reactor", "china_airfield", "gattling_cannon", "speaker_tower", "gattling_cannon", "china_reactor", "china_nuke", "china_reactor"],
		"inf": ["red_guard", "red_guard", "red_guard", "tank_hunter", "tank_hunter", "hacker"], "veh": ["battlemaster", "battlemaster", "gattling_tank", "dragon_tank", "overlord", "inferno_cannon"], "air": ["mig", "mig", "helix"],
		"upgrades": [["china_barracks", "capture"], ["china_factory", "chain_guns"], ["propaganda_center", "nationalism"], ["china_reactor", "uranium_shells"], ["china_airfield", "black_napalm"], ["propaganda_center", "subliminal_messaging"]],
		"powers": ["artillery_barrage", "cash_hack", "nuke_cannon", "emergency_repair", "frenzy"], "strike_powers": ["artillery_barrage", "carpet_bomb"]},
	"gla": {"name": "GLA", "cc": "gla_cc", "builder": "worker", "desc": "Guerrillas: no power needed, tunnels, toxins, suicide bombers and the SCUD Storm.",
		"build_order": ["gla_barracks", "supply_stash", "arms_dealer", "tunnel_network", "supply_stash", "stinger_site", "arms_dealer", "palace", "black_market", "tunnel_network", "stinger_site", "demo_trap", "scud_storm", "stinger_site"],
		"inf": ["rebel", "rebel", "rpg_trooper", "terrorist"], "veh": ["scorpion", "scorpion", "technical", "quad_cannon", "rocket_buggy", "toxin_tractor", "marauder", "scud_launcher"], "air": [],
		"upgrades": [["gla_barracks", "capture"], ["arms_dealer", "scorpion_rocket"], ["palace", "ap_bullets"], ["palace", "ap_rockets"], ["black_market", "junk_repair"], ["black_market", "anthrax_beta"]],
		"powers": ["rebel_ambush", "marauder", "cash_bounty", "emergency_repair", "anthrax_bomb"], "strike_powers": ["rebel_ambush", "anthrax_bomb", "sneak_attack"]},
}
const FACTION_ORDER := ["usa", "china", "gla"]

static func faction_of(type: String) -> String:
	var d := def(type)
	if d.get("neutral", false):
		return ""
	return str(d.get("faction", "usa"))

## Role of a structure (cc / power / barracks / supply / factory / airfield / tech / defense / sw / income / support / trap).
static func role_of(type: String) -> String:
	var d := def(type)
	if d.has("role"):
		return str(d["role"])
	match type:
		"command_center": return "cc"
		"power_plant": return "power"
		"barracks": return "barracks"
		"supply_center": return "supply"
		"war_factory": return "factory"
		"airfield": return "airfield"
		"strategy_center": return "tech"
		"patriot", "firebase": return "defense"
		"particle_cannon": return "sw"
		"supply_drop_zone": return "income"
		"detention_camp": return "support"
	return ""

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
