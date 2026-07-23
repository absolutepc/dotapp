#!/usr/bin/env bash
# Rewrite Dot systemd units (dot-api / dot-display) to this checkout + user + venv.
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
  DISPLAY_SRC="${ROOT}/firmware/systemd/dot-display.service"
else
  DISPLAY_SRC="${ROOT}/firmware/systemd/dot-display-kiosk.service"
fi
API_SRC="${ROOT}/firmware/systemd/dot-api.service"
[[ -f "${DISPLAY_SRC}" && -f "${API_SRC}" ]] || {
  echo "ERROR: systemd templates missing under ${ROOT}/firmware/systemd" >&2
  exit 1
}

# Drop legacy unit names from older installs
for old in bmw-logo-api bmw-logo-display bmw-api bmw-display; do
  systemctl disable --now "${old}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${old}.service"
done

rewrite_unit() {
  local src="$1" dest="$2" exec_bin="$3" exec_args="$4" force_user="${5:-}"
  sed \
    -e "s|/opt/dot|${ROOT}|g" \
    -e "s|/home/pi/|/home/${PI_USER}/|g" \
    "${src}" >"${dest}"
  if [[ -n "${force_user}" ]]; then
    if grep -q '^User=' "${dest}"; then
      sed -i "s|^User=.*|User=${force_user}|" "${dest}"
    else
      sed -i "/^\[Service\]/a User=${force_user}" "${dest}"
    fi
  else
    sed -i "s|^User=.*|User=${PI_USER}|" "${dest}"
  fi
  if grep -q '^ExecStart=' "${dest}"; then
    sed -i "s|^ExecStart=.*|ExecStart=${exec_bin} ${exec_args}|" "${dest}"
  fi
  sed -i \
    -e "s|^WorkingDirectory=.*|WorkingDirectory=${ROOT}|" \
    -e "s|^Environment=PYTHONPATH=.*|Environment=PYTHONPATH=${ROOT}|" \
    "${dest}"
}

# Kiosk display needs root for DRM master on tty1; API stays as the login user.
if [[ "${MODE}" == "kiosk" ]]; then
  rewrite_unit "${DISPLAY_SRC}" /etc/systemd/system/dot-display.service \
    "${VENV_BIN}/python" "-m firmware.display.hdmi_renderer" "root"
else
  rewrite_unit "${DISPLAY_SRC}" /etc/systemd/system/dot-display.service \
    "${VENV_BIN}/python" "-m firmware.display.hdmi_renderer"
fi

rewrite_unit "${API_SRC}" /etc/systemd/system/dot-api.service \
  "${VENV_BIN}/uvicorn" "firmware.main:app --host 0.0.0.0 --port 8080"

usermod -aG video,render "${PI_USER}" 2>/dev/null || usermod -aG video "${PI_USER}" 2>/dev/null || true

systemctl daemon-reload
systemctl enable dot-api dot-display
systemctl restart dot-api
# Display may need the desktop session; restart after a short wait
systemctl restart dot-display || true

# Global CLI: `show anim3` from any directory
install -m 755 "${ROOT}/scripts/show" /usr/local/bin/show

echo "---"
echo "Mode: ${MODE}"
echo "User: ${PI_USER}"
echo "Root: ${ROOT}"
echo "Venv: ${VENV_BIN}"
echo "CLI:  show anim3 | show list | show status"
echo "---"
systemctl cat dot-api dot-display | grep -E '^(# |User=|WorkingDirectory=|Environment=|ExecStart=)'
echo "---"
sleep 3
systemctl is-active dot-api dot-display || true
journalctl -u dot-display -n 25 --no-pager || true
