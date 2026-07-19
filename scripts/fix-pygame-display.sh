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

echo "Installing SDL / DRM packages…"
sudo apt-get update
sudo apt-get install -y \
  libsdl2-2.0-0 libsdl2-image-2.0-0 libsdl2-mixer-2.0-0 libsdl2-ttf-2.0-0 \
  libgbm1 libdrm2 libegl1 libxss1 libx11-6 libxext6 \
  python3-pygame

echo "Rebuilding pygame in venv against system SDL (no binary wheel)…"
"${PIP}" uninstall -y pygame || true
"${PIP}" install --no-cache-dir --force-reinstall --no-binary=pygame 'pygame>=2.5.0'

echo "Probe drivers…"
DISPLAY="${DISPLAY:-:0}" "${PY}" - <<'PY'
import os
import pygame

os.environ.setdefault("DISPLAY", ":0")
print("DISPLAY=", os.environ.get("DISPLAY"))
print("pygame", pygame.version.ver)
for driver in ("x11", "kmsdrm", "fbcon"):
    os.environ["SDL_VIDEODRIVER"] = driver
    pygame.display.quit()
    pygame.quit()
    try:
        pygame.init()
        pygame.display.init()
        screen = pygame.display.set_mode((64, 64))
        print(f"OK  {driver} -> {pygame.display.get_driver()}")
        pygame.display.quit()
        pygame.quit()
    except Exception as exc:  # noqa: BLE001
        print(f"NO  {driver}: {exc}")
PY

echo ""
echo "If at least one driver printed OK, restart display:"
echo "  sudo systemctl restart bmw-display"
echo "  ./scripts/show anim3"
