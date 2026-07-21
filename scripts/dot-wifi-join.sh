#!/usr/bin/env bash
# Join (or re-join) the saved phone-hotspot profile.
# Usage: sudo bash scripts/dot-wifi-join.sh [con-name]
#
# Anti-flap rules for iPhone Personal Hotspot:
# - If already up with IP → do nothing (no rescan / modify / connection up)
# - If associating / getting IP → only wait for DHCP (never connection up again)
# - At most ONE `nmcli connection up` per invoke unless fully disconnected
# - Never wifi rescan while connected or connecting
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
  # Ignore leftover setup-AP address
  if [[ "${ip}" == "192.168.4.1" ]]; then
    ip=""
  fi
  printf '%s' "${ip}"
}

active_connection() {
  nmcli -g GENERAL.CONNECTION device show wlan0 2>/dev/null || true
}

device_state() {
  nmcli -g GENERAL.STATE device show wlan0 2>/dev/null || true
}

profile_ssid() {
  nmcli -g 802-11-wireless.ssid connection show "${PROFILE_NAME}" 2>/dev/null || true
}

# Fully online on the right profile.
link_is_ok() {
  local ip conn state
  ip="$(current_ip)"
  conn="$(active_connection)"
  state="$(device_state)"
  [[ -n "${ip}" && "${conn}" == "${PROFILE_NAME}" && ( "${state}" == 100* || "${state}" == *"connected"* ) ]]
}

# Association in progress — wait, do not bounce.
link_is_progress() {
  local conn state
  conn="$(active_connection)"
  state="$(device_state)"
  if [[ "${conn}" == "${PROFILE_NAME}" ]]; then
    return 0
  fi
  # 10 = connecting, 20..99 = various connecting states on some NM versions
  case "${state}" in
    10*|20*|30*|40*|50*|60*|70*|80*|90*|*"connecting"*|*"configuring"*|*"ip"* ) return 0 ;;
  esac
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
  for i in $(seq 1 30); do
    if link_is_ok; then
      return 0
    fi
    # Still on profile without IP — keep waiting (do not connection up).
    if ! link_is_progress && [[ -z "$(current_ip)" ]]; then
      # Fully dropped mid-wait
      return 1
    fi
    sleep 1
  done
  link_is_ok
}

ensure_radio_quiet() {
  # Stop Setup AP if leftover — but do not reload NM if already client-managed.
  if systemctl is-active --quiet hostapd 2>/dev/null; then
    systemctl stop hostapd dnsmasq 2>/dev/null || true
    systemctl disable hostapd 2>/dev/null || true
    rm -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf
    systemctl reload NetworkManager 2>/dev/null || true
    sleep 1
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

# Already good — never touch the radio.
if link_is_ok; then
  keepalive_traffic
  mark_client_ok
  log "Already connected ip=$(current_ip) — no-op"
  exit 0
fi

# Associating / DHCP in progress — only wait.
if link_is_progress; then
  log "Link in progress conn=$(active_connection) state=$(device_state) — waiting for DHCP"
  write_status "switching" 0 "Waiting for IP on hotspot…"
  if wait_for_dhcp; then
    keepalive_traffic
    mark_client_ok
    log "Joined after DHCP wait ip=$(current_ip)"
    exit 0
  fi
  log "DHCP wait failed — will try one connection up"
fi

ensure_radio_quiet

WANT_SSID="$(profile_ssid)"
write_status "switching" 0 "Joining «${WANT_SSID:-hotspot}»…"
log "One-shot join ${PROFILE_NAME} (ssid=${WANT_SSID:-?})"

# One association only. No rescan loop — rescans drop iPhone hotspot links.
if ! link_is_ok && ! link_is_progress; then
  if ! nmcli -w 45 connection up "${PROFILE_NAME}" ifname wlan0 2>>"${LOG}"; then
    log "connection up returned error — waiting in case NM still associates"
  fi
fi

if wait_for_dhcp; then
  keepalive_traffic
  mark_client_ok
  log "Joined ${WANT_SSID} ip=$(current_ip)"
  exit 0
fi

# Second chance only if completely disconnected (not if flapping mid-associate).
if ! link_is_progress && ! link_is_ok; then
  log "Retry one more connection up after full disconnect"
  sleep 3
  nmcli -w 45 connection up "${PROFILE_NAME}" ifname wlan0 2>>"${LOG}" || true
  if wait_for_dhcp; then
    keepalive_traffic
    mark_client_ok
    log "Joined on retry ${WANT_SSID} ip=$(current_ip)"
    exit 0
  fi
fi

IP="$(current_ip)"
log "WARN: join incomplete conn=$(active_connection) state=$(device_state) ip=${IP:-none}"
write_status "error" 0 "Could not join «${WANT_SSID:-hotspot}». Keep Personal Hotspot on, Maximize Compatibility, unlocked screen."
exit 1
