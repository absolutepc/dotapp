#!/usr/bin/env bash
# Boot straight to BMW logo: no desktop, no splash screens.
# Run on Pi: sudo bash scripts/setup-kiosk-boot.sh [username]
set -euo pipefail

PI_USER="${1:-${SUDO_USER:-pi}}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Prefer a tree that actually has firmware + a usable venv.
# /opt/bmw-logo often exists as an empty/partial stub and must not win over ~/dotapp.
_has_runtime() {
  local root="$1"
  [[ -d "${root}/firmware" ]] || return 1
  [[ -x "${root}/venv/bin/python" || -x "${root}/.venv/bin/python" ]] || return 1
  [[ -x "${root}/venv/bin/uvicorn" || -x "${root}/.venv/bin/uvicorn" ]] || return 1
  return 0
}

if [[ -n "${BMW_LOGO_INSTALL:-}" ]]; then
  INSTALL_DIR="${BMW_LOGO_INSTALL}"
elif _has_runtime "${REPO_ROOT}"; then
  INSTALL_DIR="${REPO_ROOT}"
elif _has_runtime /opt/bmw-logo; then
  INSTALL_DIR="/opt/bmw-logo"
elif [[ -d "${REPO_ROOT}/firmware" ]]; then
  INSTALL_DIR="${REPO_ROOT}"
else
  INSTALL_DIR="/opt/bmw-logo"
fi

echo "Kiosk boot setup for user: ${PI_USER}"
echo "Install dir: ${INSTALL_DIR}"
if ! _has_runtime "${INSTALL_DIR}"; then
  echo "WARNING: ${INSTALL_DIR} has no usable venv (expected venv/ or .venv/ with python+uvicorn)" >&2
fi

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

# Prefer shared path rewriter (short unit names bmw-api / bmw-display)
if [[ -x "${INSTALL_DIR}/scripts/fix-systemd-paths.sh" ]]; then
  bash "${INSTALL_DIR}/scripts/fix-systemd-paths.sh" "${PI_USER}" kiosk
else
  # Fallback: inline rewrite
  for old in bmw-logo-api bmw-logo-display; do
    systemctl disable --now "${old}" 2>/dev/null || true
    rm -f "/etc/systemd/system/${old}.service"
  done
  sed "s|User=pi|User=${PI_USER}|g; s|/opt/bmw-logo|${INSTALL_DIR}|g" \
    "${INSTALL_DIR}/firmware/systemd/bmw-display-kiosk.service" \
    >/etc/systemd/system/bmw-display.service
  sed "s|User=pi|User=${PI_USER}|g; s|/opt/bmw-logo|${INSTALL_DIR}|g" \
    "${INSTALL_DIR}/firmware/systemd/bmw-api.service" \
    >/etc/systemd/system/bmw-api.service
  if [[ -x "${INSTALL_DIR}/venv/bin/python" ]]; then
    sed -i "s|/\.venv/bin/|/venv/bin/|g" \
      /etc/systemd/system/bmw-display.service \
      /etc/systemd/system/bmw-api.service
  fi
  usermod -aG video,render "${PI_USER}" 2>/dev/null || usermod -aG video "${PI_USER}" 2>/dev/null || true
  systemctl daemon-reload
  systemctl enable bmw-api bmw-display
  systemctl restart bmw-api bmw-display 2>/dev/null || true
fi

echo ""
echo "Kiosk boot configured."
echo "  - No desktop / no Plymouth / no cloud-init spam"
echo "  - Logo renderer on tty1 (kmsdrm)"
echo ""
echo "Check now (before reboot):"
echo "  systemctl --no-pager --failed"
echo "  journalctl -u bmw-display -n 30 --no-pager"
echo ""
echo "Reboot to apply quiet boot: sudo reboot"
echo ""
echo "To restore desktop:"
echo "  sudo systemctl set-default graphical.target"
echo "  sudo systemctl enable lightdm"
echo "  sudo systemctl unmask plymouth-start"
echo "  sudo rm -f /etc/cloud/cloud-init.disabled"
echo "  sudo reboot"
