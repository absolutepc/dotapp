#!/usr/bin/env bash
# Apply pending Wi-Fi client config (iPhone Personal Hotspot).
# Invoked by systemd when /var/lib/bmw-logo/wifi-request.json appears.
# Or manually: sudo bash scripts/wifi-apply-client.sh
set -euo pipefail

STATE_DIR="/var/lib/bmw-logo"
REQUEST="${STATE_DIR}/wifi-request.json"
STATUS="${STATE_DIR}/wifi-status.json"
MODE="${STATE_DIR}/wifi-mode.json"
CONN_NAME="bmw-phone-hotspot"

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
payload = {
    "ok": ok == "1",
    "mode": mode,
    "message": msg,
    "ip": ip or None,
    "updated_at": datetime.datetime.utcnow().isoformat() + "Z",
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

# Tear down AP
systemctl stop hostapd dnsmasq 2>/dev/null || true
systemctl disable hostapd 2>/dev/null || true

# Return wlan0 to NetworkManager
rm -f /etc/NetworkManager/conf.d/99-bmw-logo-unmanaged.conf
systemctl reload NetworkManager 2>/dev/null || true
nmcli device set wlan0 managed yes 2>/dev/null || true
nmcli radio wifi on 2>/dev/null || true
ip addr flush dev wlan0 2>/dev/null || true
ip link set wlan0 up || true

# Replace previous saved hotspot profile
nmcli connection delete "${CONN_NAME}" 2>/dev/null || true

# Create + activate client connection (secrets stored by NM)
if ! nmcli connection add type wifi ifname wlan0 con-name "${CONN_NAME}" \
    ssid "${SSID}" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "${PASS}" \
    connection.autoconnect yes \
    ipv4.method auto ipv6.method ignore; then
  write_status "error" 0 "Failed to create Wi-Fi connection profile"
  exit 1
fi

if ! nmcli -w 45 connection up "${CONN_NAME}" ifname wlan0; then
  write_status "error" 0 "Could not join «${SSID}». Check hotspot name/password, then reopen setup AP."
  # Leave request file for retry inspection; rename it
  mv -f "${REQUEST}" "${STATE_DIR}/wifi-request.failed.json" 2>/dev/null || true
  exit 1
fi

# Discover IPv4
IP="$(nmcli -g IP4.ADDRESS device show wlan0 2>/dev/null | head -n1 | cut -d/ -f1 || true)"
if [[ -z "${IP}" ]]; then
  IP="$(ip -4 -o addr show wlan0 | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)"
fi

rm -f "${REQUEST}"
write_status "client" 1 "Connected to «${SSID}»" "${IP}"

# Persist SSID only (never password) for UI
python3 - "${STATE_DIR}/wifi-client.json" "${SSID}" "${IP}" <<'PY'
import json, sys, datetime
path, ssid, ip = sys.argv[1:4]
open(path, "w").write(json.dumps({
    "ssid": ssid,
    "ip": ip or None,
    "updated_at": datetime.datetime.utcnow().isoformat() + "Z",
}) + "\n")
PY

echo "Connected to ${SSID} ip=${IP:-unknown}"
