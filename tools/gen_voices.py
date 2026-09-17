#!/usr/bin/env python3
"""Generate unit voicelines and EVA announcements with ElevenLabs.

Usage: ELEVEN_KEY=... python3 tools/gen_voices.py
Writes audio/voice/<class>/<kind>_<n>.ogg (radio-filtered) and audio/voice/eva/<name>.ogg.
Skips files that already exist, so re-running only fills gaps.
"""
import json, os, subprocess, sys, time, urllib.request

KEY = os.environ.get("ELEVEN_KEY", "")
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio", "voice")
MODEL = "eleven_multilingual_v2"

VOICES = {
    "eva": "XrExE9yKIg1WjnnlVkGX",        # Matilda
    "ranger": "SOYHLrjzK2X1ezoPC6cr",     # Harry
    "missile_defender": "TX3LPaxmHKxFdv7VOQHJ",  # Liam
    "pathfinder": "N2lVS1w4EtoT3dr4eOWO", # Callum
    "burton": "pNInz6obpgDQGcFmaJgB",     # Adam
    "tank": "nPczCjzI2devNBz1zQrb",       # Brian (crusader / paladin)
    "humvee": "bIHbv24MWmeRgasZH58o",     # Will
    "dozer": "CwhRBWXzGAHq8TQ4Fs17",      # Roger
    "tomahawk": "cjVigY5qzO86Huf0OWal",   # Eric
    "avenger": "iP95p4xoKVk53GoZ742B",    # Chris
    "ambulance": "hpp4J3VqNfWAUOO0d1Us",  # Bella
    "chinook": "IKne3meq5aSn9XLyUdCD",    # Charlie
    "comanche": "cgSgspJ2msm6clMCkdW9",   # Jessica
    "raptor": "onwK4e9ZLuTAKqWW03F9",     # Daniel
    "stealth_fighter": "JBFqnCBsd6RMkjVDRZzb",  # George
    "aurora": "pqHfZKP75CvOlQylNhV4",     # Bill
}

UNIT_LINES = {
    "ranger": {
        "ready": ["Ranger reporting for duty."],
        "select": ["Yes sir?", "Ready to roll.", "Rangers lead the way.", "Awaiting orders."],
        "move": ["Moving out.", "On the double!", "Roger that.", "Let's go, let's go!"],
        "attack": ["Engaging!", "Open fire!", "Taking them down!", "Contact, front!"],
        "capture": ["Taking the building.", "We'll take it from here."],
    },
    "missile_defender": {
        "ready": ["Missile Defender ready."],
        "select": ["Locked and loaded.", "Missiles ready.", "Where's the armor?", "Standing by."],
        "move": ["Moving up.", "Copy that.", "Relocating.", "On my way."],
        "attack": ["Missile away!", "Lock on, firing!", "Say goodbye!", "Target locked!"],
    },
    "pathfinder": {
        "ready": ["Pathfinder in position."],
        "select": ["I see everything.", "One shot, one kill.", "Patience.", "Quietly now."],
        "move": ["Relocating.", "Moving to overwatch.", "Staying low.", "Understood."],
        "attack": ["Target acquired.", "Taking the shot.", "Clean kill.", "They never saw it coming."],
    },
    "burton": {
        "ready": ["Colonel Burton reporting."],
        "select": ["Burton here.", "What do you need?", "I work alone.", "Give me a target."],
        "move": ["I'm on it.", "Moving in.", "Consider it done.", "Going dark."],
        "attack": ["Time to earn my pay.", "Lights out.", "Precision strike.", "This one's mine."],
    },
    "tank": {
        "ready": ["Crusader tank ready to roll.", "Paladin online, sir."],
        "select": ["Armor ready.", "Tank crew standing by.", "Where to, sir?", "Ready for battle."],
        "move": ["Rolling out.", "Advancing.", "Tracks are turning.", "Moving to position."],
        "attack": ["Fire main gun!", "Engaging target!", "Shell loaded, firing!", "They won't be walking away from that."],
    },
    "humvee": {
        "ready": ["Humvee ready to roll."],
        "select": ["Fast and light.", "Humvee here.", "Let's ride.", "Ready to scout."],
        "move": ["Floor it!", "We're moving.", "Pedal to the metal.", "On the road."],
        "attack": ["Light 'em up!", "Gunner, engage!", "Taking fire, returning fire!", "Got 'em in my sights."],
    },
    "dozer": {
        "ready": ["Dozer ready for construction."],
        "select": ["What are we building?", "Dozer here.", "Got my hard hat on.", "Ready to build."],
        "move": ["Moving the dozer.", "On my way.", "Sure thing.", "Heading over."],
        "build": ["Let's get to work.", "Building it now.", "Construction underway.", "We'll have it up in no time."],
        "repair": ["Patching it up.", "Repairs underway."],
    },
    "tomahawk": {
        "ready": ["Tomahawk launcher operational."],
        "select": ["Long range artillery ready.", "Give me coordinates.", "Tomahawk standing by.", "Missiles primed."],
        "move": ["Repositioning launcher.", "Moving out.", "Copy, relocating.", "On the move."],
        "attack": ["Tomahawk launch!", "Firing cruise missile!", "Coordinates locked, firing!", "Splash in ten seconds."],
    },
    "avenger": {
        "ready": ["Avenger anti-air online."],
        "select": ["Avenger ready.", "Watching the skies.", "Lasers charged.", "Air defense standing by."],
        "move": ["Moving the Avenger.", "Relocating air defense.", "On our way.", "Copy that."],
        "attack": ["Painting the target!", "Laser engaged!", "Bringing it down!", "Nothing gets through."],
    },
    "ambulance": {
        "ready": ["Ambulance ready."],
        "select": ["Medic here.", "Who needs help?", "Ambulance standing by.", "Ready to assist."],
        "move": ["On my way.", "Medic moving.", "Coming through.", "Heading there now."],
    },
    "chinook": {
        "ready": ["Chinook ready for pickup."],
        "select": ["Chinook here.", "Rotors turning.", "Ready to haul.", "What's the cargo?"],
        "move": ["Chinook moving.", "Taking off.", "Roger, en route.", "Airborne."],
        "gather": ["Picking up supplies.", "Heading to the supply dock.", "Cargo run, copy."],
    },
    "comanche": {
        "ready": ["Comanche online."],
        "select": ["Comanche here.", "Rotors are hot.", "Ready to hunt.", "Awaiting target."],
        "move": ["Moving in.", "Comanche en route.", "Flying low.", "On my way."],
        "attack": ["Guns hot!", "Engaging target!", "Rockets away!", "Lighting them up!"],
    },
    "raptor": {
        "ready": ["Raptor ready for takeoff."],
        "select": ["Raptor here.", "Standing by on the runway.", "Missiles loaded.", "Ready to scramble."],
        "move": ["Wheels up.", "Scrambling now.", "Raptor airborne.", "Taking off."],
        "attack": ["Fox two!", "Missiles away!", "Engaging target!", "Tally ho!"],
        "return": ["Winchester, returning to base.", "Out of ammo, heading home."],
    },
    "stealth_fighter": {
        "ready": ["Stealth fighter ready."],
        "select": ["They'll never see me.", "Stealth fighter standing by.", "Running silent.", "Ready when you are."],
        "move": ["Going stealth.", "Taking off.", "Airborne and invisible.", "En route."],
        "attack": ["Target locked.", "Firing.", "Silent strike.", "They won't know what hit them."],
        "return": ["Returning to base."],
    },
    "aurora": {
        "ready": ["Aurora bomber ready."],
        "select": ["Aurora standing by.", "Supersonic and ready.", "Give me a target.", "Bomb loaded."],
        "move": ["Going supersonic.", "Aurora airborne.", "Taking off.", "Full afterburner."],
        "attack": ["Bomb run commencing.", "Target locked, going in.", "Bombs away!", "Brace for impact."],
        "return": ["Returning to base."],
    },
}

EVA_LINES = {
    "construction_complete": "Construction complete.",
    "unit_ready": "Unit ready.",
    "insufficient_funds": "Insufficient funds.",
    "cannot_build": "Cannot build there.",
    "low_power": "Low power.",
    "power_restored": "Power restored.",
    "base_under_attack": "Our base is under attack.",
    "units_under_attack": "Our forces are under attack.",
    "unit_lost": "Unit lost.",
    "structure_lost": "Structure lost.",
    "upgrade_complete": "Upgrade complete.",
    "building_captured": "Building captured.",
    "structure_captured_by_enemy": "Structure captured by the enemy.",
    "superweapon_ready": "Particle cannon ready.",
    "enemy_superweapon": "Warning. Enemy particle cannon detected.",
    "superweapon_launch": "Particle cannon launched.",
    "enemy_superweapon_launch": "Warning. Enemy superweapon launched.",
    "promotion": "Promotion available. New general's powers can be unlocked.",
    "rank_up": "General rank increased.",
    "new_power": "New general's power acquired.",
    "airfield_full": "Airfield is full.",
    "requires": "Cannot comply. Requirements not met.",
    "supply_dock_empty": "Supply dock depleted.",
    "victory": "Mission accomplished. Victory.",
    "defeat": "Mission failed. Our base has been destroyed.",
    "a10": "A-10 strike inbound.",
    "paradrop": "Paradrop inbound.",
    "fuel_air_bomb": "Fuel air bomb inbound.",
    "spy_satellite": "Spy satellite scan complete.",
    "emergency_repair": "Emergency repair deployed.",
    "enemy_fuel_air_bomb": "Warning. Enemy fuel air bomb inbound.",
    "welcome": "Welcome, commander. Build your base and destroy the enemy.",
    "capture_requires": "Capture building upgrade required.",
    "player_disconnected": "Opponent disconnected.",
    "select_dozer": "Dozer selected.",
}


def tts(voice_id, text, dst_mp3):
    req = urllib.request.Request(
        "https://api.elevenlabs.io/v1/text-to-speech/%s?output_format=mp3_44100_128" % voice_id,
        data=json.dumps({"text": text, "model_id": MODEL, "voice_settings": {"stability": 0.45, "similarity_boost": 0.8, "style": 0.35, "use_speaker_boost": True}}).encode(),
        headers={"xi-api-key": KEY, "Content-Type": "application/json", "Accept": "audio/mpeg"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                open(dst_mp3, "wb").write(r.read())
            return True
        except Exception as e:  # noqa
            print("  retry:", e)
            time.sleep(3)
    return False


def convert(src, dst, radio):
    if radio:
        # squad radio: band-limit, compress, a touch of grit, click at the end
        filt = "highpass=f=380,lowpass=f=3300,acompressor=threshold=-18dB:ratio=4:attack=5:release=80,acrusher=bits=10:mode=log:mix=0.15,loudnorm=I=-16:TP=-1.5"
    else:
        filt = "highpass=f=90,acompressor=threshold=-20dB:ratio=3,loudnorm=I=-17:TP=-1.5"
    subprocess.check_call(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-af", filt, "-ac", "1", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "4", dst])


def main():
    if not KEY:
        sys.exit("ELEVEN_KEY missing")
    total = 0
    for cls, kinds in UNIT_LINES.items():
        d = os.path.join(ROOT, cls)
        os.makedirs(d, exist_ok=True)
        for kind, lines in kinds.items():
            for i, line in enumerate(lines):
                dst = os.path.join(d, "%s_%d.ogg" % (kind, i))
                if os.path.exists(dst):
                    continue
                tmp = "/tmp/voice.mp3"
                if tts(VOICES[cls], line, tmp):
                    convert(tmp, dst, True)
                    total += len(line)
                    print(cls, kind, i, line)
    d = os.path.join(ROOT, "eva")
    os.makedirs(d, exist_ok=True)
    for name, line in EVA_LINES.items():
        dst = os.path.join(d, name + ".ogg")
        if os.path.exists(dst):
            continue
        tmp = "/tmp/voice.mp3"
        if tts(VOICES["eva"], line, tmp):
            convert(tmp, dst, False)
            total += len(line)
            print("eva", name, line)
    print("characters used:", total)


if __name__ == "__main__":
    main()
