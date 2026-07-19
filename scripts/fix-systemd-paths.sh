#!/usr/bin/env bash
# Rewrite bmw-logo systemd units to this checkout + user + venv/.venv.
# Run on Pi:
#   sudo bash scripts/fix-systemd-paths.sh [username] [desktop|kiosk|auto]
# desktop = with LXDE/lightdm (X11 fullscreen)
# kiosk   = no desktop (kmsdrm on tty1)
# auto    = pick from system default target (default)
set -euo pipefail

PI_USER="${1:-${SUDO_USER:-mercy119}}"
MODE="${2:-auto}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -x "${ROOT}/venv/bin/python" ]]; then
  VENV_BIN="${ROOT}/venv/bin"
elif [[ -x "${ROOT}/.venv/bin/python" ]]; then
  VENV_BIN="${ROOT}/.venv/bin"
else
  echo "ERROR: no venv in ${ROOT}" >&2
  exit 1
fi

if [[ ! -x "${VENV_BIN}/uvicorn" ]]; then
  echo "ERROR: uvicorn missing in ${VENV_BIN}" >&2
  exit 1
fi

if [[ "${MODE}" == "auto" ]]; then
  if systemctl get-default 2>/dev/null | grep -q graphical; then
    MODE=desktop
  else
    MODE=kiosk
  fi
fi

if [[ "${MODE}" == "desktop" ]]; then
  DISPLAY_SRC="${ROOT}/firmware/systemd/bmw-logo-display.service"
else
  DISPLAY_SRC="${ROOT}/firmware/systemd/bmw-logo-display-kiosk.service"
fi
API_SRC="${ROOT}/firmware/systemd/bmw-logo-api.service"
[[ -f "${DISPLAY_SRC}" && -f "${API_SRC}" ]] || {
  echo "ERROR: systemd templates missing under ${ROOT}/firmware/systemd" >&2
  exit 1
}

rewrite_unit() {
  local src="$1" dest="$2" exec_bin="$3" exec_args="$4"
  sed \
    -e "s|^User=.*|User=${PI_USER}|" \
    -e "s|/opt/bmw-logo|${ROOT}|g" \
    -e "s|/home/pi/|/home/${PI_USER}/|g" \
    "${src}" >"${dest}"
  if grep -q '^ExecStart=' "${dest}"; then
    sed -i "s|^ExecStart=.*|ExecStart=${exec_bin} ${exec_args}|" "${dest}"
  fi
  sed -i \
    -e "s|^WorkingDirectory=.*|WorkingDirectory=${ROOT}|" \
    -e "s|^Environment=PYTHONPATH=.*|Environment=PYTHONPATH=${ROOT}|" \
    "${dest}"
}

rewrite_unit "${DISPLAY_SRC}" /etc/systemd/system/bmw-logo-display.service \
  "${VENV_BIN}/python" "-m firmware.display.hdmi_renderer"

rewrite_unit "${API_SRC}" /etc/systemd/system/bmw-logo-api.service \
  "${VENV_BIN}/uvicorn" "firmware.main:app --host 0.0.0.0 --port 8080"

usermod -aG video,render "${PI_USER}" 2>/dev/null || usermod -aG video "${PI_USER}" 2>/dev/null || true

systemctl daemon-reload
systemctl enable bmw-logo-api bmw-logo-display
systemctl restart bmw-logo-api
# Display may need the desktop session; restart after a short wait
systemctl restart bmw-logo-display || true

echo "---"
echo "Mode: ${MODE}"
echo "User: ${PI_USER}"
echo "Root: ${ROOT}"
echo "Venv: ${VENV_BIN}"
echo "---"
systemctl cat bmw-logo-api bmw-logo-display | grep -E '^(# |User=|WorkingDirectory=|Environment=|ExecStart=)'
echo "---"
sleep 3
systemctl is-active bmw-logo-api bmw-logo-display || true
journalctl -u bmw-logo-display -n 25 --no-pager || true
