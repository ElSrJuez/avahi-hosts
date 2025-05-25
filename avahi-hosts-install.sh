#!/usr/bin/env bash  
# avahi-hosts-install.sh – minimal interactive installer  
# (c) 2024  MIT-licensed – ship it with your repo.  
  
set -euo pipefail  
  
#── little helpers ────────────────────────────────────────────────────────────  
say()  { printf '\e[32m[INFO]\e[0m  %s\n' "$*"; }  
warn() { printf '\e[33m[WARN]\e[0m  %s\n' "$*"; }  
die()  { printf '\e[31m[FAIL]\e[0m  %s\n' "$*\n" >&2; exit 1; }  
  
[[ $EUID -eq 0 ]] || die "Run this installer with sudo or as root."  
  
#── paths ─────────────────────────────────────────────────────────────────────  
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"  
SRC_SCRIPT="${REPO_DIR}/avahi-hosts.sh"  
[[ -f $SRC_SCRIPT ]] || die "Cannot find ${SRC_SCRIPT}"  
  
DST_SCRIPT="/usr/local/bin/avahi-hosts.sh"  
SERVICE_FILE="/etc/systemd/system/avahi-hosts.service"  
TIMER_FILE="/etc/systemd/system/avahi-hosts.timer"  
  
#── gather user input (with sensible defaults) ───────────────────────────────  
default_custom="/etc/pihole/custom.list"  
[[ -f $default_custom ]] || default_custom="/var/lib/pihole/custom.list"  
  
read -r -p "Path to Pi-hole custom.list [${default_custom}]: " CUSTOM_LIST  
CUSTOM_LIST="${CUSTOM_LIST:-$default_custom}"  
  
read -r -p "Hostname suffix to use [.lan]: " HOST_SUFFIX  
HOST_SUFFIX="${HOST_SUFFIX:-.lan}"  
  
read -r -p "Run every … (systemd time, e.g. 1h, 30min) [1h]: " RUN_EVERY  
RUN_EVERY="${RUN_EVERY:-1h}"  
  
say "Summary:"  
echo "  custom.list : ${CUSTOM_LIST}"  
echo "  suffix      : ${HOST_SUFFIX}"  
echo "  interval    : ${RUN_EVERY}"  
echo  
  
#── show existing units (if any) and ask before overwriting ──────────────────  
if systemctl list-unit-files | grep -q '^avahi-hosts\.service'; then  
    warn "Existing avahi-hosts.service:"  
    systemctl cat avahi-hosts.service || true  
    read -r -p "Overwrite service? [y/N] " ans  
    [[ ${ans,,} == "y" ]] || die "Aborted by user."  
fi  
if systemctl list-unit-files | grep -q '^avahi-hosts\.timer'; then  
    warn "Existing avahi-hosts.timer:"  
    systemctl cat avahi-hosts.timer || true  
    read -r -p "Overwrite timer? [y/N] " ans  
    [[ ${ans,,} == "y" ]] || die "Aborted by user."  
fi  
  
#── 1. install / update the helper script ────────────────────────────────────  
if [[ ! -f $DST_SCRIPT || $SRC_SCRIPT -nt $DST_SCRIPT ]]; then  
    say "Installing ${DST_SCRIPT}"  
    install -m 0755 "$SRC_SCRIPT" "$DST_SCRIPT"  
else  
    say "${DST_SCRIPT} already up-to-date."  
fi  
  
#── 2. write the service unit ────────────────────────────────────────────────  
say "Writing ${SERVICE_FILE}"  
cat > "$SERVICE_FILE" <<EOF  
[Unit]  
Description=Update Pi-hole custom.list from Avahi scan  
After=network-online.target  
Wants=network-online.target  
  
[Service]  
Type=oneshot  
ExecStart=/usr/local/bin/avahi-hosts.sh -f ${CUSTOM_LIST} -s ${HOST_SUFFIX}  
User=root  
EOF  
  
#── 3. write the timer unit ──────────────────────────────────────────────────  
say "Writing ${TIMER_FILE}"  
cat > "$TIMER_FILE" <<EOF  
[Unit]  
Description=Run avahi-hosts.sh every ${RUN_EVERY}  
  
[Timer]  
OnBootSec=10min  
OnUnitActiveSec=${RUN_EVERY}  
Persistent=true  
  
[Install]  
WantedBy=timers.target  
EOF  
  
#── 4. enable & start ────────────────────────────────────────────────────────  
say "Reloading systemd and enabling timer"  
systemctl daemon-reload  
systemctl enable --now avahi-hosts.timer  
  
say "Next scheduled runs:"  
systemctl list-timers avahi-hosts.timer --all | head -n 4  
say "Installation complete."  
