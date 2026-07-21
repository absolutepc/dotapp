#!/usr/bin/env bash
# Soft keepalive oneshot (timer): ping when up; join when down.
# Respects setup-ap-hold so intentional Dot-Setup is not torn down.
set -euo pipefail

PROFILE_NAME="${DOT_WIFI_PROFILE_NAME:-dot-phone-hotspot}"
JOIN="/usr/local/sbin/dot-wifi-join"
USE="/usr/local/sbin/dot-wifi-use-hotspot"
LOG="/var/log/dot-wifi-keepalive.log"
STATE_DIR="/var/lib/dot"
HOLD="${STATE_DIR}/setup-ap-hold"

log() { echo "$(date -Is) $*" >>"${LOG}" 2>/dev/null || true; }

if [[ -f "${HOLD}" ]]; then
  exit 0
fi

if ! command -v nmcli >/dev/null 2>&1; then
  exit 0
fi

has_profile=0
nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "${PROFILE_NAME}" && has_profile=1
if [[ "${has_profile}" -ne 1 ]]; then
  if [[ -f "${STATE_DIR}/wifi-pending.json" && -x "${USE}" ]]; then
    log "no profile — use-hotspot from pending"
    "${USE}" >>"${LOG}" 2>&1 || true
  fi
  exit 0
fi

# Setup AP without hold + profile → reclaim for client
if systemctl is-active --quiet hostapd 2>/dev/null || [[ -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf ]]; then
  log "hostapd/unmanaged with profile (no hold) — use-hotspot"
  if [[ -x "${USE}" ]]; then
    "${USE}" >>"${LOG}" 2>&1 || true
  fi
  exit 0
fi

ip="$(nmcli -g IP4.ADDRESS device show wlan0 2>/dev/null | head -n1 | cut -d/ -f1 || true)"
[[ "${ip}" == "192.168.4.1" ]] && ip=""
conn="$(nmcli -g GENERAL.CONNECTION device show wlan0 2>/dev/null || true)"
num="$(nmcli -g GENERAL.STATE device show wlan0 2>/dev/null | awk '{print $1; exit}' || true)"

if [[ -n "${ip}" && "${conn}" == "${PROFILE_NAME}" && "${num}" == "100" ]]; then
  gw="$(ip route show default dev wlan0 2>/dev/null | awk '{print $3; exit}' || true)"
  [[ -n "${gw}" ]] && ping -c 1 -W 1 "${gw}" >/dev/null 2>&1 || true
  command -v iw >/dev/null 2>&1 && iw dev wlan0 set power_save off 2>/dev/null || true
  exit 0
fi

case "${num}" in
  40|50|60|70|80|90) exit 0 ;;
esac

log "down state=${num:-?} conn=${conn:-none} ip=${ip:-none} — join"
if [[ -x "${JOIN}" ]]; then
  "${JOIN}" "${PROFILE_NAME}" >>"${LOG}" 2>&1 || true
fi
exit 0
