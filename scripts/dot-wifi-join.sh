#!/usr/bin/env bash
# Join (or re-join) the saved phone-hotspot profile quickly and reliably.
# Usage: sudo bash scripts/dot-wifi-join.sh [con-name]
#
# Important: do NOT call `nmcli connection modify` or `wifi rescan` while the
# link is already up — that causes connect/disconnect flapping on iPhone hotspots.
set -euo pipefail

PROFILE_NAME="${1:-dot-phone-hotspot}"
STATE_DIR="${DOT_WIFI_STATE_DIR:-/var/lib/dot}"
STATUS="${STATE_DIR}/wifi-status.json"
MODE="${STATE_DIR}/wifi-mode.json"
CLIENT="${STATE_DIR}/wifi-client.json"
LOG="${DOT_WIFI_JOIN_LOG:-/var/log/dot-wifi-join.log}"
HARDEN_FLAG="${STATE_DIR}/.hotspot-profile-hardened"

mkdir -p "${STATE_DIR}"
touch "${LOG}" 2>/dev/null || true

log() { echo "$(date -Is) $*" | tee -a "${LOG}" >&2; }

write_status() {
  local mode="$1" ok="$2" msg="$3" ip="${4:-}"
  python3 - "${STATUS}" "${MODE}" "${mode}" "${ok}" "${msg}" "${ip}" <<'PY'
import json, sys, datetime
path, mode_path, mode, ok, msg, ip = sys.argv[1:7]
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
payload = {"ok": ok == "1", "mode": mode, "message": msg, "ip": ip or None, "updated_at": now}
open(path, "w").write(json.dumps(payload) + "\n")
open(mode_path, "w").write(json.dumps({"mode": mode, "ip": ip or None, "message": msg}) + "\n")
PY
}

current_ip() {
  local ip=""
  ip="$(nmcli -g IP4.ADDRESS device show wlan0 2>/dev/null | head -n1 | cut -d/ -f1 || true)"
  if [[ -z "${ip}" ]]; then
    ip="$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)"
  fi
  printf '%s' "${ip}"
}

active_connection() {
  nmcli -g GENERAL.CONNECTION device show wlan0 2>/dev/null || true
}

device_connected() {
  local state
  state="$(nmcli -g GENERAL.STATE device show wlan0 2>/dev/null || true)"
  [[ "${state}" == 100* || "${state}" == *"connected"* ]]
}

profile_ssid() {
  nmcli -g 802-11-wireless.ssid connection show "${PROFILE_NAME}" 2>/dev/null || true
}

# Stable health check — do not rely on wifi list ACTIVE flag (often empty while online).
link_is_ok() {
  local ip conn
  ip="$(current_ip)"
  conn="$(active_connection)"
  [[ -n "${ip}" && "${conn}" == "${PROFILE_NAME}" && "$(device_connected && echo yes)" == "yes" ]]
}

mark_client_ok() {
  local ip ssid
  ip="$(current_ip)"
  ssid="$(profile_ssid)"
  write_status "client" 1 "Connected to «${ssid:-hotspot}»" "${ip}"
  python3 - "${CLIENT}" "${ssid:-hotspot}" "${ip}" <<'PY'
import json, sys, datetime
path, ssid, ip = sys.argv[1:4]
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
open(path, "w").write(json.dumps({"ssid": ssid, "ip": ip or None, "updated_at": now}) + "\n")
PY
}

keepalive_traffic() {
  # iPhone often drops idle clients; a quiet ping to the gateway keeps the lease.
  local gw
  gw="$(ip route show default dev wlan0 2>/dev/null | awk '{print $3; exit}' || true)"
  if [[ -n "${gw}" ]]; then
    ping -c 1 -W 1 "${gw}" >/dev/null 2>&1 || true
  fi
  command -v iw >/dev/null 2>&1 && iw dev wlan0 set power_save off 2>/dev/null || true
}

harden_profile_once() {
  # Only once — modifying an active profile can force a reconnect flap.
  if [[ -f "${HARDEN_FLAG}" ]]; then
    return 0
  fi
  nmcli connection modify "${PROFILE_NAME}" \
    connection.autoconnect yes \
    connection.autoconnect-priority 200 \
    connection.autoconnect-retries 0 \
    connection.wait-device-timeout 8 \
    ipv4.method auto \
    ipv4.dhcp-timeout 20 \
    ipv6.method ignore \
    802-11-wireless.mac-address-randomization never \
    802-11-wireless.powersave 2 \
    2>/dev/null || true
  touch "${HARDEN_FLAG}" 2>/dev/null || true
}

ensure_radio() {
  if systemctl is-active --quiet hostapd 2>/dev/null; then
    systemctl stop hostapd dnsmasq 2>/dev/null || true
    rm -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf
    systemctl reload NetworkManager 2>/dev/null || true
  fi
  nmcli device set wlan0 managed yes 2>/dev/null || true
  nmcli radio wifi on 2>/dev/null || true
  ip link set wlan0 up 2>/dev/null || true
  command -v iw >/dev/null 2>&1 && iw dev wlan0 set power_save off 2>/dev/null || true
}

if ! command -v nmcli >/dev/null 2>&1; then
  log "ERROR: nmcli missing"
  exit 1
fi

if ! nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "${PROFILE_NAME}"; then
  log "No profile ${PROFILE_NAME}"
  exit 2
fi

# If already online on the right profile — do NOT rescan / modify / connection up.
if link_is_ok; then
  keepalive_traffic
  mark_client_ok
  exit 0
fi

ensure_radio
harden_profile_once

WANT_SSID="$(profile_ssid)"
write_status "switching" 0 "Joining «${WANT_SSID:-hotspot}»…"
log "Joining ${PROFILE_NAME} (ssid=${WANT_SSID:-?})"

connected=0
if [[ "${DOT_WIFI_JOIN_QUICK:-0}" == "1" ]]; then
  max_attempts=2
else
  max_attempts=6
fi

for attempt in $(seq 1 "${max_attempts}"); do
  # Re-check each round — NM autoconnect may have won already.
  if link_is_ok; then
    connected=1
    break
  fi
  # Rescan only while down (rescan while up can drop the association).
  nmcli device wifi rescan 2>/dev/null || true
  wait_s=10
  if [[ "${DOT_WIFI_JOIN_QUICK:-0}" != "1" && "${attempt}" -ge 3 ]]; then
    wait_s=15
  fi
  if nmcli -w "${wait_s}" connection up "${PROFILE_NAME}" ifname wlan0 2>>"${LOG}"; then
    connected=1
    break
  fi
  command -v iw >/dev/null 2>&1 && iw dev wlan0 set power_save off 2>/dev/null || true
  sleep 0.5
done

# DHCP can lag association by a few seconds
for _ in 1 2 3 4 5 6 7 8; do
  if link_is_ok; then
    connected=1
    break
  fi
  sleep 1
done

if ! link_is_ok; then
  IP="$(current_ip)"
  log "WARN: join incomplete conn=$(active_connection) ip=${IP:-none}"
  write_status "error" 0 "Could not join «${WANT_SSID:-hotspot}». Keep Personal Hotspot on (Maximize Compatibility + unlocked screen help)."
  exit 1
fi

keepalive_traffic
mark_client_ok
log "Joined ${WANT_SSID} ip=$(current_ip)"
exit 0
