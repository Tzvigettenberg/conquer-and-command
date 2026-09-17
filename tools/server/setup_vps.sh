#!/usr/bin/env bash
# ONE-TIME setup for the Conquer & Command match servers, run as root on an Ubuntu VPS:
#   bash setup_vps.sh [number of match servers]
#
# A match server is a headless copy of the game that owns no player: it holds a lobby, runs the
# simulation and tells the games list it is there. Players only ever make outgoing connections to
# it, which every home router allows - nobody forwards a port and nobody types an address.
#
# Each one costs about 200 MB of RAM, so two is a sensible default on a 1 GB box.
set -euo pipefail

COUNT="${1:-2}"
BASE_PORT=7801
GODOT_VER="4.7.2"
GAME_DIR="/opt/conquer-and-command"

echo "==> packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -qq
apt-get install -y -qq wget unzip rsync ufw ca-certificates

echo "==> godot ${GODOT_VER} headless"
if [ ! -x /usr/local/bin/godot-cc ]; then
  cd /tmp
  wget -q -O godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VER}-stable/Godot_v${GODOT_VER}-stable_linux.x86_64.zip"
  unzip -o -q godot.zip
  mv "Godot_v${GODOT_VER}-stable_linux.x86_64" /usr/local/bin/godot-cc
  chmod +x /usr/local/bin/godot-cc
  rm -f godot.zip
fi
/usr/local/bin/godot-cc --version || true

echo "==> service user and folder"
id -u ccserver >/dev/null 2>&1 || useradd -m -s /bin/bash ccserver
mkdir -p "$GAME_DIR"
chown -R ccserver:ccserver "$GAME_DIR"

echo "==> systemd template (one unit per port)"
cat >/etc/systemd/system/cc-match@.service <<EOF
[Unit]
Description=Conquer & Command match server on port %i
After=network-online.target

[Service]
Type=simple
User=ccserver
WorkingDirectory=$GAME_DIR
# a match server keeps no state between games, so a crash just costs the game in progress
ExecStart=/usr/local/bin/godot-cc --headless --path $GAME_DIR -- --dedicated --port=%i
Restart=always
RestartSec=3
StandardOutput=append:/var/log/cc-match-%i.log
StandardError=append:/var/log/cc-match-%i.log
# plenty for one match, and a hard stop if a match ever runs away with memory
MemoryMax=600M

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload

echo "==> firewall"
ufw allow OpenSSH >/dev/null 2>&1 || true
for i in $(seq 0 $((COUNT - 1))); do
  ufw allow "$((BASE_PORT + i))/udp" >/dev/null
done
ufw --force enable >/dev/null 2>&1 || true

echo "==> enabling $COUNT match servers from port $BASE_PORT"
for i in $(seq 0 $((COUNT - 1))); do
  systemctl enable "cc-match@$((BASE_PORT + i))" >/dev/null
done

cat <<EOF

Setup done. Now push the game with:
    bash tools/server/deploy.sh root@<this-server>
which copies the project in and starts every match server.

  status:  systemctl status 'cc-match@*'
  logs:    tail -f /var/log/cc-match-${BASE_PORT}.log
  ports:   UDP ${BASE_PORT}..$((BASE_PORT + COUNT - 1))
EOF
