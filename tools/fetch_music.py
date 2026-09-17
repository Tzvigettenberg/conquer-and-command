#!/usr/bin/env python3
"""Fetch Kevin MacLeod (incompetech.com) tracks, CC BY 4.0, into audio/music as OGG."""
import os, subprocess, urllib.request, urllib.parse, json
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio", "music")
TRACKS = {
    "menu": ["Long Note Two", "Oppressive Gloom"],
    "game": ["Five Armies", "Volatile Reaction", "Exhilarate", "Machinations", "Stormfront", "Unrelenting", "Rocket", "Impact Prelude", "Mechanolith", "Crypto"],
    "victory": ["Heroic Age"],
    "defeat": ["Dark Times"],
}
os.makedirs(ROOT, exist_ok=True)
credits = {}
for kind, names in TRACKS.items():
    for i, name in enumerate(names):
        slug = kind + "_" + name.lower().replace(" ", "_")
        dst = os.path.join(ROOT, slug + ".ogg")
        if not os.path.exists(dst):
            url = "https://incompetech.com/music/royalty-free/mp3-royaltyfree/" + urllib.parse.quote(name) + ".mp3"
            tmp = "/tmp/mus.mp3"
            try:
                urllib.request.urlretrieve(url, tmp)
                if os.path.getsize(tmp) < 300000:
                    raise RuntimeError("too small")
                subprocess.check_call(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-af", "loudnorm=I=-20:TP=-1.5:LRA=11", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "4", dst])
                print("ok", slug)
            except Exception as e:
                print("FAIL", name, e)
                continue
        credits[slug] = {"title": name, "author": "Kevin MacLeod (incompetech.com)", "license": "Creative Commons: By Attribution 4.0 https://creativecommons.org/licenses/by/4.0/"}
json.dump(credits, open(os.path.join(ROOT, "credits.json"), "w"), indent=1)
with open(os.path.join(ROOT, "CREDITS.md"), "w") as f:
    f.write("# Music credits\n\nAll tracks by Kevin MacLeod (incompetech.com), Licensed under Creative Commons: By Attribution 4.0 License\nhttp://creativecommons.org/licenses/by/4.0/\n\n")
    for slug, c in sorted(credits.items()):
        f.write("- `%s.ogg` — \"%s\"\n" % (slug, c["title"]))
