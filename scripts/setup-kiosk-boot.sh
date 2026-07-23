#!/usr/bin/env bash
# Boot straight to Dot logo: no desktop, no splash screens.
# Run on Pi: sudo bash scripts/setup-kiosk-boot.sh [username]
set -euo pipefail

PI_USER="${1:-${SUDO_USER:-pi}}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Prefer a tree that actually has firmware + a usable venv.
# /opt/dot often exists as an empty/partial stub and must not win over ~/dotapp.
_has_runtime() {
  local root="$1"
  [[ -d "${root}/firmware" ]] || return 1
  [[ -x "${root}/venv/bin/python" || -x "${root}/.venv/bin/python" ]] || return 1
  [[ -x "${root}/venv/bin/uvicorn" || -x "${root}/.venv/bin/uvicorn" ]] || return 1
  return 0
}

if [[ -n "${DOT_INSTALL:-}" ]]; then
  INSTALL_DIR="${DOT_INSTALL}"
elif _has_runtime "${REPO_ROOT}"; then
  INSTALL_DIR="${REPO_ROOT}"
elif _has_runtime /opt/dot; then
  INSTALL_DIR="/opt/dot"
elif [[ -d "${REPO_ROOT}/firmware" ]]; then
  INSTALL_DIR="${REPO_ROOT}"
else
  INSTALL_DIR="/opt/dot"
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
  grep -qE '^[[:space:]]*disable_splash=1' "${CONFIG}" || echo "disable_splash=1" >>"${CONFIG}"
  grep -qE '^[[:space:]]*avoid_warnings=1' "${CONFIG}" || echo "avoid_warnings=1" >>"${CONFIG}"
  echo "Updated ${CONFIG} (disable_splash=1, avoid_warnings=1)"
fi

# Full silence: no HDMI VT, no U-Boot text if possible, early blank
if [[ -f "${REPO_ROOT}/scripts/disable-splash.sh" ]]; then
  bash "${REPO_ROOT}/scripts/disable-splash.sh" || true
fi

# --- No desktop / no Plymouth ---
systemctl set-default multi-user.target
systemctl disable lightdm 2>/dev/null || true
systemctl disable gdm 2>/dev/null || true
systemctl disable gdm3 2>/dev/null || true
systemctl disable wayfire 2>/dev/null || true
systemctl disable labwc 2>/dev/null || true
systemctl mask lightdm 2>/dev/null || true
# Keep tty1 free for the kiosk renderer (kmsdrm)
systemctl disable getty@tty1 2>/dev/null || true
systemctl mask getty@tty1 2>/dev/null || true
for svc in plymouth-start plymouth-read-write plymouth-quit plymouth-quit-wait plymouth-reboot plymouth-halt plymouth-kexec; do
  systemctl disable "${svc}" 2>/dev/null || true
  systemctl mask "${svc}" 2>/dev/null || true
done
echo "Default target: multi-user (no desktop, Plymouth masked, tty1 for logo)"

# Also via raspi-config noninteractive if available (1 = Splash Screen No)
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_boot_splash 1 2>/dev/null || true
fi

# Rebuild initramfs / black out leftover Plymouth art — already done via disable-splash.sh above

# Prefer shared path rewriter (short unit names dot-api / dot-display)
if [[ -x "${INSTALL_DIR}/scripts/fix-systemd-paths.sh" ]]; then
  bash "${INSTALL_DIR}/scripts/fix-systemd-paths.sh" "${PI_USER}" kiosk
else
  # Fallback: inline rewrite
  for old in bmw-logo-api bmw-logo-display bmw-api bmw-display; do
    systemctl disable --now "${old}" 2>/dev/null || true
    rm -f "/etc/systemd/system/${old}.service"
  done
  sed "s|User=pi|User=${PI_USER}|g; s|/opt/dot|${INSTALL_DIR}|g" \
    "${INSTALL_DIR}/firmware/systemd/dot-display-kiosk.service" \
    >/etc/systemd/system/dot-display.service
  sed "s|User=pi|User=${PI_USER}|g; s|/opt/dot|${INSTALL_DIR}|g" \
    "${INSTALL_DIR}/firmware/systemd/dot-api.service" \
    >/etc/systemd/system/dot-api.service
  if [[ -x "${INSTALL_DIR}/venv/bin/python" ]]; then
    sed -i "s|/\.venv/bin/|/venv/bin/|g" \
      /etc/systemd/system/dot-display.service \
      /etc/systemd/system/dot-api.service
  fi
  usermod -aG video,render "${PI_USER}" 2>/dev/null || usermod -aG video "${PI_USER}" 2>/dev/null || true
  systemctl daemon-reload
  systemctl enable dot-api dot-display
  systemctl restart dot-api dot-display 2>/dev/null || true
fi

echo ""
echo "Kiosk boot configured."
echo "  - No desktop / no Plymouth / no cloud-init spam"
echo "  - Logo renderer on tty1 (kmsdrm)"
echo "  - Last selected animation starts via /var/lib/dot/state (API prepares it on boot)"
echo ""
echo "Check now (before reboot):"
echo "  systemctl get-default"
echo "  systemctl is-enabled dot-api dot-display"
echo "  systemctl cat dot-display | grep -E 'User=|ExecStart=|SDL_'"
echo "  journalctl -u dot-display -n 30 --no-pager"
echo ""
echo "Reboot to apply: sudo reboot"
echo ""
echo "To restore desktop:"
echo "  sudo systemctl set-default graphical.target"
echo "  sudo systemctl unmask lightdm getty@tty1 plymouth-start"
echo "  sudo systemctl enable lightdm"
echo "  sudo bash scripts/fix-systemd-paths.sh ${PI_USER} desktop"
echo "  sudo rm -f /etc/cloud/cloud-init.disabled"
echo "  sudo reboot"
