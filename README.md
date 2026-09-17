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
| G | guard: press once then click a spot (or a unit) to guard there; press G twice to guard where they stand. Aircraft loiter over it, rearm and come back |
| S | stop |
| Placing a building | click to place; hold the left button and drag to rotate it freely before releasing (like Generals) |
| N | select the next Dozer · B / F / I / C / Y: Barracks / War Factory / Airfield / Command Center / Supply Center |
| Ctrl+1..9 / 1..9 | assign / recall control group (press twice to jump there) |
| H | jump to Command Center · Space: jump to last attack alert |
| Arrows / edge / middle-drag | scroll · wheel: zoom · Q / E: rotate camera |
| Esc / F10 | cancel placement / deselect · with nothing to cancel: pause menu (solo/AI games actually pause; volume sliders, edge-scroll toggle, surrender) |
| Right-click with a factory selected | set its rally point |
| F1 | +$10,000 (solo / debug only) |

## Lobby
Host a game and set it up before starting: **map** (Desert Divide / Frozen Front / Green Valley),
**AI opponents** (0-3) and **difficulty** (Easy: slow, small waves, no powers for 8 min · Medium ·
Hard: bigger waves, earlier powers, +$150 every 10 s), **starting cash**, **superweapons** on/off,
**kick** buttons next to joined players, and a **team** picker per slot (humans and AI). Up to 4 players + AI;
players start in the four corners. Teammates share vision, can't be attacked without force-fire (X / Ctrl+RMB —
friendly fire only when you mean it), can capture/repair each other's stuff, and win or lose together.
Everyone starts at rank 1 with one promotion point (as in Generals) — that's how an AI can have an
A-10 strike early; on Easy/Medium it now waits several minutes before using any power.

## Audio
`audio/sfx` — 50 CC0 / CC-BY effects from Freesound (`audio/sfx/CREDITS.md`, re-fetch with `tools/fetch_sfx.py`).
`audio/voice` — 234 lines: 15 unit voices + EVA, generated with ElevenLabs (`tools/gen_voices.py`, radio filter via ffmpeg).
`audio/music` — 12 Kevin MacLeod tracks, CC BY 4.0 (`audio/music/CREDITS.md`; attribution required if you ship).
Mixer buses: Master / SFX / Voice / Music (see `Audio.set_volumes`).

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
# two peers:
godot --headless --path . -- --host --autostart --test=smoke --exit_after=330 &
godot --headless --path . -- --join=127.0.0.1 --test=smoke --exit_after=320
```
`--debug` prints unit states from the sim every 3 s; `--screenshot=DIR` saves a frame every 8 s.
