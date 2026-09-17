# Conquer & Command: Zero Budget

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

### Shareable build (no Godot needed)
`build/ConquerAndCommand.exe` is a single-file Windows build (everything embedded, ~230 MB; `build/ConquerAndCommand_ZeroBudget_v0.2.0_win64.zip` ~90 MB). Send the zip to a
friend, they double-click it. Rebuild after code changes with the editor (Project → Export → Windows Desktop,
templates installed once via Editor → Manage Export Templates) or headless:
```
godot --headless --path . --export-release "Windows Desktop" build/ConquerAndCommand.exe
```
Both sides must run the same version (`GAME_VERSION` in `game/main.gd`); the host rejects mismatches.
Internet play: the host forwards **UDP 7788** on their router and shares their public IP, or everybody joins a
free mesh VPN (Tailscale / ZeroTier / Radmin) and uses the VPN IP - no router setup at all.

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

## Factions
Pick a side per slot in the lobby (Random / USA / China / GLA); AI slots get one too, so any matchup works.

**USA** - the original roster: Dozer, Rangers, Missile Defenders, Pathfinder, Colonel Burton; Humvee, Crusader, Paladin, Tomahawk,
Ambulance, Avenger; Chinook, Comanche, Raptor, Stealth Fighter, Aurora. Strategy Center battle plans, Particle Cannon.

**China** - numbers and firepower. Nuclear Reactor (+10 power), Barracks (Red Guards come in pairs, Tank Hunters, Hackers that
earn cash while idle, Black Lotus who captures from a distance), Supply Center with ground Supply Trucks ($300 a trip), War Factory
(Battlemaster, Gattling Tank, Dragon flame tank, Troop Crawler packed with 8 Red Guards, Inferno Cannon, Overlord, Nuke Cannon),
Airfield (MiG napalm jets, Helix transport gunship), Propaganda Center (heals nearby, unlocks the heavies), Speaker Towers,
Gattling Cannon and Bunker (garrison 5) defenses, and the **Nuclear Missile** superweapon (5 min; fallout lingers).
Mechanics: **horde bonus** (5+ Red Guards / Tank Hunters / Battlemasters together deal +25%, +50% with Nationalism),
upgrades Chain Guns, Black Napalm, Uranium Shells, Subliminal Messaging; powers Cash Hack, Artillery Barrage, Frenzy, Nuke Cannon,
Carpet Bomb (rank 5).

**GLA** - guerrillas that **need no power at all**. Workers build *and* haul supplies ($75 a trip), Barracks (Rebels, RPG Troopers,
Terrorists who run in and explode, Jarmen Kell), Supply Stash, Arms Dealer (Technical with 5 fire ports, Scorpion, Quad Cannon,
Rocket Buggy, Toxin Tractor, Marauder, SCUD Launcher, Bomb Truck), Palace (garrison 5, unlocks SCUDs), Black Market (steady income
plus Junk Repair and Anthrax Beta), **Tunnel Network** (walk units in at one tunnel, unload them from any other - 10 shared slots,
rocket turret on top), Stinger Site, hidden Demo Traps, and the **SCUD Storm** (nine toxin warheads every 4 min).
Powers: Rebel Ambush, Cash Bounty, Marauder, Anthrax Bomb, Sneak Attack (a tunnel entrance surfaces anywhere, rank 5).

Toxin and radiation leave lingering fields that keep hurting whatever stands in them (toxin melts infantry; radiation hurts everything).

## Lobby
Host a game and set it up before starting. Every map has a fixed number of **spawn slots** (Desert Divide 2,
Sand Sea 4, Frozen Front 4, Green Valley 6). Each slot is **Open / Closed / Easy AI / Medium AI / Hard AI** —
add or remove opponents per slot, mix difficulties freely. Humans take the first open slot when they join
and can **click a spawn point on the map preview** to move there; every slot has a **team** picker.
Other options: starting cash, superweapons on/off, kick buttons. Teammates share vision, can't be attacked
without force-fire (X / Ctrl+RMB), can capture/repair each other's stuff, and win or lose together.
Easy: slow, small waves, no powers for 8 min · Medium · Hard: bigger waves, earlier powers, +$150 every 10 s.
Everyone starts at rank 1 with one promotion point (as in Generals).
**Observer**: press *Observe* next to your name to step out of the match and watch it - the whole map is revealed,
every unit is replicated, and a scoreboard shows each general's cash, units, structures, kills and battle plan.
Set every slot to AI and hit *Watch the AIs fight* for an AI-vs-AI match; a late joiner with no open slot
becomes an observer automatically (*Play* takes them back into a slot). Observers can chat but never command.

## Audio
`audio/sfx` — 50 CC0 / CC-BY effects from Freesound (`audio/sfx/CREDITS.md`, re-fetch with `tools/fetch_sfx.py`).
`audio/voice` — 234 lines: 15 unit voices + EVA, generated with ElevenLabs (`tools/gen_voices.py`, radio filter via ffmpeg).
`audio/music` — 14 Kevin MacLeod tracks (menu, game, victory, defeat), CC BY 4.0 (`audio/music/CREDITS.md`; attribution required if you ship).
Mixer buses: Master / SFX / Voice / Music (see `Audio.set_volumes`).

## What's in (M9) - v0.3.0
- **Open games list**: Host names a room (password optional, "show in the list" toggle); the menu lists live rooms of the same
  version and joins with a click (password prompt for locked rooms). Client in `game/room_list.gd`, server in
  `tools/room-api/` - one Cloudflare Worker with **no database**: a room exists only while its host heartbeats (every 10 s,
  dropped after 45 s), the host's address is read from the request and only handed back by `/join` after the password check.
  Live at `https://cc-rooms.zerobudget.workers.dev` (deploy with `cd tools/room-api && wrangler deploy`, credentials in
  `~/.frontline/keys.env`). `RoomList.SERVICE` empty = the feature is off and the menu hides the room fields and says so. Hosting still needs UDP 7788 reachable (port forward /
  mesh VPN); LAN just works.
- **GLA tech tree (Zero Hour)**: Palace gates Black Market, Angry Mob, Jarmen Kell, Rocket Buggy, Bomb Truck, SCUD
  Launcher (+ SCUD promotion) and SCUD Storm; Demo Trap needs the Arms Dealer. Upgrades: Arm the Mob, Camouflage, Toxin
  Shells, Anthrax Beta, Fortified Structure (Palace); AP Bullets/Rockets, Buggy Ammo, Junk Repair, Worker Shoes (Black
  Market); Camo Netting per tunnel / stinger site. Finishing an upgrade plays a unit line (`audio/voice/upgrades`).
- **Angry Mob**: a crowd unit (pistols + molotovs, AK-47s with Arm the Mob), regrows when left alone, can't board anything.
- **Workers**: $75 a trip, bare chest + loincloth + turban, crate on the back while carrying; Zero Hour-style lines.
  Loaded Supply Trucks show their crates, Chinooks fly home with a cargo net.
- **Tunnels**: units vanish underground and come out of any tunnel (or one at a time), tunnels heal occupants, machine-gun
  turret. Every transport / tunnel / garrison lists its passengers as icons in the info panel - click one to let it out.
- **Crowds**: work crews (gathering, capturing, boarding, building) squeeze through each other and approach a building from
  different sides; attackers slide along the firing line so a group fans out; one general captures a building at a time,
  3 s lockout after a capture, the losers give up (bots skip contested derricks).
- **Captured buildings** produce their own faction's units; a captured Dozer builds its faction's structures (your
  promotions / tech still apply).
- Humvee keeps the machine gun alongside TOW (which is now really gated by the upgrade); vehicle noses point forward
  (the prism was flipped); engine / rotor loops re-fetched and normalised so vehicles are audible near the camera;
  X scatters outward from the group; sold buildings refuse new orders and the panel shows SELLING / CANCELLED.
- Release pipeline: `tools/release.py` tags, GitHub Actions builds the Windows zip (see "Website and releases").

## What's in (M8) - "Zero Budget"
- Renamed: **Conquer & Command: Zero Budget** (v0.2.0). Zero Hour-style front end (gunmetal panels, brass rules, amber titles, angled buttons).
- Generals hotkeys: Q / W / E select combat units / aircraft / same type on screen (tap twice for the whole map), X scatters, Ctrl+Up next builder, camera rotates with [ ], numpad or middle-drag (Q/E no longer rotate). A + minimap click (or a double-click on the minimap) attack-moves there. Whole promotion cards are clickable.
- USA additions: escort drones bought per vehicle (Scout $100 detects stealth, Battle $200 gun + repairs, Hellfire $500 missiles - one per vehicle, buy again if it dies), Sentry Drone, Microwave Tank (cooks garrisons), Detention Camp (Intelligence reveals every enemy for 12 s), Spy Drone and Spectre Gunship powers, Countermeasures / Chemical Suits / Sentry Drone Guns upgrades. A-10 Warthogs are actual Warthogs now.
- Garrisonable civilian buildings on every map (village in the middle, farmsteads on each approach): walk infantry in, they fire from the windows and are immune to everything except flame, toxins, microwaves and radiation, which reach inside. Enemies auto-target buildings with a hostile garrison; a flag shows who holds it.
- Sim fixes: selling keeps the building standing for a few seconds (SELLING label) instead of un-building it; units on a job no longer give up when boxed in and shuffle sideways to un-stick; garrisoning a Firebase / Bunker works (units close the last metre); unlocks show up on open command cards immediately; jets attack-move properly (fly there, circle 15 s hunting, then home) so AI planes stop taxiing in circles; Aurora is untouchable and supersonic on the way in, slow and vulnerable after the drop; tanks charge and crush nearby infantry; Chinooks winch supplies from a hover (only AA can touch them) and only land to pick up passengers; strikes and superweapons reveal their area to the owner while they happen; the particle beam is steered by clicks (right-click leaves it) and crawls slowly.
- Client: beams reach from the heavens and back up from the spire; particle cannon rings light up one by one when charged (nuke / SCUD pads get beacons); stealth pulses in and out of view; structures out of sight go dim and frozen with no bars or animation; trees, rocks and ruins stay hidden under unexplored shroud; brighter selection rings with corner brackets, and a drag box lights up what it will grab; explosions scale with the hit (infantry rockets are puffs now); no more team-blue windows, no slabs under rocks; the last Synty remnants are gone (own rubble wrecks); a proper thunk when units board; every click on a unit answers with a voice line.

## What's in (M7)
- Two new factions, China and GLA, with full Zero Hour-style rosters (26 units, 21 structures, 10 upgrades, 10 general's powers, two superweapons), each with its own procedural models, a faction picker per lobby slot (humans and AIs, Random by default), faction-aware bots with their own build orders, and per-faction mechanics: China hordes, hackers, paired Red Guards, packed Troop Crawlers, ground supply trucks, propaganda healing; GLA no-power base, worker builders/haulers, suicide units, tunnel network pooling, demo traps, black market income, junk repair, cash bounty.
- New sim systems: lingering damage zones (radiation / toxin), suicide weapons, ballistic superweapons (nuke, SCUD storm), flame weapons, garrison unload fix, transports that spawn loaded.
- New FX: flamethrowers / toxin sprays, nuke mushroom cloud with screen shake, silo launches and SCUD salvos in flight, toxin / radiation fields, carpet-bomb and anthrax flyovers, artillery barrage.
- `--faction=x --ai_faction=a,b,c` for headless runs; `--showcase=units|buildings --showcase_faction=x` renders a model gallery.

## What's in (M6.2)
- Observer mode: humans can step out of the slot list and watch (AI vs AI works with nobody playing). Observers get every entity, no fog, all events and a live scoreboard; commands from observers are dropped by the sim. Lobby: Observe / Play buttons, "Watching:" on the map preview, full lobby → auto-observer.
- Composite Armor is stat-only again (no bolt-on plates).
- Fixed a particle burst being added to the FX tree twice (console spam during big fights).
- `export_presets.cfg` + `build/ConquerAndCommand.exe`: single-file Windows build to share with friends.

## What's in (M6.1)
- Transports (Generals rules): Humvee carries 5 infantry who fire from inside; Chinook has 8 slots (infantry 1, vehicles 3) and lands to load; Firebase garrisons 4 infantry who fire from the sandbags (you see them). Right-click the transport with units selected to load, U / "Unload" to let them out.
- Linked Patriots: batteries within 40 m share targets (cyan data-link lines); a designated battery gets +20% reach. Structures give up on targets that stay out of range.
- No invisible attackers: anything shooting at you or attacking your stuff stays visible until it breaks off.
- Economy: Chinooks are slower, land to load (one box per 1.3 s) and unload (4.5 s), and only one uses a Supply Center pad at a time - the rest hold off to the side.
- Particle Cannon: each cannon has its own charge and button; the reticle cursor stays while you steer the beam, click to lock the beam in place.
- Supply Drop Zone: a cargo plane flies over and parachutes the crate; the cash lands when the crate does.
- Placing a structure moves your own units out of the footprint instead of refusing; enemies still block.
- Strategy Center max 1 (plans don't stack). Upgrades queue at a building (up to 3 shown, "queued" on the button).
- Props: our own rocks, trees, cacti, dunes and ruined houses sized exactly to the cells they block (the Synty dunes were unscaled and never blocked anything).
- FX: particle smoke trails on missiles, fireball + sparks + smoke + dust explosions, contrail emitters on jets, smaller aircraft (Raptor 6.5 m), jets with gear that retracts, afterburners and missiles that disappear as ammo is spent, Comanche chin gun and rocket pods; infantry in team-colour vests and helmets; greyed-out buttons with the cash shortfall in red.

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

## Website and releases
The site lives in `site/src` (one page: home + Factions / Play with friends / Screenshots / Controls / What's new, switched
by `#hash` so it is one file and no build step). `python3 tools/build_site.py` wraps it in a standalone document and copies
the images and the shell-map clip into `site/dist`, which is what gets published:

* **https://tzvigettenberg.github.io/conquer-and-command/** - GitHub Pages, served from the `gh-pages` branch.
  Publish an update with `python3 tools/publish_site.py` (builds, then force-pushes `site/dist` to that branch).
* A custom domain is one file away if we ever buy one: put it in `site/src/CNAME` and point the DNS at GitHub.

Its Download button points at the GitHub Releases *latest* asset, so it never needs editing:
```
https://github.com/<GITHUB_REPO>/releases/latest/download/ConquerAndCommand_ZeroBudget_win64.zip
```
Shipping an update = bump `GAME_VERSION` in `game/main.gd`, commit, then:
```
python3 tools/release.py             # pushes main + tag vGAME_VERSION
```
GitHub Actions (`.github/workflows/release.yml`) then exports the Windows build with Godot 4.7.2 and attaches
`ConquerAndCommand_ZeroBudget_win64.zip` (plus a versioned copy) to the release - about 5 minutes. The script needs
`GITHUB_REPO=owner/repo` and a `GITHUB_TOKEN` (fine-grained, Contents read/write) in `~/.frontline/keys.env`;
`--status` lists the newest release, `--upload` pushes a locally exported `build/*.zip` instead of using CI.
The host rejects mismatched clients, so every release is a new version.

The site's background clip is the game's own shell map: `--shell_only` hides the menu panels and Godot's Movie Maker
records it (`godot --path . --write-movie shell.avi --fixed-fps 30 --quit-after 960 -- --shell_only`, then
`ffmpeg -i shell.avi -an -vf scale=1280:720 -c:v libx264 -crf 27 -pix_fmt yuv420p shell.mp4`).

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
godot --headless --path . -- --host --solo --autostart --faction=usa --test=smoke --exit_after=240
godot --headless --path . -- --host --autostart --ai=1 --faction=gla --ai_faction=china --test=faction --exit_after=330   # per-faction client smoke
godot --headless --path . -- --host --autostart --ai=2 --ai_level=hard --map=grass6 --exit_after=400   # AI game
# two peers:
godot --headless --path . -- --host --autostart --test=smoke --exit_after=330 &
godot --headless --path . -- --join=127.0.0.1 --test=smoke --exit_after=320
```
`--simdebug` prints unit states from the sim every 3 s; `--screenshot=DIR` saves a frame every 8 s; `--reveal` shows the whole map; `--look=x,y` starts the camera there; `--map=desert2|desert4|snow4|grass6`, `--teams=0,1,1`, `--faction=usa|china|gla`, `--ai_faction=china,gla`, `--observe`.
