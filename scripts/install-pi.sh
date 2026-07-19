#!/usr/bin/env bash
# Install BMW Logo firmware on Raspberry Pi.
# Usage:
#   cd ~/dotapp
#   sudo bash scripts/install-pi.sh [username] [desktop|kiosk]
#
# Default: install in-place (this checkout), not /opt/bmw-logo.
# Set BMW_LOGO_INSTALL=/opt/bmw-logo to copy into /opt instead.
set -euo pipefail

PI_USER="${1:-${SUDO_USER:-pi}}"
MODE="${2:-desktop}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${BMW_LOGO_INSTALL:-${REPO_ROOT}}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo: sudo bash scripts/install-pi.sh [username] [desktop|kiosk]" >&2
  exit 1
fi

echo "User: ${PI_USER}"
echo "Mode: ${MODE}"
echo "Install dir: ${INSTALL_DIR}"

apt-get update
apt-get install -y ffmpeg python3-venv python3-pip rsync git \
  libsdl2-2.0-0 libsdl2-image-2.0-0 libsdl2-mixer-2.0-0 libsdl2-ttf-2.0-0 \
  libgbm1 libdrm2 libegl1 libxss1 libx11-6 libxext6 python3-pygame

if [[ "${INSTALL_DIR}" != "${REPO_ROOT}" ]]; then
  echo "Syncing ${REPO_ROOT} → ${INSTALL_DIR}…"
  mkdir -p "${INSTALL_DIR}"
  rsync -a --delete \
    --exclude '.git' \
    --exclude 'ios' \
    --exclude 'venv' \
    --exclude '.venv' \
    --exclude '__pycache__' \
    "${REPO_ROOT}/" "${INSTALL_DIR}/"
fi

cd "${INSTALL_DIR}"

# Prefer venv/ (no leading dot) — matches existing Pi setups
if [[ ! -x venv/bin/python ]]; then
  python3 -m venv venv
fi
venv/bin/pip install --upgrade pip
venv/bin/pip install -r firmware/requirements.txt
# Pip wheels often lack x11/kmsdrm on Pi — rebuild against system SDL
venv/bin/pip install --no-cache-dir --force-reinstall --no-binary=pygame 'pygame>=2.5.0' \
  || echo "WARNING: pygame source build failed; trying binary wheel" >&2

mkdir -p /var/lib/bmw-logo/{media,frames,previews,state}
mkdir -p /var/run/bmw-logo
chown -R "${PI_USER}:${PI_USER}" /var/lib/bmw-logo /var/run/bmw-logo
# Do not chown the whole git tree if it already belongs to the user
chown -R "${PI_USER}:${PI_USER}" "${INSTALL_DIR}/venv" 2>/dev/null || true

# NEVER run generate_assets.py here — it wipes custom gallery WebM/GIF under assets/bmw/
if [[ ! -f assets/catalog.json ]]; then
  echo "WARNING: assets/catalog.json missing — gallery will be empty until you sync assets" >&2
fi

# Point systemd at this install + user + mode
bash "${INSTALL_DIR}/scripts/fix-systemd-paths.sh" "${PI_USER}" "${MODE}"

systemctl daemon-reload
systemctl enable bmw-logo-api bmw-logo-display
systemctl restart bmw-logo-api bmw-logo-display || true

echo ""
echo "Install complete."
echo "  API:     systemctl status bmw-logo-api --no-pager"
echo "  Display: systemctl status bmw-logo-display --no-pager"
echo "  Switch:  sudo -u ${PI_USER} ${INSTALL_DIR}/scripts/show anim3"
echo ""
if [[ "${MODE}" == "kiosk" ]]; then
  echo "Optional quiet kiosk boot:"
  echo "  sudo bash ${INSTALL_DIR}/scripts/setup-kiosk-boot.sh ${PI_USER}"
  echo "  sudo reboot"
else
  echo "Desktop mode: animation uses X11 on :0 after graphical login."
  echo "  After reboot, wait for desktop, then: ${INSTALL_DIR}/scripts/show anim3"
fi
