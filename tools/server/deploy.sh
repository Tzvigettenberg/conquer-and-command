#!/usr/bin/env bash
# Push the current game to the match servers and restart them.
#   bash tools/server/deploy.sh root@<server-ip> [number of match servers]
#
# Only changed files go over the wire, so a code-only update is a few hundred KB. The import cache
# (.godot) goes too, so the server never has to import anything itself - which means the build that
# runs there is exactly the build that was tested here.
set -euo pipefail

HOST="${1:?usage: deploy.sh root@server-ip [count]}"
COUNT="${2:-2}"
BASE_PORT=7801
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GAME_DIR="/opt/conquer-and-command"

# A match server never renders, so the licensed art, the website and the tools stay at home.
echo "==> syncing $SRC -> $HOST:$GAME_DIR"
rsync -az --delete --info=stats1 \
  --exclude '.git' \
  --exclude 'Assets' \
  --exclude 'build' \
  --exclude 'mixamo' \
  --exclude 'site' \
  --exclude 'tools' \
  --exclude '*.log' \
  "$SRC/" "$HOST:$GAME_DIR/"

ssh "$HOST" "chown -R ccserver:ccserver $GAME_DIR"

echo "==> restarting $COUNT match servers"
PORTS=""
for i in $(seq 0 $((COUNT - 1))); do PORTS="$PORTS cc-match@$((BASE_PORT + i))"; done
ssh "$HOST" "systemctl restart $PORTS && sleep 4 && systemctl is-active $PORTS"

echo "==> what they say"
ssh "$HOST" "tail -n 3 /var/log/cc-match-${BASE_PORT}.log"
echo "==> live"
