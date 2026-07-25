#!/usr/bin/env bash
# Join (or re-join) the saved phone-hotspot profile.
# Usage: sudo bash scripts/dot-wifi-join.sh [con-name]
#
# Anti-flap rules for iPhone Personal Hotspot:
# - If already up with IP → do nothing
# - If preparing/configuring/IP (40–90) → wait for DHCP only
# - State 30 = disconnected → MUST call connection up (do not treat as in-progress!)
set -euo pipefail

PROFILE_NAME="${1:-dot-phone-hotspot}"
STATE_DIR="${DOT_WIFI_STATE_DIR:-/var/lib/dot}"
STATUS="${STATE_DIR}/wifi-status.json"
MODE="${STATE_DIR}/wifi-mode.json"
CLIENT="${STATE_DIR}/wifi-client.json"
LOG="${DOT_WIFI_JOIN_LOG:-/var/log/dot-wifi-join.log}"
LOCK="/run/dot-wifi-join.lock"

mkdir -p "${STATE_DIR}"
touch "${LOG}" 2>/dev/null || true

exec 8>"${LOCK}"
if ! flock -n 8; then
  echo "Another join is running — skip" >&2
  exit 0
fi

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
  if [[ "${ip}" == "192.168.4.1" ]]; then
    ip=""
  fi
  printf '%s' "${ip}"
}

active_connection() {
  nmcli -g GENERAL.CONNECTION device show wlan0 2>/dev/null || true
}

# Numeric NM device state (first token), e.g. "30" from "30 (disconnected)"
device_state_num() {
  nmcli -g GENERAL.STATE device show wlan0 2>/dev/null | awk '{print $1; exit}' || true
}

device_state_raw() {
  nmcli -g GENERAL.STATE device show wlan0 2>/dev/null || true
}

profile_ssid() {
  nmcli -g 802-11-wireless.ssid connection show "${PROFILE_NAME}" 2>/dev/null || true
}

link_is_ok() {
  local ip conn num
  ip="$(current_ip)"
  conn="$(active_connection)"
  num="$(device_state_num)"
  [[ -n "${ip}" && "${conn}" == "${PROFILE_NAME}" && "${num}" == "100" ]]
}

# Truly associating / getting IP — NOT disconnected (30).
link_is_progress() {
  local conn num
  conn="$(active_connection)"
  num="$(device_state_num)"
  case "${num}" in
    40|50|60|70|80|90) return 0 ;;
  esac
  # Activating our profile but not yet fully up
  if [[ "${conn}" == "${PROFILE_NAME}" && "${num}" != "100" && "${num}" != "30" && "${num}" != "120" && "${num}" != "20" && "${num}" != "10" && "${num}" != "0" ]]; then
    # e.g. 110 deactivating — not progress for join
    if [[ "${num}" == "110" ]]; then
      return 1
    fi
  fi
  if [[ "${conn}" == "${PROFILE_NAME}" && -z "$(current_ip)" ]]; then
    case "${num}" in
      40|50|60|70|80|90) return 0 ;;
    esac
  fi
  return 1
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
  local gw
  gw="$(ip route show default dev wlan0 2>/dev/null | awk '{print $3; exit}' || true)"
  if [[ -n "${gw}" ]]; then
    ping -c 1 -W 1 "${gw}" >/dev/null 2>&1 || true
  fi
  command -v iw >/dev/null 2>&1 && iw dev wlan0 set power_save off 2>/dev/null || true
}

wait_for_dhcp() {
  local i
  for i in $(seq 1 35); do
    if link_is_ok; then
      return 0
    fi
    if link_is_progress; then
      sleep 1
      continue
    fi
    # Disconnected / failed mid-wait
    return 1
  done
  link_is_ok
}

exit_setup_ap() {
  systemctl stop hostapd dnsmasq 2>/dev/null || true
  systemctl disable hostapd dnsmasq 2>/dev/null || true
  if [[ -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf ]]; then
    rm -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf
    systemctl reload NetworkManager 2>/dev/null || true
    sleep 1
  fi
  nmcli device set wlan0 managed yes 2>/dev/null || true
  nmcli radio wifi on 2>/dev/null || true
  # Drop leftover AP address
  if ip -4 addr show wlan0 2>/dev/null | grep -q '192.168.4.1'; then
    ip addr flush dev wlan0 2>/dev/null || true
  fi
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

if link_is_ok; then
  keepalive_traffic
  mark_client_ok
  log "Already connected ip=$(current_ip) — no-op"
  exit 0
fi

if link_is_progress; then
  log "Link in progress state=$(device_state_raw) — waiting for DHCP"
  write_status "switching" 0 "Waiting for IP on hotspot…"
  if wait_for_dhcp; then
    keepalive_traffic
    mark_client_ok
    log "Joined after DHCP wait ip=$(current_ip)"
    exit 0
  fi
  log "DHCP wait ended without IP — will connection up"
fi

exit_setup_ap

WANT_SSID="$(profile_ssid)"
write_status "switching" 0 "Joining «${WANT_SSID:-hotspot}»…"
log "Join ${PROFILE_NAME} ssid=${WANT_SSID:-?} state=$(device_state_raw) conn=$(active_connection)"

# Ensure forever-autoconnect (NM: 0 = forever)
nmcli connection modify "${PROFILE_NAME}" \
  connection.autoconnect yes \
  connection.autoconnect-retries 0 \
  2>/dev/null || true

# While fully down, one rescan then connection up is OK
nmcli device wifi rescan 2>/dev/null || true
sleep 2

for attempt in 1 2 3 4 5; do
  if link_is_ok; then
    break
  fi
  if link_is_progress; then
    if wait_for_dhcp; then
      break
    fi
  fi
  log "connection up attempt ${attempt} (state=$(device_state_raw))"
  nmcli -w 40 connection up "${PROFILE_NAME}" ifname wlan0 2>>"${LOG}" || true
  if wait_for_dhcp; then
    break
  fi
  sleep 3
done

if link_is_ok; then
  keepalive_traffic
  mark_client_ok
  log "Joined ${WANT_SSID} ip=$(current_ip)"
  exit 0
fi

IP="$(current_ip)"
log "WARN: join incomplete state=$(device_state_raw) conn=$(active_connection) ip=${IP:-none}"
write_status "error" 0 "Could not join «${WANT_SSID:-hotspot}». Keep Personal Hotspot on + Maximize Compatibility."
exit 1
