#!/usr/bin/env bash
# Soft keepalive: keep Dot on the phone hotspot without flapping.
# - If already online → only ping gateway (iPhone drops idle clients)
# - If associating → do nothing
# - If fully down → one anti-flap join (safe to rescan while down)
# Never runs during Setup AP.
#
# Note: NetworkManager autoconnect-retries: 0 = forever, -1 = global default (~4).
set -euo pipefail

PROFILE_NAME="${DOT_WIFI_PROFILE_NAME:-dot-phone-hotspot}"
JOIN="/usr/local/sbin/dot-wifi-join"
LOG="/var/log/dot-wifi-keepalive.log"

log() { echo "$(date -Is) $*" >>"${LOG}" 2>/dev/null || true; }

if ! command -v nmcli >/dev/null 2>&1; then
  exit 0
fi
if ! nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "${PROFILE_NAME}"; then
  exit 0
fi

# Don't fight Setup AP
if systemctl is-active --quiet hostapd 2>/dev/null; then
  exit 0
fi
if [[ -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf ]]; then
  exit 0
fi

current_ip() {
  local ip=""
  ip="$(nmcli -g IP4.ADDRESS device show wlan0 2>/dev/null | head -n1 | cut -d/ -f1 || true)"
  if [[ -z "${ip}" ]]; then
    ip="$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1 || true)"
  fi
  [[ "${ip}" == "192.168.4.1" ]] && ip=""
  printf '%s' "${ip}"
}

conn="$(nmcli -g GENERAL.CONNECTION device show wlan0 2>/dev/null || true)"
state="$(nmcli -g GENERAL.STATE device show wlan0 2>/dev/null || true)"
ip="$(current_ip)"

# Healthy: ping only — never connection up / rescan
if [[ -n "${ip}" && "${conn}" == "${PROFILE_NAME}" && ( "${state}" == 100* || "${state}" == *"connected"* ) ]]; then
  gw="$(ip route show default dev wlan0 2>/dev/null | awk '{print $3; exit}' || true)"
  [[ -n "${gw}" ]] && ping -c 1 -W 1 "${gw}" >/dev/null 2>&1 || true
  command -v iw >/dev/null 2>&1 && iw dev wlan0 set power_save off 2>/dev/null || true
  exit 0
fi

# In progress — never bounce
if [[ "${conn}" == "${PROFILE_NAME}" ]]; then
  exit 0
fi
case "${state}" in
  10*|20*|30*|40*|50*|60*|70*|80*|90*|*"connecting"*|*"configuring"* ) exit 0 ;;
esac

# Fully down: ensure radio + one join. Rescan is OK while disconnected.
log "link down conn=${conn:-none} state=${state:-?} ip=${ip:-none} — join once"
nmcli radio wifi on 2>/dev/null || true
nmcli device set wlan0 managed yes 2>/dev/null || true
command -v iw >/dev/null 2>&1 && iw dev wlan0 set power_save off 2>/dev/null || true
# Ensure NM will keep trying (0 = forever in NetworkManager)
nmcli connection modify "${PROFILE_NAME}" \
  connection.autoconnect yes \
  connection.autoconnect-retries 0 \
  2>/dev/null || true
nmcli device wifi rescan 2>/dev/null || true
sleep 2
if [[ -x "${JOIN}" ]]; then
  "${JOIN}" "${PROFILE_NAME}" >>"${LOG}" 2>&1 || true
else
  nmcli -w 30 connection up "${PROFILE_NAME}" ifname wlan0 >>"${LOG}" 2>&1 || true
fi
exit 0
