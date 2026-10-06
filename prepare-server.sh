#!/usr/bin/env bash
# Base setup for a fresh Ubuntu 24.04 server. Run once, before install.sh:
#   sudo bash prepare-server.sh               # base setup
#   sudo bash prepare-server.sh --tailscale   # + Tailscale, so you can reach the
#                                             #   server by name from anywhere
#
# - installs all updates
# - sets the timezone to Europe/Oslo
# - installs/enables the SSH server
# - turns on automatic security updates (with a reboot at 04:15 when needed)
# - installs fail2ban to block SSH password-guessing
# - turns off SSH password login IF you already have an SSH key set up
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
log() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
ADMIN_USER=${SUDO_USER:-}
TAILSCALE=0
for a in "$@"; do
  case "$a" in
    --tailscale) TAILSCALE=1 ;;
    *) echo "Unknown option: $a" >&2; exit 1 ;;
  esac
done

log "Installing all updates (can take a while on a fresh install)"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get -yq -o Dpkg::Options::=--force-confold full-upgrade
DEBIAN_FRONTEND=noninteractive apt-get install -yq \
  openssh-server unattended-upgrades fail2ban python3-systemd \
  nano htop curl tar gzip
apt-get -yq autoremove

log "Setting timezone to Europe/Oslo"
timedatectl set-timezone Europe/Oslo
timedatectl set-ntp true || true

log "Enabling SSH"
systemctl enable --now ssh

log "Turning on automatic security updates"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
cat > /etc/apt/apt.conf.d/52valheim-auto-reboot <<'EOF'
// Reboot for kernel updates at a quiet hour (the Valheim service starts again by itself)
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:15";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
systemctl enable --now unattended-upgrades

log "Configuring fail2ban for SSH"
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
backend  = systemd
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF
systemctl enable fail2ban
systemctl restart fail2ban

if (( TAILSCALE )); then
  log "Installing Tailscale"
  command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
  systemctl enable --now tailscaled
  echo "Open the link below on your PC and log in to connect this server to your Tailscale account:"
  tailscale up --hostname=valheim
  echo "Tailscale address: $(tailscale ip -4 2>/dev/null | head -1)   name: valheim"
fi

log "SSH login settings"
keyfile=""
[[ -n "$ADMIN_USER" ]] && keyfile="$(getent passwd "$ADMIN_USER" | cut -d: -f6)/.ssh/authorized_keys"
if [[ -n "$keyfile" && -s "$keyfile" ]]; then
  cat > /etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
  sshd -t && systemctl reload ssh
  echo "SSH key found for $ADMIN_USER - password login over SSH is now OFF (keys only)."
  echo "Keep this session open and test 'ssh $ADMIN_USER@<server>' from your PC in a new terminal."
else
  echo "No SSH key found for ${ADMIN_USER:-this user} - leaving password login ON."
  echo "Set up a key from your PC (see README, step 3) and re-run this script to lock it down."
fi

log "Done"
echo "  Server IP address(es): $(hostname -I)"
(( TAILSCALE )) && echo "  From your PC (with Tailscale running):  ssh $ADMIN_USER@valheim"
if [[ -f /var/run/reboot-required ]]; then
  echo "  A reboot is needed for the updates:  sudo reboot"
  echo "  Then log in again and run:            sudo bash install.sh --world-dir ~/Ginnung"
else
  echo "  Next:  sudo bash install.sh --world-dir ~/Ginnung"
fi
