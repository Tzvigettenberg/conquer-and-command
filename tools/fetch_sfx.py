#!/usr/bin/env python3
"""Fetch CC0 / CC-BY sound effects from Freesound for Frontline.

Usage: FREESOUND_KEY=... python3 tools/fetch_sfx.py [name ...]
Writes audio/sfx/<name>.ogg plus audio/sfx/CREDITS.md. Only re-downloads entries
that are missing (or listed on the command line).
"""
import json, os, subprocess, sys, time, urllib.parse, urllib.request

KEY = os.environ.get("FREESOUND_KEY", "")
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio", "sfx")
API = "https://freesound.org/apiv2"

# name: (query, min_dur, max_dur, loop, extra filter)
MANIFEST = {
    # weapons
    "rifle_burst":      ("assault rifle burst", 0.3, 3.0, False, ""),
    "machinegun":       ("minigun fire", 0.4, 4.0, False, ""),
    "tank_cannon":      ("tank cannon shot", 0.5, 4.0, False, ""),
    "missile_launch":   ("missile launch whoosh", 0.5, 4.0, False, ""),
    "rocket_pod":       ("rocket launch", 0.3, 3.0, False, ""),
    "artillery_fire":   ("howitzer fire", 0.5, 5.0, False, ""),
    "laser_zap":        ("laser zap sci-fi", 0.2, 2.0, False, ""),
    "sniper_shot":      ("sniper rifle single shot", 0.4, 3.0, False, ""),
    "bomb_whistle":     ("bomb falling whistle", 1.0, 5.0, False, ""),
    "gau8":             ("gatling gun burst", 0.5, 6.0, False, ""),
    # impacts
    "explosion_small":  ("small explosion", 0.5, 3.0, False, ""),
    "explosion_medium": ("explosion", 1.0, 5.0, False, ""),
    "explosion_large":  ("large explosion", 2.0, 8.0, False, ""),
    "ricochet":         ("ricochet", 0.2, 2.0, False, ""),
    "building_collapse":("building collapse rubble", 1.5, 8.0, False, ""),
    "metal_hit":        ("metal hit", 0.2, 2.0, False, ""),
    # vehicles
    "tank_engine":      ("tank engine loop", 2.0, 15.0, True, ""),
    "truck_engine":     ("diesel truck engine loop", 2.0, 15.0, True, ""),
    "humvee_engine":    ("car engine idle loop", 2.0, 15.0, True, ""),
    "helicopter_loop":  ("helicopter rotor loop", 2.0, 15.0, True, ""),
    "jet_loop":         ("jet engine", 2.0, 20.0, True, ""),
    "jet_flyby":        ("fighter jet flyby", 2.0, 8.0, False, ""),
    "chinook_loop":     ("helicopter hovering", 2.0, 20.0, True, ""),
    # base
    "construction":     ("construction site hammering", 2.0, 12.0, True, ""),
    "place_building":   ("hammering nails wood construction", 0.6, 4.0, False, ""),
    "sell":             ("cash register", 0.3, 3.0, False, ""),
    "cash":             ("coins money", 0.2, 2.0, False, ""),
    "power_down":       ("power down", 0.5, 5.0, False, ""),
    "power_up":         ("power up hum", 0.5, 5.0, False, ""),
    "repair":           ("wrench ratchet", 0.3, 3.0, False, ""),
    "capture":          ("radio static beep", 0.3, 3.0, False, ""),
    "superweapon_charge":("sci-fi charging", 1.0, 6.0, False, ""),
    "superweapon_fire": ("laser cannon", 1.0, 8.0, False, ""),
    "satellite":        ("sonar ping", 0.3, 3.0, False, ""),
    "plane_pass":       ("propeller plane flyby", 2.0, 10.0, False, ""),
    # ui
    "ui_click":         ("ui click", 0.05, 1.0, False, ""),
    "ui_hover":         ("ui hover tick", 0.05, 1.0, False, ""),
    "ui_error":         ("error buzz", 0.1, 1.5, False, ""),
    "ui_select":        ("select blip", 0.05, 1.0, False, ""),
    "alert":            ("alarm siren short", 0.5, 4.0, False, ""),
    "chime":            ("notification chime", 0.2, 2.0, False, ""),
    "fanfare":          ("short fanfare", 1.0, 6.0, False, ""),
    "victory":          ("victory fanfare", 2.0, 12.0, False, ""),
    "defeat":           ("sad trombone", 1.0, 8.0, False, ""),
    # ambience / infantry
    "wind_loop":        ("desert wind loop", 5.0, 40.0, True, ""),
    "scream":           ("male death scream", 0.3, 3.0, False, ""),
    "grunt":            ("male pain grunt", 0.2, 2.0, False, ""),
    "footsteps":        ("running footsteps gravel", 1.0, 10.0, True, ""),
    "crush":            ("bone crunch", 0.2, 2.0, False, ""),
    "beep":             ("radio beep", 0.1, 1.0, False, ""),
}


def api(path, params):
    params["token"] = KEY
    url = API + path + "?" + urllib.parse.urlencode(params)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                return json.load(r)
        except Exception as e:  # noqa
            time.sleep(2)
            err = e
    raise err


def pick(name, query, lo, hi, extra):
    """Top relevance hits, re-ranked by rating and by keyword presence in name/tags."""
    filt = 'duration:[%s TO %s]' % (lo, hi)
    if extra:
        filt += " " + extra
    words = [w for w in query.lower().split() if w not in ("loop", "sound", "effect", "sci-fi", "short", "single")]
    out = []
    for lic in ['license:"Creative Commons 0"', 'license:("Creative Commons 0" OR "Attribution")']:
        res = api("/search/text/", {
            "query": query, "filter": filt + " " + lic, "fields": "id,name,tags,previews,license,username,duration,avg_rating,num_ratings,num_downloads",
            "page_size": 12})
        for idx, r in enumerate(res.get("results", [])):
            text = (r["name"] + " " + " ".join(r.get("tags", []))).lower()
            kw = sum(1 for w in words if w in text)
            rating = (r.get("avg_rating") or 0) * min(r.get("num_ratings") or 0, 5) / 5.0
            score = (12 - idx) * 0.8 + rating * 2.0 + kw * 4.0 + min((r.get("num_downloads") or 0), 20000) / 8000.0
            out.append((score, r))
        if out:
            break
    out.sort(key=lambda x: -x[0])
    return [r for _, r in out]


def convert(src, dst, loop):
    filt = "loudnorm=I=-18:TP=-1.5:LRA=11"
    if loop:
        filt += ",afade=t=in:d=0.05,afade=t=out:d=0.05"
    subprocess.check_call(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-af", filt, "-ac", "1", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "4", dst])


def main():
    if not KEY:
        sys.exit("FREESOUND_KEY missing")
    os.makedirs(ROOT, exist_ok=True)
    credits_path = os.path.join(ROOT, "credits.json")
    credits = json.load(open(credits_path)) if os.path.exists(credits_path) else {}
    wanted = sys.argv[1:] or list(MANIFEST)
    for name in wanted:
        query, lo, hi, loop, extra = MANIFEST[name]
        dst = os.path.join(ROOT, name + ".ogg")
        if os.path.exists(dst) and name not in sys.argv[1:]:
            continue
        cands = pick(name, query, lo, hi, extra)
        r = None
        for cand in cands[:5]:
            try:
                url = cand["previews"]["preview-hq-mp3"]
                tmp = "/tmp/fs_%s.mp3" % name
                urllib.request.urlretrieve(url, tmp)
                convert(tmp, dst, loop)
                r = cand
                break
            except Exception as e:  # noqa
                print("  retry", name, e)
        if r is None:
            print("MISSING", name)
            continue
        credits[name] = {"id": r["id"], "title": r["name"], "author": r["username"], "license": r["license"], "url": "https://freesound.org/s/%d/" % r["id"]}
        print("%-20s %-40s %-14s %s" % (name, r["name"][:40], r["username"][:14], r["license"].split("/")[-3]))
        time.sleep(0.6)
    json.dump(credits, open(credits_path, "w"), indent=1)
    with open(os.path.join(ROOT, "CREDITS.md"), "w") as f:
        f.write("# Sound effect credits (Freesound)\n\n")
        for name in sorted(credits):
            c = credits[name]
            f.write("- `%s.ogg` — \"%s\" by %s — %s — %s\n" % (name, c["title"], c["author"], c["license"], c["url"]))


if __name__ == "__main__":
    main()
