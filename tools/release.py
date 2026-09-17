#!/usr/bin/env python3
"""Publish a build to GitHub Releases so the website's download link stays current.

The site links to
    https://github.com/<repo>/releases/latest/download/ConquerAndCommand_ZeroBudget_win64.zip
which GitHub always redirects to the newest release, so the link on the website never
changes: every run of this script *is* the update.

Setup (once), in ~/.frontline/keys.env (never committed):
    GITHUB_REPO=tzvigettenberg/conquer-and-command
    GITHUB_TOKEN=github_pat_...      # fine-grained token with Contents: read/write on that repo

Usage:
    python3 tools/release.py                  # tag + release GAME_VERSION with build/*.zip
    python3 tools/release.py --push           # also push the source to GitHub first
    python3 tools/release.py --notes notes.md # release notes from a file (default: M-section of README)
Only the standard library is used, so it runs anywhere python3 does.
"""
import argparse, json, os, re, subprocess, sys, urllib.request, urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STABLE_NAME = "ConquerAndCommand_ZeroBudget_win64.zip"


def load_keys() -> dict:
    env = dict(os.environ)
    p = Path.home() / ".frontline" / "keys.env"
    if p.exists():
        for line in p.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env.setdefault(k.strip(), v.strip().strip('"').strip("'"))
    return env


def version() -> str:
    src = (ROOT / "game" / "main.gd").read_text()
    m = re.search(r'GAME_VERSION\s*:=\s*"([^"]+)"', src)
    if not m:
        sys.exit("GAME_VERSION not found in game/main.gd")
    return m.group(1)


def default_notes(ver: str) -> str:
    readme = (ROOT / "README.md").read_text()
    m = re.search(r"## What's in \(M[\d.]+\)[^\n]*\n(.*?)(?=\n## )", readme, re.S)
    body = m.group(1).strip() if m else ""
    return f"Conquer & Command: Zero Budget v{ver}\n\nWindows 64-bit. Unzip, run ConquerAndCommand.exe. Everyone needs the same version to play together.\n\n{body}"


def api(env: dict, method: str, url: str, data=None, ctype="application/json"):
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", f"Bearer {env['GITHUB_TOKEN']}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data is not None:
        if ctype == "application/json":
            data = json.dumps(data).encode()
        req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req, data) as r:
            txt = r.read().decode()
            return json.loads(txt) if txt else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {url} -> {e.code}: {e.read().decode()[:400]}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--push", action="store_true", help="git push the source first")
    ap.add_argument("--notes", help="markdown file with release notes")
    ap.add_argument("--zip", help="zip to upload (default: newest build/*.zip)")
    a = ap.parse_args()
    env = load_keys()
    for k in ("GITHUB_REPO", "GITHUB_TOKEN"):
        if not env.get(k):
            sys.exit(f"{k} missing - put it in ~/.frontline/keys.env")
    repo = env["GITHUB_REPO"]
    ver = version()
    tag = f"v{ver}"
    zips = sorted((ROOT / "build").glob("*.zip"), key=lambda p: p.stat().st_mtime)
    zip_path = Path(a.zip) if a.zip else (zips[-1] if zips else None)
    if not zip_path or not zip_path.exists():
        sys.exit("no build zip found - export the Windows build first")
    if ver not in zip_path.name:
        print(f"warning: {zip_path.name} does not mention v{ver}")
    notes = Path(a.notes).read_text() if a.notes else default_notes(ver)

    if a.push:
        remote = f"https://x-access-token:{env['GITHUB_TOKEN']}@github.com/{repo}.git"
        branch = subprocess.check_output(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=ROOT).decode().strip()
        subprocess.check_call(["git", "push", remote, f"HEAD:{branch}"], cwd=ROOT)
        print(f"pushed {branch}")

    base = f"https://api.github.com/repos/{repo}"
    rel = None
    try:
        rel = api(env, "GET", f"{base}/releases/tags/{tag}")
    except SystemExit:
        rel = None
    if rel is None or "id" not in rel:
        rel = api(env, "POST", f"{base}/releases", {
            "tag_name": tag, "name": f"Conquer & Command: Zero Budget {tag}",
            "body": notes, "draft": False, "prerelease": False, "generate_release_notes": False})
        print(f"created release {tag}")
    else:
        print(f"release {tag} exists - replacing assets")
        for asset in rel.get("assets", []):
            api(env, "DELETE", f"{base}/releases/assets/{asset['id']}")
    upload = rel["upload_url"].split("{")[0]
    data = zip_path.read_bytes()
    for name in dict.fromkeys([STABLE_NAME, zip_path.name]):
        print(f"uploading {name} ({len(data) // 1_000_000} MB)...")
        api(env, "POST", f"{upload}?name={name}", data, "application/zip")
    print("done:")
    print(f"  release  https://github.com/{repo}/releases/tag/{tag}")
    print(f"  download https://github.com/{repo}/releases/latest/download/{STABLE_NAME}")


if __name__ == "__main__":
    main()
