#!/usr/bin/env bash
# Aggressively disable ALL Raspberry Pi boot splash screens.
# Run: sudo bash scripts/disable-splash.sh
set -euo pipefail

echo "=== Disable Raspberry Pi splash screens ==="

CONFIG="/boot/firmware/config.txt"
[[ -f "${CONFIG}" ]] || CONFIG="/boot/config.txt"
CMDLINE="/boot/firmware/cmdline.txt"
[[ -f "${CMDLINE}" ]] || CMDLINE="/boot/cmdline.txt"

if [[ ! -f "${CONFIG}" || ! -f "${CMDLINE}" ]]; then
  echo "ERROR: cannot find config.txt / cmdline.txt" >&2
  exit 1
fi

# 1) Rainbow / early firmware splash
if ! grep -q '^disable_splash=1' "${CONFIG}"; then
  echo "disable_splash=1" >>"${CONFIG}"
fi
echo "[ok] ${CONFIG}: disable_splash=1"

# 2) Plymouth graphical splash ("Welcome to Raspberry Pi Desktop")
#    The word "splash" in cmdline ENABLES it — remove it.
cp -a "${CMDLINE}" "${CMDLINE}.bak.$(date +%s)"
# Keep as a single line; strip splash-related tokens
python3 - "${CMDLINE}" <<'PY'
import sys
path = sys.argv[1]
tokens = open(path).read().strip().split()
drop = {"splash", "nosplash", "plymouth.ignore-serial-consoles"}
kept = [t for t in tokens if t not in drop]
kept = ["console=tty3" if t == "console=tty1" else t for t in kept]
for need in ("quiet", "loglevel=0", "logo.nologo", "vt.global_cursor_default=0", "consoleblank=0"):
    key = need.split("=")[0]
    kept = [t for t in kept if t != key and not t.startswith(key + "=")]
    kept.append(need)
open(path, "w").write(" ".join(kept) + "\n")
print("[ok] cmdline rewritten")
print(open(path).read())
PY

# 3) Mask Plymouth units
for svc in plymouth-start plymouth-read-write plymouth-quit plymouth-quit-wait \
           plymouth-reboot plymouth-halt plymouth-kexec; do
  systemctl disable "${svc}" 2>/dev/null || true
  systemctl mask "${svc}" 2>/dev/null || true
done
echo "[ok] Plymouth services masked"

# 4) raspi-config: Splash Screen = No  (1 = No in nonint API)
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_boot_splash 1 2>/dev/null && echo "[ok] raspi-config splash=No" || true
fi

# 5) Replace Plymouth theme image with solid black (covers initramfs leftover)
PIX="/usr/share/plymouth/themes/pix/splash.png"
if [[ -f "${PIX}" ]]; then
  cp -a "${PIX}" "${PIX}.bak" 2>/dev/null || true
  if command -v convert >/dev/null 2>&1; then
    convert -size 1920x1080 xc:black "${PIX}"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
from pathlib import Path
try:
    from PIL import Image
    Image.new("RGB", (1920, 1080), (0, 0, 0)).save("/usr/share/plymouth/themes/pix/splash.png")
    print("[ok] splash.png -> black")
except Exception as e:
    print("[warn] could not rewrite splash.png:", e)
PY
  fi
fi

# 6) Rebuild initramfs so Plymouth changes take effect
if command -v update-initramfs >/dev/null 2>&1; then
  echo "[..] update-initramfs (may take a minute on Pi Zero)…"
  update-initramfs -u
  echo "[ok] initramfs updated"
elif command -v plymouth-set-default-theme >/dev/null 2>&1; then
  plymouth-set-default-theme -R text 2>/dev/null || true
  echo "[ok] plymouth theme -> text"
fi

echo ""
echo "Verify (must NOT contain the word 'splash'):"
echo "--- cmdline ---"
cat "${CMDLINE}"
echo "--- config ---"
grep disable_splash "${CONFIG}" || true
echo ""
echo "Now reboot: sudo reboot"
