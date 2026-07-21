#!/usr/bin/env bash
# Long-running watch — ONLY when wifi-role=client.
# Initial / setup role: do nothing (Dot-Setup must stay visible).
set -euo pipefail

PROFILE_NAME="${DOT_WIFI_PROFILE_NAME:-dot-phone-hotspot}"
JOIN="/usr/local/sbin/dot-wifi-join"
USE="/usr/local/sbin/dot-wifi-use-hotspot"
LOG="/var/log/dot-wifi-watch.log"
STATE_DIR="/var/lib/dot"
ROLE_FILE="${STATE_DIR}/wifi-role"
HOLD="${STATE_DIR}/setup-ap-hold"

mkdir -p "${STATE_DIR}"
touch "${LOG}" 2>/dev/null || true
log() { echo "$(date -Is) $*" >>"${LOG}" 2>/dev/null || true; }

wifi_role() {
  if [[ -f "${ROLE_FILE}" ]]; then
    tr -d '[:space:]' <"${ROLE_FILE}"
  else
    echo "setup"
  fi
}

log "watch started pid=$$"

while true; do
  role="$(wifi_role)"
  if [[ "${role}" != "client" || -f "${HOLD}" ]]; then
    sleep 20
    continue
  fi

  if ! command -v nmcli >/dev/null 2>&1; then
    sleep 15
    continue
  fi

  if ! nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "${PROFILE_NAME}"; then
    sleep 20
    continue
  fi

  # Accidental Setup AP while role=client — reclaim
  if systemctl is-active --quiet hostapd 2>/dev/null || [[ -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf ]]; then
    log "Setup AP while role=client — use-hotspot"
    [[ -x "${USE}" ]] && "${USE}" >>"${LOG}" 2>&1 || true
    sleep 15
    continue
  fi

  ip="$(nmcli -g IP4.ADDRESS device show wlan0 2>/dev/null | head -n1 | cut -d/ -f1 || true)"
  [[ "${ip}" == "192.168.4.1" ]] && ip=""
  conn="$(nmcli -g GENERAL.CONNECTION device show wlan0 2>/dev/null || true)"
  num="$(nmcli -g GENERAL.STATE device show wlan0 2>/dev/null | awk '{print $1; exit}' || true)"

  if [[ -n "${ip}" && "${conn}" == "${PROFILE_NAME}" && "${num}" == "100" ]]; then
    gw="$(ip route show default dev wlan0 2>/dev/null | awk '{print $3; exit}' || true)"
    [[ -n "${gw}" ]] && ping -c 1 -W 1 "${gw}" >/dev/null 2>&1 || true
    command -v iw >/dev/null 2>&1 && iw dev wlan0 set power_save off 2>/dev/null || true
    sleep 15
    continue
  fi

  case "${num}" in
    40|50|60|70|80|90) sleep 5; continue ;;
  esac

  log "not connected (state=${num:-?} conn=${conn:-none}) — join"
  [[ -x "${JOIN}" ]] && "${JOIN}" "${PROFILE_NAME}" >>"${LOG}" 2>&1 || true
  sleep 15
done
