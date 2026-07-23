#!/usr/bin/env bash
# Fix "No SDL display driver available" on Raspberry Pi kiosk.
#
# PyPI pygame wheels (and some source builds) often have ZERO video backends.
# This script prefers Debian's python3-pygame via a --system-site-packages venv.
#
# Run on Pi: bash scripts/fix-pygame-display.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROBE_USER="${SUDO_USER:-${USER}}"

echo "=== Dot pygame / SDL fix ==="
echo "Repo: ${ROOT}"
echo

echo "--- devices / groups ---"
ls -l /dev/dri /dev/fb0 2>/dev/null || echo "WARN: no /dev/dri or /dev/fb0"
id "${PROBE_USER}"
groups "${PROBE_USER}" || true
CONFIG="/boot/firmware/config.txt"
[[ -f "${CONFIG}" ]] || CONFIG="/boot/config.txt"
if [[ -f "${CONFIG}" ]]; then
  echo "--- ${CONFIG} (video bits) ---"
  grep -E '^(dtoverlay=vc4|hdmi_|framebuffer_|disable_splash|gpu_mem)' "${CONFIG}" || true
  if ! grep -qE '^[[:space:]]*dtoverlay=vc4-kms-v3d' "${CONFIG}"; then
    echo "NOTE: adding dtoverlay=vc4-kms-v3d (needed for kmsdrm)"
    echo "dtoverlay=vc4-kms-v3d" | sudo tee -a "${CONFIG}" >/dev/null
  fi
fi
echo

echo "--- apt: SDL / Mesa / system pygame ---"
sudo apt-get update
sudo apt-get install -y \
  build-essential pkg-config python3-dev \
  libsdl2-2.0-0 libsdl2-dev \
  libsdl2-image-2.0-0 libsdl2-image-dev \
  libsdl2-mixer-2.0-0 libsdl2-mixer-dev \
  libsdl2-ttf-2.0-0 libsdl2-ttf-dev \
  libgbm1 libgbm-dev libdrm2 libdrm-dev \
  libegl1 libegl-dev libgles2 \
  libxss1 libx11-6 libxext6 \
  libjpeg-dev libpng-dev \
  python3-pygame
# Optional packages (names differ by release)
sudo apt-get install -y libgles-dev 2>/dev/null || true
sudo apt-get install -y libgl1-mesa-dri 2>/dev/null || true
sudo apt-get install -y mesa-libgallium 2>/dev/null || true
sudo apt-get install -y kmscube 2>/dev/null || true

usermod -aG video,render "${PROBE_USER}" 2>/dev/null || usermod -aG video "${PROBE_USER}" 2>/dev/null || true

echo
echo "--- recreate venv with system-site-packages (Debian pygame) ---"
cd "${ROOT}"
if [[ -d venv ]]; then
  stamp="$(date +%Y%m%d%H%M%S)"
  mv venv "venv.bak-sdl-${stamp}"
  echo "Moved old venv → venv.bak-sdl-${stamp}"
fi
python3 -m venv --system-site-packages venv
venv/bin/pip install --upgrade pip
# Install deps but DO NOT let pip shadow Debian pygame with a broken wheel
grep -viE '^[[:space:]]*pygame' firmware/requirements.txt > /tmp/dot-req-no-pygame.txt
venv/bin/pip install -r /tmp/dot-req-no-pygame.txt
venv/bin/pip uninstall -y pygame 2>/dev/null || true

PY="${ROOT}/venv/bin/python"
echo
echo "--- which pygame? ---"
"${PY}" - <<'PY'
import pygame, pathlib
print("pygame", pygame.version.ver, "SDL", pygame.version.SDL)
print("file", pathlib.Path(pygame.__file__))
PY

echo
echo "--- SDL video drivers (ctypes) ---"
"${PY}" - <<'PY'
import ctypes
try:
    sdl = ctypes.CDLL("libSDL2-2.0.so.0")
except OSError as e:
    print("Cannot load libSDL2:", e)
    raise SystemExit(1)
sdl.SDL_GetNumVideoDrivers.restype = ctypes.c_int
sdl.SDL_GetVideoDriver.argtypes = [ctypes.c_int]
sdl.SDL_GetVideoDriver.restype = ctypes.c_char_p
n = sdl.SDL_GetNumVideoDrivers()
print(f"SDL_GetNumVideoDrivers = {n}")
for i in range(n):
    name = sdl.SDL_GetVideoDriver(i)
    print(f"  [{i}] {name.decode() if name else '?'}")
if n == 0:
    print("ERROR: SDL built with no video drivers")
PY

echo
echo "--- probe display (auto, then kmsdrm/fbcon/x11) ---"
ok=0
probe() {
  local mode="$1"
  if sudo -u "${PROBE_USER}" "${PY}" - <<PY
import os, sys
# Clear forced driver for auto mode
if "${mode}" == "auto":
    os.environ.pop("SDL_VIDEODRIVER", None)
else:
    os.environ["SDL_VIDEODRIVER"] = "${mode}"
os.environ.setdefault("SDL_VIDEO_EGL_DRIVER", "libEGL.so.1")
os.environ.setdefault("SDL_VIDEO_GL_DRIVER", "libGLESv2.so.2")
import pygame
pygame.display.quit(); pygame.quit()
pygame.init()
pygame.display.init()
screen = pygame.display.set_mode((64, 64))
print("OK  ${mode} ->", pygame.display.get_driver())
pygame.display.quit(); pygame.quit()
PY
  then
    ok=1
  else
    echo "NO  ${mode}"
  fi
}

probe auto
probe kmsdrm
probe fbcon
probe x11

echo
if [[ "${ok}" -eq 0 ]]; then
  echo "ERROR: still no usable display." >&2
  echo "Run and paste output:" >&2
  echo "  ls -l /dev/dri /dev/fb0" >&2
  echo "  ${PY} -c 'import pygame; print(pygame.version)'" >&2
  echo "  kmscube  # should draw on the HDMI panel if DRM works" >&2
  exit 1
fi

echo "--- rewrite systemd units ---"
if [[ -x "${ROOT}/scripts/fix-systemd-paths.sh" ]]; then
  sudo bash "${ROOT}/scripts/fix-systemd-paths.sh" "${PROBE_USER}" kiosk || \
    sudo bash "${ROOT}/scripts/fix-systemd-paths.sh" "${PROBE_USER}" auto
fi

# Soften hard-coded SDL_VIDEODRIVER=kmsdrm so auto/fallback works
if [[ -f /etc/systemd/system/dot-display.service ]]; then
  sudo sed -i '/^Environment=SDL_VIDEODRIVER=/d' /etc/systemd/system/dot-display.service || true
  if ! grep -q 'SDL_VIDEO_EGL_DRIVER' /etc/systemd/system/dot-display.service; then
    sudo sed -i '/^Environment=PYTHONPATH=/a Environment=SDL_VIDEO_EGL_DRIVER=libEGL.so.1\nEnvironment=SDL_VIDEO_GL_DRIVER=libGLESv2.so.2' \
      /etc/systemd/system/dot-display.service || true
  fi
  sudo systemctl daemon-reload
fi

echo "Restarting Dot display…"
sudo systemctl restart dot-api dot-display || true
sleep 3
systemctl is-active dot-api dot-display || true
journalctl -u dot-display -n 20 --no-pager || true
echo
echo "Done. If active: show anim3 && sudo reboot"
echo "NOTE: if you just added vc4-kms-v3d, reboot is required."
