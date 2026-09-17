# Frontline — 1v1 RTS (Generals-style)

Top-down RTS built in Godot 4.7, modelled on Command & Conquer Generals: Zero Hour
(USA faction, mirror match). Server-authoritative multiplayer from day one:
the host runs the simulation, both players send orders, and each client only
receives what its own units can see (real fog of war, not client-side hiding).

## Run it
1. Godot 4.7.2 (the exe you already have from Incremental PvE).
2. Project Manager → Import → this folder → `project.godot` → Import & Edit.
3. FIRST OPEN IS SLOW: Godot imports the Synty pack (~7,000 files). Let it finish.
4. F5 to play. **Host game** to host (port 7788), **Join game** with the host's IP.
   Hosting alone lets you **Start solo (sandbox)** to practice — F1 gives +$10,000 there.

Testing with a friend over the internet: the host forwards UDP port 7788 (or you both
use a VPN like Tailscale/ZeroTier, or the same LAN). Same build on both sides — the
host rejects mismatched versions.

Two copies on one PC for a quick check: run one, Host; run another, Join 127.0.0.1.

## Controls
| | |
|---|---|
| Left-drag / click | select (double-click = all of that type on screen, Shift adds). Buildings are picked by their whole model. |
| Right-click | move / attack / repair (dozer) / gather (Chinook) / capture derrick (Ranger + upgrade) — Shift queues |
| Ctrl+right-click or X | force attack: fire at a spot, a neutral structure or one of your own |
| A + click | attack-move |
| G + click | guard an area (ring shown while placing; G twice = guard here). Aircraft loiter over it and fly home to rearm, then come back. |
| S | stop |
| Placing a building | click to place; hold the left button and drag to rotate it freely before releasing (like Generals) |
| N | select the next Dozer · B / F / I / C / Y: Barracks / War Factory / Airfield / Command Center / Supply Center |
| Ctrl+1..9 / 1..9 | assign / recall control group (press twice to jump there) |
| H | jump to Command Center · Space: jump to last attack alert |
| Arrows / edge / middle-drag | scroll · wheel: zoom · Q / E: rotate camera |
| Esc | cancel placement / deselect |
| Right-click with a factory selected | set its rally point |
| F1 | +$10,000 (solo / debug only) |

## Menu
Host → "Start vs AI" fights the built-in AI general (build order, waves, defence, powers, superweapon).
Untick "Add AI opponent" for an empty sandbox. A second player joining replaces the AI.

## Audio
`audio/sfx` — 50 CC0 / CC-BY effects from Freesound (`audio/sfx/CREDITS.md`, re-fetch with `tools/fetch_sfx.py`).
`audio/voice` — 234 lines: 15 unit voices + EVA, generated with ElevenLabs (`tools/gen_voices.py`, radio filter via ffmpeg).
`audio/music` — 12 Kevin MacLeod tracks, CC BY 4.0 (`audio/music/CREDITS.md`; attribution required if you ship).
Mixer buses: Master / SFX / Voice / Music (see `Audio.set_volumes`).

## What's in (M2)
- Aircraft: jets taxi and take off along the runway, fly with a turn radius, make attack passes, loiter in circles when guarding or homeless, land on their pad to rearm. Sell or lose the Airfield and they look for another one, else circle and slowly break up.
- Helicopters bank and pitch with velocity, rotors spin, wheels spin, vehicles leave tyre tracks, infantry run/fire/die animations.
- Icons for every unit, building, upgrade and power are rendered at runtime from the models.
- Supply Docks are crate stacks that empty as you harvest; Chinooks hover 3 s to unload and "+$600" floats over the Supply Center.
- Unpowered buildings go dark with a blue pulse. Damaged buildings smoke.
- Mountain ridges and rocks block movement exactly where the art is.
- AI opponent, guard areas, force attack, free building rotation, explicit Capture button, hotkeys, square minimap view.

## What's in (M1)
- Economy: Supply Docks ($30k each), Chinooks ($600/load), Oil Derricks (capture, $200/12s + $1000), Supply Drop Zone ($1500/2min). Start $10,000.
- Base building via Dozer with grid placement, construction progress, repair, sell (50%), power (Cold Fusion Reactor, low power slows production & disables Patriots / superweapon).
- Structures: Command Center, Reactor, Barracks, Supply Center, War Factory, Airfield (4 pads, jets rearm), Strategy Center, Supply Drop Zone, Patriot, Firebase, Particle Cannon.
- Units: Dozer, Ranger, Missile Defender, Pathfinder, Col. Burton, Humvee (+TOW), Crusader, Paladin, Tomahawk, Ambulance, Avenger, Chinook, Comanche (+Rocket Pods), Raptor, Stealth Fighter, Aurora.
- Upgrades: Control Rods, Capture Building, Supply Lines, TOW, Rocket Pods, Laser Missiles, Composite Armor, Advanced Training.
- General's promotion: ranks from XP, points to buy Paladin / Stealth Fighter / Pathfinder unlocks, Spy Satellite, A-10 Strike (3 levels), Emergency Repair, Paradrop, Fuel Air Bomb (rank 5).
- Superweapon: Particle Cannon with shared countdown, steerable beam.
- Veterancy (veteran/elite/heroic), crushing infantry with tanks, splash damage, real Zero Hour damage/armor tables.
- Fog of war (shroud + fog), minimap with alerts, ghosted enemy buildings.
- Victory: destroy every enemy structure.

Numbers come from the Zero Hour INI files (Weapon.ini / Armor.ini / Locomotor.ini / America*.ini),
scaled to metres at 1 Generals unit = 0.2 m. See `game/data.gd`.

## Layout
```
game/main.gd            menu, lobby, host/join
game/session.gd         RPC hub (commands up, spawns/snapshots/fog/events down)
game/data.gd            all unit/building/weapon/upgrade/power definitions
game/sim/world.gd       the simulation (host only)
game/sim/pathgrid.gd    A* grid pathing, footprints
game/sim/vision.gd      per-player fog grids
game/sim/map_gen.gd     the 1v1 map "Desert Divide"
game/client/*.gd        puppets, camera, controller, HUD, FX, terrain, fog rendering
Assets/                 Synty PolygonMilitary (git-ignored, licensed)
mixamo/                 rifle idle/run/fire/death clips for infantry
```

## Headless smoke test (what Claude runs before shipping)
```
godot --headless --path . -- --host --solo --autostart --test=smoke --exit_after=240
# two peers:
godot --headless --path . -- --host --autostart --test=smoke --exit_after=330 &
godot --headless --path . -- --join=127.0.0.1 --test=smoke --exit_after=320
```
`--debug` prints unit states from the sim every 3 s; `--screenshot=DIR` saves a frame every 8 s.
