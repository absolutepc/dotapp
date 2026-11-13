#!/usr/bin/env bash
# Enter one-time Wi-Fi setup AP mode (phone joins this network to configure hotspot).
# Run: sudo bash scripts/enter-setup-ap.sh [setup_password]
# Tip: does NOT run apt-get update unless packages are missing (fast on Pi Zero).
set -euo pipefail

SETUP_PASS="${1:-dotsetup1}"
SSID_SUFFIX="$(hostname 2>/dev/null | tr -cd 'A-Za-z0-9' | tail -c 4)"
SSID="Dot-Setup-${SSID_SUFFIX:-Pi}"
AP_IP="192.168.4.1"
STATE_DIR="/var/lib/dot"
mkdir -p "${STATE_DIR}"

echo "Entering setup AP mode: ${SSID}"

# Initial / re-provision mode: Setup AP only — do not auto-join modem.
echo "setup" >"${STATE_DIR}/wifi-role"
touch "${STATE_DIR}/setup-ap-hold"

# Pause AND disable client watchers so they cannot tear down Dot-Setup or rejoin hotspot.
systemctl disable --now dot-wifi-watch.service 2>/dev/null || true
systemctl disable --now dot-wifi-keepalive.timer 2>/dev/null || true
systemctl stop dot-wifi-keepalive.service 2>/dev/null || true
pkill -f '/usr/local/sbin/dot-wifi-watch' 2>/dev/null || true
pkill -f '/usr/local/sbin/dot-wifi-use-hotspot' 2>/dev/null || true
pkill -f '/usr/local/sbin/dot-wifi-join' 2>/dev/null || true
pkill -f '/usr/local/sbin/dot-wifi-keepalive' 2>/dev/null || true

# Drop the hotspot NM profile so it cannot autoconnect while we are in Dot-Setup.
# Credentials stay in wifi-pending.json for the next wizard run (use-hotspot recreates the profile).
if command -v nmcli >/dev/null 2>&1; then
  if nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "dot-phone-hotspot"; then
    nmcli connection modify dot-phone-hotspot connection.autoconnect no 2>/dev/null || true
    nmcli connection down dot-phone-hotspot 2>/dev/null || true
    nmcli connection delete dot-phone-hotspot 2>/dev/null || true
  fi
  # Also disable autoconnect on any other Wi-Fi profiles that might steal wlan0.
  nmcli -t -f NAME,TYPE connection show 2>/dev/null | while IFS=: read -r name type; do
    [[ "${type}" == "802-11-wireless" || "${type}" == "wifi" ]] || continue
    nmcli connection modify "${name}" connection.autoconnect no 2>/dev/null || true
    nmcli connection down "${name}" 2>/dev/null || true
  done
fi

# Cancel any queued join request.
rm -f "${STATE_DIR}/wifi-request.json" "${STATE_DIR}/wifi-request.failed.json" \
  "${STATE_DIR}/wifi-client.json" "${STATE_DIR}/.hotspot-profile-hardened"

need_pkgs=()
command -v hostapd >/dev/null || need_pkgs+=(hostapd)
command -v dnsmasq >/dev/null || need_pkgs+=(dnsmasq)
command -v nmcli >/dev/null || need_pkgs+=(network-manager)
if ((${#need_pkgs[@]})); then
  echo "Installing packages: ${need_pkgs[*]} (needs internet)…"
  apt-get update -qq
  apt-get install -y -qq "${need_pkgs[@]}"
else
  echo "Packages already installed — skipping apt."
fi

# Stop any client connection on wlan0
systemctl stop hostapd dnsmasq 2>/dev/null || true
nmcli radio wifi on 2>/dev/null || true
nmcli device disconnect wlan0 2>/dev/null || true

# Let hostapd own wlan0
mkdir -p /etc/NetworkManager/conf.d
cat >/etc/NetworkManager/conf.d/99-dot-unmanaged.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
systemctl reload NetworkManager 2>/dev/null || true
nmcli device set wlan0 managed no 2>/dev/null || true

cat >/etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${SETUP_PASS}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
EOF

if [[ -f /etc/default/hostapd ]]; then
  if grep -q '^DAEMON_CONF=' /etc/default/hostapd || grep -q '^#DAEMON_CONF=' /etc/default/hostapd; then
    sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
  else
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >>/etc/default/hostapd
  fi
else
  echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >/etc/default/hostapd
fi

mkdir -p /etc/dnsmasq.d
# Dedicated config; avoid clashing with systemd-resolved / NM on port 53 (lo).
cat >/etc/dnsmasq.d/dot.conf <<EOF
interface=wlan0
bind-interfaces
except-interface=lo
no-resolv
no-hosts
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
address=/dot.local/${AP_IP}
address=/setup.dot/${AP_IP}
EOF

# Disable stock dnsmasq defaults that bind *:53 and break on Bookworm.
if [[ -f /etc/default/dnsmasq ]]; then
  sed -i 's/^#\?ENABLED=.*/ENABLED=1/' /etc/default/dnsmasq 2>/dev/null || true
  if ! grep -q 'IGNORE_RESOLVCONF' /etc/default/dnsmasq 2>/dev/null; then
    echo 'IGNORE_RESOLVCONF=yes' >>/etc/default/dnsmasq
  fi
fi
# Prefer our drop-in only: comment broad listen in main conf if present
if [[ -f /etc/dnsmasq.conf ]]; then
  sed -i 's/^bind-interfaces/# bind-interfaces (managed by /etc/dnsmasq.d\/dot.conf)/' /etc/dnsmasq.conf 2>/dev/null || true
fi

ip link set wlan0 up || true
ip addr flush dev wlan0 2>/dev/null || true
ip addr replace ${AP_IP}/24 dev wlan0 || true

systemctl unmask hostapd 2>/dev/null || true
systemctl enable hostapd >/dev/null 2>&1 || true
# Do not permanently enable system dnsmasq — it fights resolved when not in setup.
systemctl disable dnsmasq >/dev/null 2>&1 || true

echo "Starting hostapd + dnsmasq…"
# Free port 53 on wlan0 path; resolved can keep lo.
systemctl stop dnsmasq 2>/dev/null || true
# Kill stray dnsmasq (NM plugin) that holds interfaces
pkill -x dnsmasq 2>/dev/null || true
sleep 0.5

# hostapd first (AP), then dnsmasq (DHCP). Don't abort setup if DHCP helper flakes —
# phone can still use a static/link-local path less often, but AP SSID still appears.
set +e
systemctl restart hostapd
hap=$?
systemctl restart dnsmasq
dns=$?
set -e

sleep 1
systemctl is-active hostapd || true
systemctl is-active dnsmasq || true
ip -4 addr show wlan0 | sed -n '1,6p' || true

if [[ "${hap}" -ne 0 ]]; then
  echo "ERROR: hostapd failed to start — Setup Wi-Fi will not appear." >&2
  journalctl -u hostapd -n 20 --no-pager >&2 || true
  exit 1
fi
if [[ "${dns}" -ne 0 ]]; then
  echo "WARN: dnsmasq failed (DHCP). Trying foreground fallback…" >&2
  journalctl -u dnsmasq -n 15 --no-pager >&2 || true
  # Fallback: run dnsmasq only on wlan0 without full unit
  pkill -x dnsmasq 2>/dev/null || true
  dnsmasq --conf-file=/dev/null --interface=wlan0 --bind-interfaces \
    --except-interface=lo --dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h \
    --address=/dot.local/${AP_IP} --pid-file=/run/dot-dnsmasq.pid \
    && echo "dnsmasq fallback started." || echo "WARN: DHCP still down — join Dot-Setup may need manual IP." >&2
fi

# Clear stale client / error status so the app sees setup_ap (not leftover "error").
rm -f "${STATE_DIR}/wifi-client.json" "${STATE_DIR}/wifi-request.json" \
  "${STATE_DIR}/wifi-request.failed.json" "${STATE_DIR}/.hotspot-profile-hardened"
python3 - "${STATE_DIR}/wifi-mode.json" "${STATE_DIR}/wifi-status.json" "${SSID}" "${AP_IP}" <<'PY'
import json, sys, datetime
mode_path, status_path, ssid, ip = sys.argv[1:5]
now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
mode = {"mode": "setup_ap", "ssid": ssid, "ip": ip, "portal": f"http://{ip}/setup/", "message": f"Setup AP {ssid}"}
status = {"ok": True, "mode": "setup_ap", "message": f"Setup AP ready: {ssid}", "ip": ip, "updated_at": now}
open(mode_path, "w").write(json.dumps(mode) + "\n")
open(status_path, "w").write(json.dumps(status) + "\n")
PY

# Show SSID / password / QR on the round HDMI (best-effort).
SETUP_MEDIA_ID="setup-info"
FRAMES_ROOT="${STATE_DIR}/frames"
STATE_RUN="/var/run/dot"
[[ -d "${STATE_RUN}" ]] || STATE_RUN="${STATE_DIR}/state"
mkdir -p "${FRAMES_ROOT}" "${STATE_RUN}"

# When installed as /usr/local/sbin/dot-enter-setup-ap, dirname/.. is /usr/local — not the repo.
# Prefer the packaged copy under /usr/local/share/dot, then a repo checkout if present.
RENDER_SETUP=""
for candidate in \
  "/usr/local/share/dot/render-setup-screen.py" \
  "/home/mercy119/dotapp/scripts/render-setup-screen.py" \
  "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/scripts/render-setup-screen.py"
do
  if [[ -n "${candidate}" && -f "${candidate}" ]]; then
    RENDER_SETUP="${candidate}"
    break
  fi
done

PY=""
if command -v python3 >/dev/null; then
  PY="python3"
fi
if [[ -n "${PY}" && -n "${RENDER_SETUP}" ]]; then
  "${PY}" "${RENDER_SETUP}" \
    --ssid "${SSID}" \
    --password "${SETUP_PASS}" \
    --ip "${AP_IP}" \
    --frames-dir "${FRAMES_ROOT}" \
    --media-id "${SETUP_MEDIA_ID}" \
    && cat >"${STATE_RUN}/current_media.json" <<EOF
{"media_id": "${SETUP_MEDIA_ID}", "fps": 1.0}
EOF
  mkdir -p "${STATE_DIR}/previews"
  if [[ -f "${FRAMES_ROOT}/${SETUP_MEDIA_ID}/0000.jpg" ]]; then
    cp -f "${FRAMES_ROOT}/${SETUP_MEDIA_ID}/0000.jpg" "${STATE_DIR}/previews/${SETUP_MEDIA_ID}.jpg" || true
  fi
elif [[ -n "${PY}" ]]; then
  echo "WARN: render-setup-screen.py not found — HDMI QR skipped (Setup AP still works)." >&2
fi

echo ""
echo "Setup AP ready."
echo "  1. On iPhone: join Wi-Fi  ${SSID}"
echo "  2. Password:              ${SETUP_PASS}"
echo "  3. Open Dot app → Wi‑Fi setup  (or http://${AP_IP}/setup/)"
echo "  4. Enter your iPhone Personal Hotspot name + password"
echo "  Auto-join is paused until you finish setup (or run: sudo dot-wifi-use-hotspot)."
echo "  HDMI shows the same SSID / password / QR when display is running."
echo ""
