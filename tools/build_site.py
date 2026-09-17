#!/usr/bin/env python3
"""Build the website.

One source, two outputs, so the public site and the preview never drift:

  site/src/index.html   the page itself. It opens with <title>/<link>/<style> and then the markup -
                        exactly the shape the Claude artifact preview wants (it supplies the
                        document skeleton), so it can be published there as-is.
  site/dist/            a normal standalone site for GitHub Pages: the same page wrapped in a real
                        <!doctype html> document with charset, viewport and social-preview tags,
                        plus the images and the shell-map clip.

Usage:  python3 tools/build_site.py [--check]
        --check only verifies that dist is up to date (for CI).
"""
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "site" / "src"
DIST = ROOT / "site" / "dist"
PAGE_URL = "https://tzvigettenberg.github.io/conquer-and-command/"
DESCRIPTION = ("Conquer & Command: Zero Budget - a free Command & Conquer Generals: Zero Hour-style "
               "RTS for Windows. USA, China and the GLA, skirmish and multiplayer.")


def build() -> str:
    raw = (SRC / "index.html").read_text()
    # everything before the first element is head material (title, font link, styles)
    split = raw.index("<header")
    head, body = raw[:split].strip(), raw[split:].strip()
    title = re.search(r"<title>(.*?)</title>", head, re.S)
    title = title.group(1).strip() if title else "Conquer & Command: Zero Budget"
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="description" content="{DESCRIPTION}">
<meta name="theme-color" content="#0b0d10">
<meta property="og:type" content="website">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{DESCRIPTION}">
<meta property="og:url" content="{PAGE_URL}">
<meta property="og:image" content="{PAGE_URL}img/poster.jpg">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><text y='26' font-size='26'>%F0%9F%8E%96</text></svg>">
<style>
  :root {{ color-scheme: dark; padding-top: env(safe-area-inset-top, 0px); padding-bottom: env(safe-area-inset-bottom, 0px); }}
  body {{ margin: 0; }}
  img {{ max-width: 100%; }}
  [hidden] {{ display: none !important; }}
</style>
{head}
</head>
<body>
{body}
</body>
</html>
"""


def main() -> None:
    check = "--check" in sys.argv
    page = build()
    current = (DIST / "index.html").read_text() if (DIST / "index.html").exists() else ""
    if check:
        sys.exit(0 if current == page else "site/dist is stale - run tools/build_site.py")
    DIST.mkdir(parents=True, exist_ok=True)
    (DIST / "index.html").write_text(page)
    # GitHub Pages runs Jekyll by default, which would swallow files starting with an underscore
    (DIST / ".nojekyll").write_text("")
    for folder in ("img", "media"):
        dst = DIST / folder
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(SRC / folder, dst)
    total = sum(f.stat().st_size for f in DIST.rglob("*") if f.is_file())
    print(f"built site/dist ({total / 1_000_000:.1f} MB) -> {PAGE_URL}")


if __name__ == "__main__":
    main()
