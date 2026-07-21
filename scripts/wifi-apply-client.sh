#!/usr/bin/env bash
# Apply pending Wi-Fi client config (iPhone Personal Hotspot).
# Invoked by systemd when /var/lib/dot/wifi-request.json appears.
#
# Critical anti-flap: do NOT rescan after creating an autoconnect profile —
# NM may already be associating; rescans tear down iPhone hotspot links.
set -euo pipefail

STATE_DIR="/var/lib/dot"
REQUEST="${STATE_DIR}/wifi-request.json"
STATUS="${STATE_DIR}/wifi-status.json"
MODE="${STATE_DIR}/wifi-mode.json"
CONN_NAME="dot-phone-hotspot"
JOIN_BIN="/usr/local/sbin/dot-wifi-join"
LOCK="/run/dot-wifi-apply.lock"

mkdir -p "${STATE_DIR}"

exec 9>"${LOCK}"
if ! flock -n 9; then
  echo "Another wifi-apply is already running — skip" >&2
  exit 0
fi

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

mapfile -t CREDS < <(read_request)
SSID="${CREDS[0]}"
PASS="${CREDS[1]}"

write_status "switching" 0 "Stopping setup AP and joining ${SSID}…"

# Tear down Setup AP once and keep it off
systemctl stop hostapd dnsmasq 2>/dev/null || true
systemctl disable hostapd dnsmasq 2>/dev/null || true
rm -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf
systemctl reload NetworkManager 2>/dev/null || true
nmcli device set wlan0 managed yes 2>/dev/null || true
nmcli radio wifi on 2>/dev/null || true
command -v iw >/dev/null 2>&1 && iw dev wlan0 set power_save off 2>/dev/null || true
ip addr flush dev wlan0 2>/dev/null || true
ip link set wlan0 up || true
sleep 1

# Optional: one rescan BEFORE profile exists (still fully disconnected)
nmcli device wifi rescan 2>/dev/null || true
sleep 2

# Drop colliding profiles
nmcli -t -f NAME,UUID,TYPE connection show 2>/dev/null | while IFS=: read -r name uuid type; do
  [[ "${type}" == "802-11-wireless" || "${type}" == "wifi" ]] || continue
  if [[ "${name}" == "${CONN_NAME}" || "${name}" == "${SSID}" ]]; then
    nmcli connection delete uuid "${uuid}" 2>/dev/null || true
  fi
done

# Create profile. Autoconnect on for reboot; join helper will one-shot connect now.
# Do NOT rescan after this — that flaps iPhone hotspot association.
nmcli connection add type wifi ifname wlan0 con-name "${CONN_NAME}" \
  ssid "${SSID}" \
  wifi-sec.key-mgmt wpa-psk \
  wifi-sec.psk "${PASS}" \
  connection.autoconnect yes \
  connection.autoconnect-priority 200 \
  connection.autoconnect-retries 0 \
  connection.wait-device-timeout 15 \
  ipv4.method auto \
  ipv4.dhcp-timeout 30 \
  ipv6.method ignore \
  802-11-wireless.mac-address-randomization never \
  802-11-wireless.powersave 2 \
  802-11-wireless.cloned-mac-address permanent \
  || {
    write_status "error" 0 "Failed to create Wi-Fi connection profile"
    exit 1
  }
touch "${STATE_DIR}/.hotspot-profile-hardened" 2>/dev/null || true

# Give the user time to leave Dot-Setup and enable Personal Hotspot.
# Rare rescans only (every ~15s) — frequent rescans flap iPhone hotspot links.
write_status "switching" 0 "Waiting for Personal Hotspot «${SSID}» (up to 2 min)…"
visible=0
for i in $(seq 1 24); do
  if nmcli -t -f SSID device wifi list 2>/dev/null | grep -Fxq "${SSID}"; then
    visible=1
    break
  fi
  if (( i % 3 == 1 )); then
    nmcli device wifi rescan 2>/dev/null || true
  fi
  echo "Waiting for SSID «${SSID}» (${i}/24)…"
  sleep 5
done
if [[ "${visible}" -ne 1 ]]; then
  echo "SSID not listed yet — one-shot join anyway (iPhone hotspot can be hidden)."
fi

if [[ -x "${JOIN_BIN}" ]]; then
  if ! "${JOIN_BIN}" "${CONN_NAME}"; then
    write_status "error" 0 "Could not join «${SSID}». Keep modem on + Maximize Compatibility, unlock phone, then: sudo dot-wifi-join"
    mv -f "${REQUEST}" "${STATE_DIR}/wifi-request.failed.json" 2>/dev/null || true
    exit 1
  fi
else
  if ! nmcli -w 60 connection up "${CONN_NAME}" ifname wlan0; then
    write_status "error" 0 "Could not join «${SSID}». Check hotspot name/password."
    mv -f "${REQUEST}" "${STATE_DIR}/wifi-request.failed.json" 2>/dev/null || true
    exit 1
  fi
fi

rm -f "${REQUEST}" "${STATE_DIR}/wifi-request.failed.json"
IP="$(nmcli -g IP4.ADDRESS device show wlan0 2>/dev/null | head -n1 | cut -d/ -f1 || true)"
if [[ "${IP}" == "192.168.4.1" ]]; then
  IP=""
fi
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
