#!/usr/bin/env python3
"""Publish site/dist to GitHub Pages (the `gh-pages` branch).

    python3 tools/publish_site.py

Builds the site first, then replaces the `gh-pages` branch with exactly what is in `site/dist`,
plus the newest Windows zip from `build/` as `download/ConquerAndCommand_ZeroBudget_win64.zip`.
The branch is force-pushed as a single commit, so it holds only the current site and the current
build - the download link never changes and the branch never grows. The zip is deliberately *not*
in `site/dist` (and is git-ignored there), so it never lands in the main branch's history.

Needs the same `~/.frontline/keys.env` as tools/release.py (GITHUB_REPO + GITHUB_TOKEN with
Contents: read/write). One-off: in the repo's Settings -> Pages, set the source to "Deploy from a
branch" -> `gh-pages` / `(root)`.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "site" / "dist"
BRANCH = "gh-pages"
DOWNLOAD_NAME = "ConquerAndCommand_ZeroBudget_win64.zip"


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


def main() -> None:
    env = load_keys()
    for k in ("GITHUB_REPO", "GITHUB_TOKEN"):
        if not env.get(k):
            sys.exit(f"{k} missing - put it in ~/.frontline/keys.env")
    subprocess.check_call([sys.executable, str(ROOT / "tools" / "build_site.py")])
    if not (DIST / "index.html").exists():
        sys.exit("site/dist/index.html missing")
    remote = f"https://x-access-token:{env['GITHUB_TOKEN']}@github.com/{env['GITHUB_REPO']}.git"
    owner, repo = env["GITHUB_REPO"].split("/", 1)
    zips = sorted((ROOT / "build").glob("*_win64.zip"), key=lambda p: p.stat().st_mtime)
    build_zip = zips[-1] if zips and "--no-build" not in sys.argv else None

    # a throwaway repo holding only the built site, force-pushed onto the branch
    with tempfile.TemporaryDirectory() as tmp:
        git = ["git", "-C", tmp]
        subprocess.check_call(git + ["init", "-q", "-b", BRANCH])
        subprocess.check_call(["cp", "-r"] + [str(p) for p in DIST.iterdir()] + [tmp])
        if build_zip:
            (Path(tmp) / "download").mkdir()
            subprocess.check_call(["cp", str(build_zip), str(Path(tmp) / "download" / DOWNLOAD_NAME)])
            print(f"including {build_zip.name} ({build_zip.stat().st_size / 1_000_000:.0f} MB) as download/{DOWNLOAD_NAME}")
        subprocess.check_call(git + ["add", "-A"])
        subprocess.check_call(git + [
            "-c", "user.name=Tzvi Gettenberg", "-c", "user.email=tzvigettenberg@gmail.com",
            "commit", "-q", "-m", "Publish site"])
        subprocess.check_call(git + ["push", "-q", "--force", remote, f"{BRANCH}:{BRANCH}"])
    print(f"published -> https://{owner.lower()}.github.io/{repo}/")
    print("(first time only: Settings -> Pages -> Deploy from a branch -> gh-pages / root)")


if __name__ == "__main__":
    main()
