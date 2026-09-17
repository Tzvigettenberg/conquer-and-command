#!/usr/bin/env python3
"""Ship a release: push the source, tag vGAME_VERSION, and let GitHub Actions build + attach
the Windows zip (.github/workflows/release.yml). The website links to

    https://github.com/<repo>/releases/latest/download/ConquerAndCommand_ZeroBudget_win64.zip

which GitHub always redirects to the newest release, so that link never changes.

Setup (once), in ~/.frontline/keys.env (never committed):
    GITHUB_REPO=Tzvigettenberg/conquer-and-command
    GITHUB_TOKEN=github_pat_...      # fine-grained token, Contents: read/write on that repo

Usage:
    python3 tools/release.py             # push main, push tag vX.Y.Z -> CI builds and publishes
    python3 tools/release.py --upload    # instead: upload build/*.zip from this machine (needs a
                                         # network that allows >10 MB request bodies)
    python3 tools/release.py --status    # show the newest release and its assets
Bump GAME_VERSION in game/main.gd before releasing: the host rejects clients on another version,
and the tag must match it (the workflow checks).
Only the standard library is used.
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


def api(env: dict, method: str, url: str, data=None, ctype="application/json", ok404=False):
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
        if e.code == 404 and ok404:
            return None
        sys.exit(f"{method} {url} -> {e.code}: {e.read().decode()[:400]}")


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT).decode().strip()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--upload", action="store_true", help="upload build/*.zip directly instead of tagging")
    ap.add_argument("--status", action="store_true")
    ap.add_argument("--zip", help="zip to upload (default: newest build/*.zip)")
    a = ap.parse_args()
    env = load_keys()
    for k in ("GITHUB_REPO", "GITHUB_TOKEN"):
        if not env.get(k):
            sys.exit(f"{k} missing - put it in ~/.frontline/keys.env")
    repo = env["GITHUB_REPO"]
    base = f"https://api.github.com/repos/{repo}"
    ver = version()
    tag = f"v{ver}"

    if a.status:
        rel = api(env, "GET", f"{base}/releases/latest", ok404=True)
        if not rel:
            print("no release yet")
            return
        print(rel["tag_name"], rel["html_url"])
        for asset in rel.get("assets", []):
            print(f"  {asset['name']}  {asset['size'] // 1_000_000} MB  downloads: {asset['download_count']}")
        return

    remote = f"https://x-access-token:{env['GITHUB_TOKEN']}@github.com/{repo}.git"
    if git("status", "--porcelain"):
        sys.exit("uncommitted changes - commit first")
    branch = git("rev-parse", "--abbrev-ref", "HEAD")

    if not a.upload:
        subprocess.check_call(["git", "push", "-q", remote, f"HEAD:{branch}"], cwd=ROOT)
        print(f"pushed {branch}")
        if subprocess.call(["git", "rev-parse", "-q", "--verify", f"refs/tags/{tag}"], cwd=ROOT,
                           stdout=subprocess.DEVNULL) != 0:
            git("tag", "-a", tag, "-m", f"Conquer & Command: Zero Budget {tag}")
        subprocess.check_call(["git", "push", "-q", remote, tag], cwd=ROOT)
        print(f"pushed tag {tag} - GitHub Actions is building the Windows zip now:")
        print(f"  https://github.com/{repo}/actions")
        print(f"  download link once it finishes: https://github.com/{repo}/releases/latest/download/{STABLE_NAME}")
        return

    zips = sorted((ROOT / "build").glob("*.zip"), key=lambda p: p.stat().st_mtime)
    zip_path = Path(a.zip) if a.zip else (zips[-1] if zips else None)
    if not zip_path or not zip_path.exists():
        sys.exit("no build zip found - export the Windows build first")
    rel = api(env, "GET", f"{base}/releases/tags/{tag}", ok404=True)
    if rel is None:
        rel = api(env, "POST", f"{base}/releases", {
            "tag_name": tag, "name": f"Conquer & Command: Zero Budget {tag}",
            "generate_release_notes": True})
        print(f"created release {tag}")
    else:
        for asset in rel.get("assets", []):
            if asset["name"] == STABLE_NAME:
                api(env, "DELETE", f"{base}/releases/assets/{asset['id']}")
    upload = rel["upload_url"].split("{")[0]
    data = zip_path.read_bytes()
    print(f"uploading {STABLE_NAME} ({len(data) // 1_000_000} MB)...")
    api(env, "POST", f"{upload}?name={STABLE_NAME}", data, "application/zip")
    print(f"done: https://github.com/{repo}/releases/latest/download/{STABLE_NAME}")


if __name__ == "__main__":
    main()
