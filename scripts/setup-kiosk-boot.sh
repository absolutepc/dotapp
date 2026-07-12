#!/usr/bin/env bash
# Boot straight to BMW logo: no desktop, minimal splash.
# Run on Pi: sudo bash scripts/setup-kiosk-boot.sh [username]
set -euo pipefail

PI_USER="${1:-${SUDO_USER:-pi}}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${BMW_LOGO_INSTALL:-/opt/bmw-logo}"
if [[ -d "${REPO_ROOT}/firmware" && ! -d "${INSTALL_DIR}/firmware" ]]; then
  INSTALL_DIR="${REPO_ROOT}"
fi

echo "Kiosk boot setup for user: ${PI_USER}"
echo "Install dir: ${INSTALL_DIR}"

# --- Quiet boot: config.txt ---
CONFIG="/boot/firmware/config.txt"
[[ -f "${CONFIG}" ]] || CONFIG="/boot/config.txt"
if [[ -f "${CONFIG}" ]]; then
  grep -q '^disable_splash=1' "${CONFIG}" || echo "disable_splash=1" >>"${CONFIG}"
  echo "Updated ${CONFIG} (disable_splash=1)"
fi

# --- Quiet boot: cmdline.txt ---
CMDLINE="/boot/firmware/cmdline.txt"
[[ -f "${CMDLINE}" ]] || CMDLINE="/boot/cmdline.txt"
if [[ -f "${CMDLINE}" ]]; then
  for token in quiet splash loglevel=3 logo.nologo vt.global_cursor_default=0; do
    grep -q "${token}" "${CMDLINE}" || sed -i "s/$/ ${token}/" "${CMDLINE}"
  done
  echo "Updated ${CMDLINE} (quiet boot)"
fi

# --- No desktop ---
systemctl set-default multi-user.target
systemctl disable lightdm 2>/dev/null || true
systemctl disable gdm 2>/dev/null || true
systemctl disable wayfire 2>/dev/null || true
systemctl disable labwc 2>/dev/null || true
systemctl disable plymouth-start 2>/dev/null || true
echo "Default target: multi-user (no desktop)"

# --- Kiosk display service ---
sed "s|User=pi|User=${PI_USER}|g; s|/opt/bmw-logo|${INSTALL_DIR}|g" \
  "${INSTALL_DIR}/firmware/systemd/bmw-logo-display-kiosk.service" \
  >/etc/systemd/system/bmw-logo-display.service

# Fix venv path (venv vs .venv)
if [[ -x "${INSTALL_DIR}/venv/bin/python" ]]; then
  sed -i "s|/.venv/bin/python|/venv/bin/python|g" /etc/systemd/system/bmw-logo-display.service
fi

# API service user/path
sed "s|User=pi|User=${PI_USER}|g; s|/opt/bmw-logo|${INSTALL_DIR}|g" \
  "${INSTALL_DIR}/firmware/systemd/bmw-logo-api.service" \
  >/etc/systemd/system/bmw-logo-api.service
if [[ -x "${INSTALL_DIR}/venv/bin/uvicorn" ]]; then
  sed -i "s|/.venv/bin/uvicorn|/venv/bin/uvicorn|g" /etc/systemd/system/bmw-logo-api.service
fi

systemctl daemon-reload
systemctl enable bmw-logo-api bmw-logo-display

echo ""
echo "Kiosk boot configured."
echo "  - No desktop on next boot"
echo "  - Minimal Raspberry Pi splash"
echo "  - Logo renderer starts on tty1"
echo ""
echo "Reboot to apply: sudo reboot"
echo ""
echo "To restore desktop:"
echo "  sudo systemctl set-default graphical.target"
echo "  sudo systemctl enable lightdm"
echo "  sudo cp ${INSTALL_DIR}/firmware/systemd/bmw-logo-display.service /etc/systemd/system/"
echo "  sudo systemctl daemon-reload && sudo reboot"
