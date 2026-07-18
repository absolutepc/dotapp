#!/usr/bin/env bash
# Boot straight to BMW logo: no desktop, no splash screens.
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

# --- Quiet boot: config.txt (hide rainbow + early Pi logos) ---
CONFIG="/boot/firmware/config.txt"
[[ -f "${CONFIG}" ]] || CONFIG="/boot/config.txt"
if [[ -f "${CONFIG}" ]]; then
  grep -q '^disable_splash=1' "${CONFIG}" || echo "disable_splash=1" >>"${CONFIG}"
  echo "Updated ${CONFIG} (disable_splash=1)"
fi

# --- Quiet boot: cmdline.txt ---
# IMPORTANT: do NOT add "splash" — that enables Plymouth ("Welcome to Raspberry Pi").
CMDLINE="/boot/firmware/cmdline.txt"
[[ -f "${CMDLINE}" ]] || CMDLINE="/boot/cmdline.txt"
if [[ -f "${CMDLINE}" ]]; then
  # Remove splash / plymouth flags that show the graphical boot screen
  sed -i \
    -e 's/\bsplash\b//g' \
    -e 's/\bnosplash\b//g' \
    -e 's/\bplymouth\.ignore-serial-consoles\b//g' \
    -e 's/  */ /g' \
    -e 's/[[:space:]]*$//' \
    "${CMDLINE}"

  for token in quiet loglevel=0 logo.nologo vt.global_cursor_default=0 consoleblank=0; do
    grep -qE "(^|[[:space:]])${token}([[:space:]]|$)" "${CMDLINE}" || sed -i "s/$/ ${token}/" "${CMDLINE}"
  done

  # Prefer tty3 so kernel spam is not on the visible console
  if grep -q 'console=tty1' "${CMDLINE}"; then
    sed -i 's/console=tty1/console=tty3/' "${CMDLINE}"
  fi

  echo "Updated ${CMDLINE}:"
  cat "${CMDLINE}"
fi

# --- No desktop / no Plymouth ---
systemctl set-default multi-user.target
systemctl disable lightdm 2>/dev/null || true
systemctl disable gdm 2>/dev/null || true
systemctl disable wayfire 2>/dev/null || true
systemctl disable labwc 2>/dev/null || true
for svc in plymouth-start plymouth-read-write plymouth-quit plymouth-quit-wait plymouth-reboot plymouth-halt plymouth-kexec; do
  systemctl disable "${svc}" 2>/dev/null || true
  systemctl mask "${svc}" 2>/dev/null || true
done
echo "Default target: multi-user (no desktop, Plymouth masked)"

# Also via raspi-config noninteractive if available (1 = Splash Screen No)
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_boot_splash 1 2>/dev/null || true
fi

# Rebuild initramfs / black out leftover Plymouth art
if [[ -f "${REPO_ROOT}/scripts/disable-splash.sh" ]]; then
  # Full splash kill: cmdline + mask Plymouth + black theme + initramfs
  bash "${REPO_ROOT}/scripts/disable-splash.sh" || true
fi

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

# Ensure user can open DRM/KMS devices without desktop
usermod -aG video,render "${PI_USER}" 2>/dev/null || usermod -aG video "${PI_USER}" 2>/dev/null || true

systemctl daemon-reload
systemctl enable bmw-logo-api bmw-logo-display
systemctl restart bmw-logo-api bmw-logo-display 2>/dev/null || true

echo ""
echo "Kiosk boot configured."
echo "  - No desktop / no Plymouth / no cloud-init spam"
echo "  - Logo renderer on tty1 (kmsdrm)"
echo ""
echo "Check now (before reboot):"
echo "  systemctl --no-pager --failed"
echo "  journalctl -u bmw-logo-display -n 30 --no-pager"
echo ""
echo "Reboot to apply quiet boot: sudo reboot"
echo ""
echo "To restore desktop:"
echo "  sudo systemctl set-default graphical.target"
echo "  sudo systemctl enable lightdm"
echo "  sudo systemctl unmask plymouth-start"
echo "  sudo rm -f /etc/cloud/cloud-init.disabled"
echo "  sudo reboot"
