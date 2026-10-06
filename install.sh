#!/usr/bin/env bash
# Valheim dedicated server installer for Ubuntu 24.04 LTS
#
#   sudo ./install.sh                      # fresh random world
#   sudo ./install.sh --world-dir ~/Ginnung      # your world (new folder-style save)
#   sudo ./install.sh --world-file Ginnung.fwl   # your world (old single-file save)
#
# Safe to re-run: it updates config/units and keeps existing worlds.
set -euo pipefail

# ---------- defaults (edit /etc/valheim/valheim.env later to change) ----------
VH_USER=valheim
BASE_DIR=/srv/valheim
INSTALL_DIR=$BASE_DIR/server
SAVE_DIR=$BASE_DIR/data
BACKUP_DIR=/var/backups/valheim
CONF_DIR=/etc/valheim
CONF=$CONF_DIR/valheim.env
APP_ID=896660           # Valheim Dedicated Server
UPDATE_TIME="05:00"     # nightly update+restart, Norwegian time
BACKUP_KEEP_DAYS=14

WORLD_FILE=""
WORLD_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --world-file) WORLD_FILE="$(realpath "$2")"; shift 2 ;;
    --world-dir)  WORLD_DIR="$(realpath "$2")"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
if [[ -n "$WORLD_FILE" ]]; then
  [[ -f "$WORLD_FILE" && "$WORLD_FILE" == *.fwl ]] || { echo "--world-file must be an existing .fwl file" >&2; exit 1; }
fi
if [[ -n "$WORLD_DIR" ]]; then
  [[ -d "$WORLD_DIR" ]] || { echo "--world-dir must be an existing folder" >&2; exit 1; }
  compgen -G "$WORLD_DIR/*.fwl*" >/dev/null || { echo "$WORLD_DIR doesn't look like a Valheim world (no .fwl2 file)" >&2; exit 1; }
fi

log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

# ---------- 1. server settings ----------
if [[ -f "$CONF" ]]; then
  log "Keeping existing settings in $CONF"
  # shellcheck disable=SC1090
  source "$CONF"
else
  log "Server settings"
  if [[ -n "$WORLD_DIR" ]]; then
    WORLD_NAME="$(basename "$WORLD_DIR")"
    echo "World name taken from folder: $WORLD_NAME"
  elif [[ -n "$WORLD_FILE" ]]; then
    WORLD_NAME="$(basename "$WORLD_FILE" .fwl)"
    echo "World name taken from file: $WORLD_NAME"
  else
    read -rp "World name [Ginnung]: " WORLD_NAME; WORLD_NAME=${WORLD_NAME:-Ginnung}
  fi
  read -rp "Server name shown in the server list [Valheim Lego]: " SERVER_NAME
  SERVER_NAME=${SERVER_NAME:-Valheim Lego}
  while :; do
    read -rsp "Server password (min 5 chars, must not contain the server name): " SERVER_PASSWORD; echo
    if (( ${#SERVER_PASSWORD} < 5 )); then echo "Too short."; continue; fi
    if [[ "${SERVER_PASSWORD,,}" == *"${SERVER_NAME,,}"* ]]; then echo "Must not contain the server name."; continue; fi
    break
  done
  install -d -m 750 "$CONF_DIR"
  cat > "$CONF" <<EOF
# Valheim server settings. After editing: sudo systemctl restart valheim
SERVER_NAME=$(printf '%q' "$SERVER_NAME")
WORLD_NAME=$(printf '%q' "$WORLD_NAME")
SERVER_PASSWORD=$(printf '%q' "$SERVER_PASSWORD")
PORT=2456
# 1 = listed in the in-game community server list (friends can search by name)
PUBLIC=1
# 1 = PlayFab relay: works behind firewalls/NAT without port forwarding,
#     gives a join code, and lets Xbox/Game Pass players join.
CROSSPLAY=1
INSTALL_DIR=$INSTALL_DIR
SAVE_DIR=$SAVE_DIR
APP_ID=$APP_ID
EOF
fi

# ---------- 2. packages ----------
log "Installing SteamCMD and libraries"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -yq software-properties-common
add-apt-repository -y multiverse >/dev/null
dpkg --add-architecture i386
echo steam steam/question select "I AGREE" | debconf-set-selections
echo steam steam/license note '' | debconf-set-selections
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -yq \
  steamcmd lib32gcc-s1 ca-certificates \
  libatomic1 libpulse0 libpulse-dev libc6 \
  ufw tar gzip

# ---------- 2b. swap on small servers ----------
mem_mb=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
if (( mem_mb < 4000 )) && [[ -z "$(swapon --show --noheadings)" ]]; then
  log "Only ${mem_mb} MB RAM and no swap - adding a 4 GB swap file"
  fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ---------- 3. user + directories ----------
log "Creating '$VH_USER' system user and folders"
id "$VH_USER" &>/dev/null || useradd --system --create-home --home-dir "$BASE_DIR" --shell /usr/sbin/nologin "$VH_USER"
install -d -o "$VH_USER" -g "$VH_USER" "$BASE_DIR" "$INSTALL_DIR" "$SAVE_DIR" "$SAVE_DIR/worlds_local"
install -d -o root -g "$VH_USER" -m 750 "$BACKUP_DIR"
chown root:"$VH_USER" "$CONF_DIR" "$CONF"; chmod 750 "$CONF_DIR"; chmod 640 "$CONF"

# ---------- 4. your world ----------
if [[ -n "$WORLD_DIR" ]]; then
  dest="$SAVE_DIR/worlds_local/$WORLD_NAME"
  if [[ -e "$dest" ]]; then
    echo "A world called $WORLD_NAME already exists on the server - not overwriting it."
  else
    cp -r "$WORLD_DIR" "$dest"
    rm -f "$dest"/cacheMinimap*          # client-only map cache
    chown -R "$VH_USER:$VH_USER" "$dest"
    echo "Copied your world to $dest"
  fi
fi
if [[ -n "$WORLD_FILE" ]]; then
  dest="$SAVE_DIR/worlds_local/$WORLD_NAME.fwl"
  if [[ -f "$SAVE_DIR/worlds_local/$WORLD_NAME.db" ]]; then
    echo "A world called $WORLD_NAME already exists on the server - not overwriting it."
  else
    install -o "$VH_USER" -g "$VH_USER" -m 644 "$WORLD_FILE" "$dest"
    echo "Placed $dest - the server will generate the world from its seed on first start."
  fi
fi

# ---------- 5. helper scripts ----------
log "Installing helper scripts"
cat > /usr/local/bin/valheim-update <<'EOF'
#!/usr/bin/env bash
# Install/update the Valheim server files via SteamCMD (runs as the valheim user)
set -euo pipefail
source /etc/valheim/valheim.env
/usr/games/steamcmd +@sSteamCmdForcePlatformType linux \
  +force_install_dir "$INSTALL_DIR" +login anonymous \
  +app_update "$APP_ID" validate +quit
EOF

cat > /usr/local/bin/valheim-start <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /etc/valheim/valheim.env
cd "$INSTALL_DIR"
export LD_LIBRARY_PATH="$INSTALL_DIR/linux64:${LD_LIBRARY_PATH:-}"
export SteamAppId=892970
args=(-nographics -batchmode
      -name "$SERVER_NAME" -port "$PORT" -world "$WORLD_NAME"
      -password "$SERVER_PASSWORD" -public "$PUBLIC"
      -savedir "$SAVE_DIR" -saveinterval 1200 -backups 4)
[[ "${CROSSPLAY:-0}" == "1" ]] && args+=(-crossplay)
exec ./valheim_server.x86_64 "${args[@]}"
EOF

cat > /usr/local/bin/valheim-backup <<EOF
#!/usr/bin/env bash
# Compressed copy of all worlds + admin/ban lists. Keeps $BACKUP_KEEP_DAYS days.
set -euo pipefail
src="$SAVE_DIR"
dst="$BACKUP_DIR"
stamp=\$(date +%Y-%m-%d_%H%M)
tar -czf "\$dst/valheim-\$stamp.tar.gz" -C "\$src" .
find "\$dst" -name 'valheim-*.tar.gz' -mtime +$BACKUP_KEEP_DAYS -delete
echo "Backup written: \$dst/valheim-\$stamp.tar.gz"
EOF

cat > /usr/local/bin/valheim-code <<'EOF'
#!/usr/bin/env bash
# Show the crossplay join code of the currently running server
since=$(systemctl show -p ActiveEnterTimestamp --value valheim)
code=$(journalctl -u valheim --since "${since:-today}" --no-pager -o cat 2>/dev/null \
       | grep -oiE 'join code [0-9]+' | tail -1 | grep -oE '[0-9]+')
if [[ -n "$code" ]]; then echo "Join code: $code"
else echo "No join code yet - the server may still be starting (takes ~1 min). Try: journalctl -u valheim -f"; fi
EOF
chmod 755 /usr/local/bin/valheim-{update,start,backup,code}

# ---------- 6. systemd ----------
log "Installing systemd units"
cat > /etc/systemd/system/valheim.service <<EOF
[Unit]
Description=Valheim dedicated server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$VH_USER
Group=$VH_USER
WorkingDirectory=$INSTALL_DIR
# Update before every start; '-' = still start if Steam is unreachable
ExecStartPre=-/usr/local/bin/valheim-update
ExecStart=/usr/local/bin/valheim-start
# SIGINT makes Valheim save the world before exiting
KillSignal=SIGINT
TimeoutStartSec=900
TimeoutStopSec=120
Restart=always
RestartSec=15
LimitNOFILE=100000
NoNewPrivileges=true
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/valheim-backup.service <<EOF
[Unit]
Description=Back up Valheim worlds

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/valheim-backup
EOF

cat > /etc/systemd/system/valheim-backup.timer <<EOF
[Unit]
Description=Daily Valheim world backup

[Timer]
OnCalendar=*-*-* 04:45 Europe/Oslo
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/valheim-nightly.service <<EOF
[Unit]
Description=Nightly Valheim restart (pulls game updates)

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl restart valheim.service
EOF

cat > /etc/systemd/system/valheim-nightly.timer <<EOF
[Unit]
Description=Nightly Valheim update + restart

[Timer]
OnCalendar=*-*-* $UPDATE_TIME Europe/Oslo
Persistent=false

[Install]
WantedBy=timers.target
EOF

# ---------- 7. firewall ----------
log "Configuring firewall (ufw)"
# Allow whatever port sshd actually listens on, so you can't lock yourself out
SSH_PORTS=$(sshd -T 2>/dev/null | awk '/^port /{print $2}' || true)
for p in ${SSH_PORTS:-22}; do ufw allow "$p/tcp" comment 'SSH' >/dev/null; done
ufw allow 2456:2458/udp comment 'Valheim' >/dev/null
ufw --force enable >/dev/null
ufw status | sed 's/^/   /'

# ---------- 8. download + start ----------
log "Downloading Valheim server (a few minutes the first time)"
sudo -u "$VH_USER" -H /usr/local/bin/valheim-update

log "Starting services"
systemctl daemon-reload
systemctl enable --now valheim-backup.timer valheim-nightly.timer
systemctl enable valheim.service
systemctl restart valheim.service

log "Done!"
cat <<EOF
  Status:     systemctl status valheim
  Live log:   journalctl -u valheim -f
  Join code:  valheim-code      (wait ~1-2 min after start)
  Settings:   sudo nano $CONF   then  sudo systemctl restart valheim
  Worlds:     $SAVE_DIR/worlds_local
  Backups:    $BACKUP_DIR  (daily 04:45, kept $BACKUP_KEEP_DAYS days)
  Updates:    automatic restart + update every night at $UPDATE_TIME
EOF
