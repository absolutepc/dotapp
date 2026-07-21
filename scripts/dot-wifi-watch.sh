#!/usr/bin/env bash
# Long-running watch: every 15s ensure Dot is on the phone hotspot.
# Safer than a timer stacking oneshots. Skips while Setup AP is intentional.
set -euo pipefail

PROFILE_NAME="${DOT_WIFI_PROFILE_NAME:-dot-phone-hotspot}"
JOIN="/usr/local/sbin/dot-wifi-join"
USE="/usr/local/sbin/dot-wifi-use-hotspot"
LOG="/var/log/dot-wifi-watch.log"
STATE_DIR="/var/lib/dot"

mkdir -p "${STATE_DIR}"
touch "${LOG}" 2>/dev/null || true
log() { echo "$(date -Is) $*" >>"${LOG}" 2>/dev/null || true; }

log "watch started pid=$$"

while true; do
  if ! command -v nmcli >/dev/null 2>&1; then
    sleep 15
    continue
  fi

  # If no profile and no pending creds — nothing to do
  has_profile=0
  nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq "${PROFILE_NAME}" && has_profile=1
  if [[ "${has_profile}" -ne 1 && ! -f "${STATE_DIR}/wifi-pending.json" ]]; then
    sleep 20
    continue
  fi

  # Prefer client mode whenever a hotspot profile/pending exists:
  # lingering Setup AP blocks auto-join.
  if systemctl is-active --quiet hostapd 2>/dev/null || [[ -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf ]]; then
    # Only auto-exit Setup AP if user already saved hotspot credentials
    if [[ "${has_profile}" -eq 1 || -f "${STATE_DIR}/wifi-pending.json" ]]; then
      log "Setup AP active but hotspot creds exist — switching to client"
      if [[ -x "${USE}" ]]; then
        "${USE}" >>"${LOG}" 2>&1 || true
      fi
      sleep 15
      continue
    fi
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

  # Creating profile from pending if needed
  if [[ "${has_profile}" -ne 1 && -x "${USE}" ]]; then
    log "no profile — use-hotspot"
    "${USE}" >>"${LOG}" 2>&1 || true
    sleep 10
    continue
  fi

  log "not connected (state=${num:-?} conn=${conn:-none} ip=${ip:-none}) — join"
  if [[ -x "${JOIN}" ]]; then
    "${JOIN}" "${PROFILE_NAME}" >>"${LOG}" 2>&1 || true
  fi
  sleep 15
done
