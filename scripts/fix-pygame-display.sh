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
echo "--- probe display (SSH often cannot open KMSDRM; offscreen ≠ success) ---"
ok=0
have_kms=0
if "${PY}" - <<'PY'
import ctypes
sdl = ctypes.CDLL("libSDL2-2.0.so.0")
sdl.SDL_GetNumVideoDrivers.restype = ctypes.c_int
sdl.SDL_GetVideoDriver.argtypes = [ctypes.c_int]
sdl.SDL_GetVideoDriver.restype = ctypes.c_char_p
names = [(sdl.SDL_GetVideoDriver(i) or b"").decode().lower() for i in range(sdl.SDL_GetNumVideoDrivers())]
print("drivers:", ", ".join(names) or "(none)")
raise SystemExit(0 if "kmsdrm" in names else 1)
PY
then
  have_kms=1
  ok=1
  echo "OK  SDL lists KMSDRM (will use root+tty1 systemd service)"
else
  echo "NO  KMSDRM not in SDL driver list"
fi

# Optional live probe as root on tty context — may still fail over plain SSH
if sudo env SDL_VIDEODRIVER=KMSDRM SDL_VIDEO_EGL_DRIVER=libEGL.so.1 \
  SDL_VIDEO_GL_DRIVER=libGLESv2.so.2 XDG_RUNTIME_DIR=/run/dot-display \
  "${PY}" -c "
import os, pygame
os.makedirs('/run/dot-display', exist_ok=True)
os.environ['SDL_VIDEODRIVER']='KMSDRM'
pygame.init(); pygame.display.init()
s=pygame.display.set_mode((64,64))
d=pygame.display.get_driver()
print('OK  root KMSDRM ->', d)
raise SystemExit(0 if d and d.lower() not in ('offscreen','dummy') else 1)
" 2>/dev/null; then
  ok=1
else
  echo "NOTE: live KMSDRM probe from SSH failed (common). Rely on systemd on tty1."
fi

echo
if [[ "${ok}" -eq 0 ]]; then
  echo "ERROR: SDL has no KMSDRM. Check:" >&2
  echo "  ls -l /dev/dri /dev/fb0" >&2
  echo "  grep dtoverlay /boot/firmware/config.txt" >&2
  exit 1
fi

echo "--- rewrite systemd units (kiosk display as root + KMSDRM) ---"
sudo bash "${ROOT}/scripts/fix-systemd-paths.sh" "${PROBE_USER}" kiosk

echo "Restarting Dot display…"
sudo systemctl restart dot-api dot-display || true
sleep 3
systemctl is-active dot-api dot-display || true
journalctl -u dot-display -n 25 --no-pager || true
echo
echo "Look for: Display driver: kmsdrm"
echo "Then: show anim3 && sudo reboot"
if [[ "${have_kms}" -eq 1 ]]; then
  echo "NOTE: 'OK auto -> offscreen' over SSH is normal; service runs as root on tty1."
fi
