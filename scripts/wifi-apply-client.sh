#!/usr/bin/env bash
# Apply pending Wi-Fi client config (iPhone Personal Hotspot).
# Invoked by systemd when /var/lib/dot/wifi-request.json appears.
# Or manually: sudo bash scripts/wifi-apply-client.sh
set -euo pipefail

STATE_DIR="/var/lib/dot"
REQUEST="${STATE_DIR}/wifi-request.json"
STATUS="${STATE_DIR}/wifi-status.json"
MODE="${STATE_DIR}/wifi-mode.json"
CONN_NAME="dot-phone-hotspot"

mkdir -p "${STATE_DIR}"

if [[ ! -f "${REQUEST}" ]]; then
  echo "No ${REQUEST}" >&2
  exit 1
fi

write_status() {
  local mode="$1" ok="$2" msg="$3" ip="${4:-}"
  python3 - "${STATUS}" "${MODE}" "${mode}" "${ok}" "${msg}" "${ip}" <<'PY'
import json, sys, datetime
path, mode_path, mode, ok, msg, ip = sys.argv[1:7]
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
payload = {
    "ok": ok == "1",
    "mode": mode,
    "message": msg,
    "ip": ip or None,
    "updated_at": now,
}
open(path, "w").write(json.dumps(payload) + "\n")
open(mode_path, "w").write(json.dumps({"mode": mode, "ip": ip or None, "message": msg}) + "\n")
PY
}

read_request() {
  python3 - "${REQUEST}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
ssid = (data.get("ssid") or "").strip()
password = data.get("password") or ""
if not ssid:
    raise SystemExit("missing ssid")
if len(password) < 8:
    raise SystemExit("password must be at least 8 characters")
print(ssid)
print(password)
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

already_on_ssid() {
  local want="$1"
  local active
  active="$(nmcli -t -f ACTIVE,SSID device wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}')"
  [[ -n "${active}" && "${active}" == "${want}" ]]
}

mapfile -t CREDS < <(read_request)
SSID="${CREDS[0]}"
PASS="${CREDS[1]}"

write_status "switching" 0 "Stopping setup AP and joining ${SSID}…"

# Tear down AP
systemctl stop hostapd dnsmasq 2>/dev/null || true
systemctl disable hostapd 2>/dev/null || true

# Return wlan0 to NetworkManager
rm -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf
systemctl reload NetworkManager 2>/dev/null || true
nmcli device set wlan0 managed yes 2>/dev/null || true
nmcli radio wifi on 2>/dev/null || true
ip addr flush dev wlan0 2>/dev/null || true
ip link set wlan0 up || true
sleep 2

# Drop old profiles that collide (by our name or by SSID)
nmcli -t -f NAME,UUID,TYPE connection show 2>/dev/null | while IFS=: read -r name uuid type; do
  [[ "${type}" == "802-11-wireless" || "${type}" == "wifi" ]] || continue
  if [[ "${name}" == "${CONN_NAME}" || "${name}" == "${SSID}" ]]; then
    nmcli connection delete uuid "${uuid}" 2>/dev/null || true
  fi
done

# Wait until the hotspot is visible (iPhone hotspot can appear late)
visible=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  nmcli device wifi rescan 2>/dev/null || true
  sleep 2
  if nmcli -t -f SSID device wifi list 2>/dev/null | grep -Fxq "${SSID}"; then
    visible=1
    break
  fi
  echo "Waiting for SSID «${SSID}»…"
done

nmcli connection add type wifi ifname wlan0 con-name "${CONN_NAME}" \
  ssid "${SSID}" \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk "${PASS}" \
  connection.autoconnect yes \
  ipv4.method auto ipv6.method ignore \
  || {
    write_status "error" 0 "Failed to create Wi-Fi connection profile"
    exit 1
  }

connected=0
for attempt in 1 2 3 4 5; do
  echo "Connect attempt ${attempt}…"
  if nmcli -w 30 connection up "${CONN_NAME}" ifname wlan0; then
    connected=1
    break
  fi
  # Hotspot may have been off briefly
  nmcli device wifi rescan 2>/dev/null || true
  sleep 3
done

IP="$(current_ip)"
if [[ "${connected}" -ne 1 ]]; then
  # Sometimes NM associates under another profile / delayed DHCP
  if already_on_ssid "${SSID}" && [[ -n "${IP}" ]]; then
    connected=1
  fi
fi

if [[ "${connected}" -ne 1 || -z "${IP}" ]]; then
  # Last chance: wait for DHCP if associated
  for _ in 1 2 3 4 5 6; do
    IP="$(current_ip)"
    if already_on_ssid "${SSID}" && [[ -n "${IP}" ]]; then
      connected=1
      break
    fi
    sleep 2
  done
fi

if [[ "${connected}" -ne 1 || -z "${IP}" ]]; then
  write_status "error" 0 "Could not join «${SSID}». Check hotspot name/password, then reopen setup AP."
  mv -f "${REQUEST}" "${STATE_DIR}/wifi-request.failed.json" 2>/dev/null || true
  exit 1
fi

rm -f "${REQUEST}" "${STATE_DIR}/wifi-request.failed.json"
write_status "client" 1 "Connected to «${SSID}»" "${IP}"

python3 - "${STATE_DIR}/wifi-client.json" "${SSID}" "${IP}" <<'PY'
import json, sys, datetime
path, ssid, ip = sys.argv[1:4]
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
open(path, "w").write(json.dumps({
    "ssid": ssid,
    "ip": ip or None,
    "updated_at": now,
}) + "\n")
PY

echo "Connected to ${SSID} ip=${IP}"
