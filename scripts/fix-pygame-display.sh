#!/usr/bin/env bash
# Install system SDL video backends and rebuild pygame against them.
# Fixes: "No SDL display driver available: x11/kmsdrm not available"
# Run on Pi: bash scripts/fix-pygame-display.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -x "${ROOT}/venv/bin/pip" ]]; then
  PIP="${ROOT}/venv/bin/pip"
  PY="${ROOT}/venv/bin/python"
elif [[ -x "${ROOT}/.venv/bin/pip" ]]; then
  PIP="${ROOT}/.venv/bin/pip"
  PY="${ROOT}/.venv/bin/python"
else
  echo "ERROR: venv not found in ${ROOT}" >&2
  exit 1
fi

echo "Installing SDL / DRM runtime + build deps…"
sudo apt-get update
sudo apt-get install -y \
  build-essential pkg-config python3-dev \
  libsdl2-2.0-0 libsdl2-image-2.0-0 libsdl2-mixer-2.0-0 libsdl2-ttf-2.0-0 \
  libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-ttf-dev \
  libgbm1 libdrm2 libegl1 libxss1 libx11-6 libxext6 \
  libgbm-dev libdrm-dev libegl-dev \
  libjpeg-dev libpng-dev \
  python3-pygame

echo "Rebuilding pygame in venv from source (linked to system SDL with kmsdrm)…"
"${PIP}" uninstall -y pygame || true
# Binary wheels from PyPI often ship without kmsdrm/fbcon — force a source build.
"${PIP}" install --no-cache-dir --force-reinstall --no-binary=pygame 'pygame>=2.5.0,<3'

echo "Probe drivers…"
ok=0
# Probe as the install user when possible (matches systemd User=)
PROBE_USER="${SUDO_USER:-${USER}}"
probe() {
  local driver="$1"
  sudo -u "${PROBE_USER}" env -u DISPLAY SDL_VIDEODRIVER="${driver}" "${PY}" - <<PY
import os, pygame
os.environ["SDL_VIDEODRIVER"] = "${driver}"
pygame.display.quit()
pygame.quit()
pygame.init()
pygame.display.init()
screen = pygame.display.set_mode((64, 64))
print(f"OK  ${driver} -> {pygame.display.get_driver()}")
pygame.display.quit()
pygame.quit()
PY
}

for driver in kmsdrm fbcon x11; do
  if probe "${driver}"; then
    ok=1
  else
    echo "NO  ${driver}"
  fi
done

echo ""
if [[ "${ok}" -eq 0 ]]; then
  echo "ERROR: still no SDL video driver. Check cable/HDMI and:" >&2
  echo "  ls -l /dev/dri /dev/fb0" >&2
  echo "  groups ${PROBE_USER}" >&2
  exit 1
fi

echo "Restarting Dot display…"
sudo systemctl restart dot-display || true
sleep 2
systemctl is-active dot-display || true
journalctl -u dot-display -n 15 --no-pager || true
echo ""
echo "If active: show list && show anim3"
