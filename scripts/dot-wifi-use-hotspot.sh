#!/usr/bin/env bash
# Exit Setup AP (if any) and connect to the saved iPhone Personal Hotspot.
# Creates the NM profile from /var/lib/dot/wifi-pending.json when needed.
# Usage: sudo dot-wifi-use-hotspot
set -euo pipefail

STATE_DIR="/var/lib/dot"
PENDING="${STATE_DIR}/wifi-pending.json"
CONN_NAME="dot-phone-hotspot"
JOIN_BIN="/usr/local/sbin/dot-wifi-join"
LOG="/var/log/dot-wifi-use-hotspot.log"

mkdir -p "${STATE_DIR}"
touch "${LOG}" 2>/dev/null || true
log() { echo "$(date -Is) $*" | tee -a "${LOG}" >&2; }

log "use-hotspot: start"

# Always leave Setup AP — auto-join cannot work while hostapd owns wlan0
systemctl stop hostapd dnsmasq 2>/dev/null || true
systemctl disable hostapd dnsmasq 2>/dev/null || true
rm -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf
systemctl reload NetworkManager 2>/dev/null || true
nmcli device set wlan0 managed yes 2>/dev/null || true
nmcli radio wifi on 2>/dev/null || true
ip addr flush dev wlan0 2>/dev/null || true
ip link set wlan0 up 2>/dev/null || true
command -v iw >/dev/null 2>&1 && iw dev wlan0 set power_save off 2>/dev/null || true
sleep 1

ensure_profile_from_pending() {
  if nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "${CONN_NAME}"; then
    return 0
  fi
  if [[ ! -f "${PENDING}" ]]; then
    log "ERROR: no ${CONN_NAME} profile and no ${PENDING}"
    return 1
  fi
  local ssid pass
  ssid="$(python3 - "${PENDING}" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
print((d.get("ssid") or "").strip())
PY
)"
  pass="$(python3 - "${PENDING}" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("password") or "")
PY
)"
  if [[ -z "${ssid}" || ${#pass} -lt 8 ]]; then
    log "ERROR: invalid pending credentials"
    return 1
  fi
  log "Creating profile ${CONN_NAME} for ssid=${ssid}"
  nmcli connection add type wifi ifname wlan0 con-name "${CONN_NAME}" \
    ssid "${ssid}" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "${pass}" \
    connection.autoconnect yes \
    connection.autoconnect-priority 200 \
    connection.autoconnect-retries 0 \
    connection.wait-device-timeout 15 \
    ipv4.method auto \
    ipv4.dhcp-timeout 30 \
    ipv6.method ignore \
    802-11-wireless.mac-address-randomization never \
    802-11-wireless.powersave 2 \
    802-11-wireless.cloned-mac-address permanent
}

if ! ensure_profile_from_pending; then
  exit 1
fi

nmcli connection modify "${CONN_NAME}" \
  connection.autoconnect yes \
  connection.autoconnect-retries 0 \
  802-11-wireless.powersave 2 \
  802-11-wireless.mac-address-randomization never \
  2>/dev/null || true

# Stop other Wi-Fi profiles from stealing wlan0 (e.g. home router "SAMBURGER").
nmcli -t -f NAME,TYPE connection show 2>/dev/null | while IFS=: read -r name type; do
  [[ "${type}" == "802-11-wireless" || "${type}" == "wifi" ]] || continue
  [[ "${name}" == "${CONN_NAME}" ]] && continue
  log "Disable autoconnect for competing Wi-Fi «${name}»"
  nmcli connection modify "${name}" connection.autoconnect no 2>/dev/null || true
  nmcli connection down "${name}" 2>/dev/null || true
done

systemctl enable --now dot-wifi-keepalive.timer 2>/dev/null || true
systemctl start dot-wifi-watch.service 2>/dev/null || true

SSID="$(nmcli -g 802-11-wireless.ssid connection show "${CONN_NAME}" 2>/dev/null || true)"
log "Waiting for hotspot «${SSID}» and joining…"

for i in $(seq 1 24); do
  if [[ -x "${JOIN_BIN}" ]]; then
    if "${JOIN_BIN}" "${CONN_NAME}"; then
      log "SUCCESS joined"
      exit 0
    fi
  else
    nmcli device wifi rescan 2>/dev/null || true
    if nmcli -w 25 connection up "${CONN_NAME}" ifname wlan0; then
      log "SUCCESS joined (nmcli)"
      exit 0
    fi
  fi
  log "not up yet (${i}/24) — retry in 8s (keep Personal Hotspot on)"
  sleep 8
done

log "WARN: not connected yet — watch/keepalive will keep trying"
exit 0
