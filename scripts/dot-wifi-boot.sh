#!/usr/bin/env bash
# On boot: if phone hotspot is not configured yet, start Dot-Setup AP.
# If configured, try joining the phone hotspot (NM autoconnect / connection up).
set -euo pipefail

STATE_DIR="${DOT_WIFI_STATE_DIR:-/var/lib/dot}"
PROFILE_NAME="${DOT_WIFI_PROFILE_NAME:-dot-phone-hotspot}"
ENTER_SETUP="/usr/local/sbin/dot-enter-setup-ap"
LOG="/var/log/dot-wifi-boot.log"

log() {
  echo "$(date -Is) $*" | tee -a "$LOG" >&2
}

mkdir -p "$STATE_DIR"
chmod 755 "$STATE_DIR" 2>/dev/null || true

# Wait for NetworkManager / wlan0
for _ in $(seq 1 60); do
  if command -v nmcli >/dev/null 2>&1 && ip link show wlan0 >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

has_hotspot_profile() {
  nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$PROFILE_NAME"
}

# First boot / never configured: open setup AP automatically (no SSH needed).
if ! has_hotspot_profile; then
  log "No hotspot profile — starting Dot-Setup AP"
  if [[ -x "$ENTER_SETUP" ]]; then
    exec "$ENTER_SETUP"
  fi
  log "ERROR: $ENTER_SETUP missing — run scripts/install-wifi-provision.sh"
  exit 1
fi

# Already configured: bring up saved phone-hotspot profile.
log "Hotspot profile present — attempting client join"
nmcli radio wifi on 2>/dev/null || true
# Tear down leftover setup AP if any
if systemctl is-active --quiet hostapd 2>/dev/null; then
  systemctl stop hostapd dnsmasq 2>/dev/null || true
  rm -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf
  systemctl reload NetworkManager 2>/dev/null || true
  nmcli device set wlan0 managed yes 2>/dev/null || true
fi

nmcli device wifi rescan 2>/dev/null || true
sleep 2
if nmcli -w 45 connection up "$PROFILE_NAME" ifname wlan0; then
  ip="$(nmcli -g IP4.ADDRESS device show wlan0 2>/dev/null | head -n1 | cut -d/ -f1 || true)"
  log "Joined hotspot ip=${ip:-unknown}"
else
  log "WARN: hotspot join failed (phone Personal Hotspot may be off) — will retry via NM autoconnect"
fi

exit 0
