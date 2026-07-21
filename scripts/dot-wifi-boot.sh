#!/usr/bin/env bash
# On boot:
# - role setup (default) → Dot-Setup AP (no modem assumed)
# - role client → join saved iPhone Personal Hotspot
set -euo pipefail

STATE_DIR="${DOT_WIFI_STATE_DIR:-/var/lib/dot}"
ROLE_FILE="${STATE_DIR}/wifi-role"
PROFILE_NAME="${DOT_WIFI_PROFILE_NAME:-dot-phone-hotspot}"
ENTER_SETUP="/usr/local/sbin/dot-enter-setup-ap"
JOIN_BIN="/usr/local/sbin/dot-wifi-join"
USE_BIN="/usr/local/sbin/dot-wifi-use-hotspot"
LOG="/var/log/dot-wifi-boot.log"

log() {
  echo "$(date -Is) $*" | tee -a "$LOG" >&2
}

mkdir -p "$STATE_DIR"
chmod 755 "$STATE_DIR" 2>/dev/null || true

wifi_role() {
  if [[ -f "${ROLE_FILE}" ]]; then
    tr -d '[:space:]' <"${ROLE_FILE}"
  else
    echo "setup"
  fi
}

# Wait for NetworkManager / wlan0
for _ in $(seq 1 60); do
  if command -v nmcli >/dev/null 2>&1 && ip link show wlan0 >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

role="$(wifi_role)"
log "boot wifi-role=${role}"

# Default / first-time: Setup AP only — do not assume a modem is available.
if [[ "${role}" != "client" ]]; then
  log "Role is setup — starting Dot-Setup AP (no modem auto-join)"
  if [[ -x "$ENTER_SETUP" ]]; then
    exec "$ENTER_SETUP"
  fi
  log "ERROR: $ENTER_SETUP missing — run scripts/install-wifi-provision.sh"
  exit 1
fi

# Client role: join phone hotspot
if ! nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "$PROFILE_NAME"; then
  log "Client role but no profile — falling back to Setup AP"
  echo "setup" >"${ROLE_FILE}"
  if [[ -x "$ENTER_SETUP" ]]; then
    exec "$ENTER_SETUP"
  fi
  exit 1
fi

log "Client role — joining phone hotspot"
if [[ -x "${USE_BIN}" ]]; then
  "${USE_BIN}" || true
  exit 0
fi

nmcli radio wifi on 2>/dev/null || true
if systemctl is-active --quiet hostapd 2>/dev/null; then
  systemctl stop hostapd dnsmasq 2>/dev/null || true
  rm -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf
  systemctl reload NetworkManager 2>/dev/null || true
  nmcli device set wlan0 managed yes 2>/dev/null || true
fi

nmcli connection modify "$PROFILE_NAME" \
  connection.autoconnect yes \
  connection.autoconnect-retries 0 \
  2>/dev/null || true

for attempt in $(seq 1 12); do
  if [[ -x "${JOIN_BIN}" ]] && "${JOIN_BIN}" "${PROFILE_NAME}"; then
    log "Joined hotspot (attempt ${attempt})"
    exit 0
  fi
  log "Hotspot not ready (attempt ${attempt}/12)"
  sleep 10
done

log "WARN: hotspot join not ready at boot — watch will keep trying"
exit 0
