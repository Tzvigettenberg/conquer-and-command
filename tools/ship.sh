#!/usr/bin/env bash
# Ship a build: export it, put it behind the Download button, and put the same build on the match
# servers. The last part matters - players and servers must be on the same GAME_VERSION or the
# servers will turn everyone away, so this script refuses to do one without the other.
#
#   bash tools/ship.sh              # build, publish the site, deploy the servers, verify
#   bash tools/ship.sh --site       # only the website + download
#   bash tools/ship.sh --servers    # only the match servers
#
# Runs where Godot and the SSH key live (Tzvi's PC). Settings come from ~/.frontline/keys.env:
# GITHUB_REPO, GITHUB_TOKEN, CC_SERVER_IP.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-$HOME/gd/Godot_v4.7.2-stable_linux.x86_64}"
PROJ="${PROJ:-$HOME/proj}"
KEY="${KEY:-$HOME/.frontline/id_cc}"
KEYS="$HOME/.frontline/keys.env"
[ -f "$KEYS" ] && set -a && . "$KEYS" && set +a
SERVER="${CC_SERVER_IP:?CC_SERVER_IP missing from ~/.frontline/keys.env}"
LIST_URL="${LIST_URL:-https://cc-rooms.zerobudget.workers.dev}"

DO_SITE=1; DO_SERVERS=1
case "${1:-}" in
  --site) DO_SERVERS=0 ;;
  --servers) DO_SITE=0 ;;
esac

VERSION=$(grep -oP 'GAME_VERSION\s*:=\s*"\K[^"]+' "$REPO/game/main.gd")
echo "==> shipping v$VERSION"

# ---- 1. export the Windows build from an imported copy of the project ----
echo "==> building"
mkdir -p "$PROJ" "$HOME/gd/build"
rsync -a --delete --exclude .git --exclude build --exclude mixamo --exclude Assets \
  --exclude 'site/dist/download' "$REPO/" "$PROJ/"
"$GODOT" --headless --path "$PROJ" --import >/dev/null 2>&1 || true
rm -f "$HOME/gd/build/ConquerAndCommand.exe"
"$GODOT" --headless --path "$PROJ" --export-release "Windows Desktop" "$HOME/gd/build/ConquerAndCommand.exe" >/dev/null
EXE_MB=$(( $(stat -c%s "$HOME/gd/build/ConquerAndCommand.exe") / 1000000 ))
echo "    ConquerAndCommand.exe  ${EXE_MB} MB"
# an exe this size means the licensed art got packed in by mistake
[ "$EXE_MB" -gt 200 ] && { echo "REFUSING: the build is ${EXE_MB} MB - check exclude_filter in export_presets.cfg"; exit 1; }

cd "$HOME/gd/build"
cat > README.txt <<EOF
Conquer & Command: Zero Budget v$VERSION  (Windows 64-bit)

Run ConquerAndCommand.exe. If Windows SmartScreen complains: More info -> Run anyway.

Playing with friends
  One of you types a name for the game (and a password if you want) and presses CREATE GAME.
  Everyone else sees it under OPEN GAMES and clicks it. That is the whole thing - matches run on
  our server, so there is no port forwarding, no addresses and nothing to set up.

On your own
  SKIRMISH VS AI plays against the computer on your own PC, no connection needed.

Everyone needs the same version. Newest build: https://tzvigettenberg.github.io/conquer-and-command/
EOF
ZIP="ConquerAndCommand_ZeroBudget_v${VERSION}_win64.zip"
rm -f ConquerAndCommand_ZeroBudget_v*_win64.zip
zip -q -9 "$ZIP" ConquerAndCommand.exe README.txt
mkdir -p "$REPO/build/_old"
mv -f "$REPO"/build/ConquerAndCommand_ZeroBudget_v*_win64.zip "$REPO/build/_old/" 2>/dev/null || true
cp ConquerAndCommand.exe "$REPO/build/ConquerAndCommand.exe.new" && mv -f "$REPO/build/ConquerAndCommand.exe.new" "$REPO/build/ConquerAndCommand.exe"
cp "$ZIP" README.txt "$REPO/build/"
echo "    $ZIP  $(( $(stat -c%s "$ZIP") / 1000000 )) MB"

# ---- 2. the website and the download ----
if [ "$DO_SITE" = 1 ]; then
  echo "==> publishing the site"
  python3 "$REPO/tools/build_site.py" >/dev/null
  python3 "$REPO/tools/publish_site.py" | sed 's/^/    /'
fi

# ---- 3. the match servers, from the same imported copy that produced the exe ----
if [ "$DO_SERVERS" = 1 ]; then
  echo "==> deploying the match servers ($SERVER)"
  rsync -az --delete -e "ssh -i $KEY -o StrictHostKeyChecking=no" \
    --exclude '.git' --exclude 'Assets' --exclude 'build' --exclude 'mixamo' --exclude 'site' \
    --exclude 'tools' --exclude '*.log' "$PROJ/" "root@$SERVER:/opt/conquer-and-command/"
  ssh -i "$KEY" -o StrictHostKeyChecking=no "root@$SERVER" \
    "chown -R ccserver:ccserver /opt/conquer-and-command && systemctl restart cc-match@7801 cc-match@7802 && sleep 6 && systemctl is-active cc-match@7801 cc-match@7802" | sed 's/^/    /'
fi

# ---- 4. prove players and servers agree ----
echo "==> checking"
SRV_VER=$(ssh -i "$KEY" -o StrictHostKeyChecking=no "root@$SERVER" "grep -oP 'GAME_VERSION\\s*:=\\s*\"\\K[^\"]+' /opt/conquer-and-command/game/main.gd")
echo "    servers run v$SRV_VER"
[ "$SRV_VER" = "$VERSION" ] || { echo "MISMATCH: site has v$VERSION, servers have v$SRV_VER"; exit 1; }
for i in 1 2 3 4 5 6; do
  HEALTH=$(curl -s -m 10 "$LIST_URL/health" || true)
  case "$HEALTH" in *'"free":2'*) break ;; esac
  sleep 5
done
echo "    games list: ${HEALTH:-unreachable}"
case "${HEALTH:-}" in
  *'"free":0'*|"") echo "WARNING: no free match server is registered yet - check /var/log/cc-match-7801.log" ;;
esac
echo "==> shipped v$VERSION"
