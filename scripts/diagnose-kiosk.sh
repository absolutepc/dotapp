#!/usr/bin/env bash
# Diagnose black screen / leftover e2fsck text in kiosk mode.
# Run on Pi: bash scripts/diagnose-kiosk.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "=== Dot kiosk diagnose ==="
echo "Repo: ${ROOT}"
echo "Date: $(date -Is)"
echo

echo "--- boot target / units ---"
systemctl get-default || true
systemctl is-enabled dot-api dot-display 2>/dev/null || true
systemctl is-active dot-api dot-display 2>/dev/null || true
echo

echo "--- dot-display unit (paths) ---"
systemctl cat dot-display 2>/dev/null | grep -E '^(User=|WorkingDirectory=|Environment=|ExecStart|TTYPath=)' || {
  echo "ERROR: dot-display unit missing — run: sudo bash scripts/setup-kiosk-boot.sh \$USER"
  exit 1
}
echo

echo "--- recent display logs ---"
journalctl -u dot-display -n 40 --no-pager || true
echo

echo "--- display devices ---"
ls -l /dev/dri /dev/fb0 /dev/tty1 2>/dev/null || true
groups "${SUDO_USER:-$USER}" 2>/dev/null || true
id "${SUDO_USER:-$USER}" 2>/dev/null || true
echo

echo "--- cmdline / hdmi ---"
CMDLINE="/boot/firmware/cmdline.txt"
[[ -f "${CMDLINE}" ]] || CMDLINE="/boot/cmdline.txt"
CONFIG="/boot/firmware/config.txt"
[[ -f "${CONFIG}" ]] || CONFIG="/boot/config.txt"
echo "cmdline: $(tr -d '\n' <"${CMDLINE}" 2>/dev/null || echo missing)"
echo
grep -E '^(disable_splash|hdmi_|dtoverlay=vc4|dtoverlay=vkms)' "${CONFIG}" 2>/dev/null || true
echo

echo "--- state / frames ---"
ls -la /var/lib/dot/state 2>/dev/null || echo "no /var/lib/dot/state"
python3 - <<'PY' 2>/dev/null || true
import json
from pathlib import Path
p = Path("/var/lib/dot/state")
if p.exists():
    print(p.read_text()[:400])
PY
echo

echo "--- pygame drivers (quick) ---"
if [[ -x "${ROOT}/venv/bin/python" ]]; then
  PY="${ROOT}/venv/bin/python"
elif [[ -x "${ROOT}/.venv/bin/python" ]]; then
  PY="${ROOT}/.venv/bin/python"
else
  PY=""
fi
if [[ -n "${PY}" ]]; then
  sudo -u "${SUDO_USER:-$USER}" env SDL_VIDEODRIVER=kmsdrm "${PY}" - <<'PY' 2>&1 | sed 's/^/  /' || true
import os, pygame
for driver in ("kmsdrm", "fbcon"):
    os.environ["SDL_VIDEODRIVER"] = driver
    pygame.display.quit(); pygame.quit()
    try:
        pygame.init(); pygame.display.init()
        s = pygame.display.set_mode((64, 64))
        print(f"OK  {driver} -> {pygame.display.get_driver()}")
        pygame.display.quit(); pygame.quit()
    except Exception as e:
        print(f"NO  {driver}: {e}")
PY
else
  echo "no venv python in ${ROOT}"
fi
echo

echo "=== suggested fixes ==="
echo "1) Re-apply kiosk units + reboot:"
echo "     cd ${ROOT} && sudo bash scripts/setup-kiosk-boot.sh ${SUDO_USER:-$USER} && sudo reboot"
echo "2) If logs say No SDL display driver:"
echo "     cd ${ROOT} && bash scripts/fix-pygame-display.sh && sudo systemctl restart dot-display"
echo "3) Force a logo now (after display is up):"
echo "     show list && show anim3"
echo "4) Temporary desktop for debugging:"
echo "     sudo systemctl set-default graphical.target && sudo systemctl unmask lightdm getty@tty1 && sudo reboot"
