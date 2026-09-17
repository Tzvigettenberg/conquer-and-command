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
| G | guard area: press G, then click a spot — or hold and drag to size the circle (12–90 m). G twice = guard right here. Aircraft loiter over it, rearm and come back |
| S | stop |
| Placing a building | click to place; hold the left button and drag to rotate it freely before releasing (like Generals). The yellow arrow on the ghost shows the front (where units come out) |
| N | select the next Dozer · B / F / I / C / Y: Barracks / War Factory / Airfield / Command Center / Supply Center |
| Ctrl+1..9 / 1..9 | assign / recall control group (press twice to jump there) |
| H | jump to Command Center · Space: jump to last attack alert |
| Arrows / edge / right-drag | scroll · wheel or numpad 8 / 2: zoom · middle-drag, Q / E or numpad 4 / 6: rotate (middle-drag up/down tilts) · numpad 5: reset |
| Ctrl+B | place a beacon your team sees (minimap ping + pillar; Space jumps to it) |
| Enter / Backspace | chat with everyone / with allies |
| Side buttons (left of the info panel) | menu · next idle Dozer · promotion · beacon · chat — the Generals control-bar set |
| Esc / F10 | cancel placement / deselect · with nothing to cancel: pause menu (solo/AI games actually pause; volume sliders, edge-scroll toggle, surrender) |
| Right-click with a factory selected | set its rally point |
| F1 | +$10,000 (solo / debug only) |

## Lobby
Host a game and set it up before starting. Every map has a fixed number of **spawn slots** (Desert Divide 2,
Sand Sea 4, Frozen Front 4, Green Valley 6). Each slot is **Open / Closed / Easy AI / Medium AI / Hard AI** —
add or remove opponents per slot, mix difficulties freely. Humans take the first open slot when they join
and can **click a spawn point on the map preview** to move there; every slot has a **team** picker.
Other options: starting cash, superweapons on/off, kick buttons. Teammates share vision, can't be attacked
without force-fire (X / Ctrl+RMB), can capture/repair each other's stuff, and win or lose together.
Easy: slow, small waves, no powers for 8 min · Medium · Hard: bigger waves, earlier powers, +$150 every 10 s.
Everyone starts at rank 1 with one promotion point (as in Generals).

## Audio
`audio/sfx` — 50 CC0 / CC-BY effects from Freesound (`audio/sfx/CREDITS.md`, re-fetch with `tools/fetch_sfx.py`).
`audio/voice` — 234 lines: 15 unit voices + EVA, generated with ElevenLabs (`tools/gen_voices.py`, radio filter via ffmpeg).
`audio/music` — 14 Kevin MacLeod tracks (menu, game, victory, defeat), CC BY 4.0 (`audio/music/CREDITS.md`; attribution required if you ship).
Mixer buses: Master / SFX / Voice / Music (see `Audio.set_volumes`).

## What's in (M6)
- Our own low-poly unit models for everything (tanks, Humvee, Avenger, Tomahawk, Ambulance, Dozer, Comanche, Chinook, Raptor, Stealth Fighter, Aurora, infantry with walking limbs) — no Synty needed; wrecks are charred copies.
- Airfield remake: four hangars, taxiway, runway lights, helipad and tower. Jets roll out of the hangar, taxi to the runway, take off, and taxi back in after landing. Helicopters lift off from the helipad.
- War Factory door slides open with flashing lights when a vehicle rolls out.
- Unit AI: parked friends step aside for movers (no more dozer stuck behind a tank); guard radius = the unit's own weapon range; idle Dozers repair damaged structures nearby; units that fire at you show up even outside your vision (muzzle flash reveal).
- Avenger and Paladin laser point-defence: incoming missiles and shells are burned out of the air (Avenger every 0.35 s, Paladin every 1.5 s — salvos get through). Comanche gun always works, only the rockets reload (12 s).
- Splash damage on missiles, shells and bombs (inner / outer radius); the FAB is a proper fireball.
- Strike markers on the ground for A-10 / paradrop / fuel-air bomb, a visible bomb drop, much bigger explosions with debris and scorch marks, subtle contrails.
- Fog of war is drawn on the ground only (no floating cloud layer), lighter dimming; unexplored = black.
- Particle Cannon: continuous beam from the sky plus an uplink from the spire, 10 s, glowing orb on the spire when charged; button lives in the side panel with the general's powers (no label).
- Cursors change with what you're doing: attack crosshair, force-fire, guard shield, build, beacon, capture, rally, power star, superweapon reticle, repair.
- Construction sites: scaffold, progress bar and a flashing UNFINISHED warning when no Dozer is on it.
- Control rods: reactor steam turns blue; research is no longer slowed by low power (and each reactor's button reflects its own research).
- Captures fade out when the capturer leaves; airfield-full jets are greyed out; Medium AI is easier (24-unit cap, 5-minute first wave, slower growth); Easy easier still.
- Sound: listener sits where you're looking (everything was too quiet), engines rev when vehicles set off, victory / defeat music, all weapons mapped.
- Main menu plays over a living shell map (base, tank column, patrol helicopter, circling jet).

## What's in (M5)
- Lobby rework: per-slot AI with its own difficulty, map preview with clickable spawn points, four maps with 2 / 4 / 4 / 6 slots (6 team colours).
- Real raised terrain: mountain ridges are a heightmap mesh (rock / snow-cap colouring, fog dims it too) instead of props; they sit exactly on the blocked cells so nothing walks into a slope.
- Generals controls: right-drag scrolls, middle-drag rotates and tilts, numpad camera keys; side buttons for menu / idle Dozer / promotion / beacon / chat; team beacons (Ctrl+B); chat (Enter / Backspace).
- Strategy Center battle plans (Zero Hour): Bombardment (+20% ground damage, roof howitzer), Hold the Line (−10% damage taken, reinforced building), Search and Destroy (+20% range and vision, stealth detection). 12 s to switch, one plan active, visible to everyone; the model shows the cannon / sandbags / scanner mast.
- Smarter units: idle units near an attacked friend (own or allied) join in, parked jets and helicopters scramble when their base is hit, group attack orders fan out around the target, and a unit stuck behind friends picks another angle.
- Production: 9-slot queue strip with the unit icon filling up as it builds (click to cancel), research shown beside it; the strip never overflows.
- Upgrade visuals: TOW pod on Humvees, armour skirts on Crusader/Paladin, rocket pods, laser-missile tips, glowing control rods, extra crates, flag, etc.
- Placement shows a facing arrow; guard radius is drag-sized (and bigger by default); surrender in the pause menu; smaller Supply Center awning.

## What's in (M4)
- Pause menu (Esc / F10) with Master / SFX / Voice / Music sliders and an edge-scroll toggle, saved to `user://settings.cfg`; solo and vs-AI games freeze while it's open, multiplayer keeps running.
- Post-game report: units built / lost / killed, structures built / lost / destroyed, cash earned, captures, rank — for every player.
- Teams: lobby team picker; allied vision, no accidental friendly fire (force-fire still works), team victory.
- Selling "unbuilds" the structure over half its build time; the refund only lands when it finishes — destroyed mid-sale pays nothing.
- Enemy structures you're shelling from outside your vision now show their real health (any seen corner of the footprint counts, and ghosts refresh on damage).
- Guard works on aircraft and every ground unit (button or G then click).
- Command bar rebuilt so prices and names never clip (three rows fit, requirements on their own red line); promotion screen is centred, sized to the screen and scrolls if needed.
- Completion flash matches the rotated footprint of the finished building.

## What's in (M3)
- All structures are new procedural low-poly models sized to their footprints and painted with the owner's colour: Command Center (radar dish), Reactor (dome + steaming stacks), Barracks, Supply Center (H pad + crane), War Factory (hangar door, roof fan), Airfield (real runway with lights, tower, four pads), Strategy Center (dish + antenna farm), Drop Zone (beacon), Patriot (rotating 4-tube launcher), Firebase (sandbag ring + traversing howitzer), Particle Cannon (spinning focus rings), Oil Derrick (nodding pump-jack), Supply Dock (crate stacks). Every model has an idle animation. Dozers got a blade.
- Units carry a team-colour tint; tank turrets traverse at a realistic rate and settle back forward; units shot from beyond their reach go and find the shooter.
- Missiles leave smoke trails, jets leave contrails, machine-gun and sniper fire shows tracers; jets nose-dive and helicopters spin in when killed, then explode on the ground.
- A-10 strike is a gun run followed by missiles, with tracers from the jets.
- Ammo pips over aircraft and Comanches; unit-lost EVA calls; capture flashes the capturing player's colour with a beeping loop.
- Tech-tree style promotion screen (icons, unlocked / available / locked, closes on click-away); build buttons print the missing requirement in red; an invalid spot no longer closes placement; ghost buildings are readable.
- Three map themes, 4-player corner layouts, lobby options, AI difficulty.

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
godot --headless --path . -- --host --autostart --ai=2 --ai_level=hard --map=grass6 --exit_after=400   # AI game
# two peers:
godot --headless --path . -- --host --autostart --test=smoke --exit_after=330 &
godot --headless --path . -- --join=127.0.0.1 --test=smoke --exit_after=320
```
`--simdebug` prints unit states from the sim every 3 s; `--screenshot=DIR` saves a frame every 8 s; `--reveal` shows the whole map; `--look=x,y` starts the camera there; `--map=desert2|desert4|snow4|grass6`, `--teams=0,1,1`.
