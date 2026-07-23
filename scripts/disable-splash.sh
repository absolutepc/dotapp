#!/usr/bin/env bash
# Aggressively silence ALL boot text on the round HDMI panel.
# Covers: rainbow splash, Plymouth, kernel/fbcon, e2fsck, U-Boot video console.
# Run: sudo bash scripts/disable-splash.sh
set -euo pipefail

echo "=== Silence Dot HDMI boot console ==="

CONFIG="/boot/firmware/config.txt"
[[ -f "${CONFIG}" ]] || CONFIG="/boot/config.txt"
CMDLINE="/boot/firmware/cmdline.txt"
[[ -f "${CMDLINE}" ]] || CMDLINE="/boot/cmdline.txt"
BOOTDIR="$(dirname "${CMDLINE}")"

if [[ ! -f "${CONFIG}" || ! -f "${CMDLINE}" ]]; then
  echo "ERROR: cannot find config.txt / cmdline.txt" >&2
  exit 1
fi

# 1) Rainbow / early GPU firmware splash
grep -qE '^[[:space:]]*disable_splash=1' "${CONFIG}" || echo "disable_splash=1" >>"${CONFIG}"
# Hide under-voltage / thermal warning overlays on the panel
grep -qE '^[[:space:]]*avoid_warnings=1' "${CONFIG}" || echo "avoid_warnings=1" >>"${CONFIG}"
echo "[ok] ${CONFIG}: disable_splash=1 avoid_warnings=1"

# 2) cmdline — no HDMI virtual terminal, no splash, minimal printk
cp -a "${CMDLINE}" "${CMDLINE}.bak.$(date +%s)"
python3 - "${CMDLINE}" <<'PY'
import sys
path = sys.argv[1]
tokens = open(path).read().strip().split()

drop_exact = {
    "splash", "nosplash", "plymouth.ignore-serial-consoles",
    "quiet", "logo.nologo", "consoleblank=0",
    "vt.global_cursor_default=0", "systemd.show_status=false",
    "loglevel=0", "loglevel=1", "loglevel=2", "loglevel=3",
    "fbcon=map:99", "fbcon=logo-count:0",
}
kept = []
for t in tokens:
    if t in drop_exact:
        continue
    if t.startswith("loglevel="):
        continue
    if t.startswith("console="):
        # Drop HDMI/VT consoles (tty1/tty2/tty3/ttyAMA without serial naming).
        # Keep UART so SSH/serial debug still works when cabled.
        val = t.split("=", 1)[1]
        if val.startswith("tty") and not val.startswith("ttyS") and not val.startswith("ttyAMA") and "serial" not in val:
            # console=tty1 / tty3 → drop (these paint on the round panel)
            continue
        kept.append(t)
        continue
    if t.startswith("fbcon="):
        continue
    kept.append(t)

# Ensure a serial console remains if none left (headless debug)
if not any(t.startswith("console=") for t in kept):
    kept.append("console=serial0,115200")

for need in (
    "quiet",
    "loglevel=0",
    "logo.nologo",
    "vt.global_cursor_default=0",
    "consoleblank=0",
    "systemd.show_status=false",
    "fbcon=map:99",
):
    key = need.split("=")[0]
    kept = [t for t in kept if t != key and not t.startswith(key + "=")]
    kept.append(need)

open(path, "w").write(" ".join(kept) + "\n")
print("[ok] cmdline rewritten (no HDMI VT console)")
print(open(path).read())
PY

# 3) Mask Plymouth + getty on tty1
for svc in plymouth-start plymouth-read-write plymouth-quit plymouth-quit-wait \
           plymouth-reboot plymouth-halt plymouth-kexec; do
  systemctl disable "${svc}" 2>/dev/null || true
  systemctl mask "${svc}" 2>/dev/null || true
done
systemctl disable getty@tty1 2>/dev/null || true
systemctl mask getty@tty1 2>/dev/null || true
echo "[ok] Plymouth + getty@tty1 masked"

# 4) raspi-config: Splash Screen = No
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_boot_splash 1 2>/dev/null && echo "[ok] raspi-config splash=No" || true
fi

# 5) Black out Plymouth art leftovers
PIX="/usr/share/plymouth/themes/pix/splash.png"
if [[ -f "${PIX}" ]]; then
  cp -a "${PIX}" "${PIX}.bak" 2>/dev/null || true
  python3 - <<'PY' 2>/dev/null || true
from pathlib import Path
try:
    from PIL import Image
    Image.new("RGB", (1920, 1080), (0, 0, 0)).save("/usr/share/plymouth/themes/pix/splash.png")
    print("[ok] splash.png -> black")
except Exception as e:
    print("[warn] splash.png:", e)
PY
fi

# 6) initramfs refresh
if command -v update-initramfs >/dev/null 2>&1; then
  echo "[..] update-initramfs…"
  update-initramfs -u || true
fi

# 7) cloud-init spam
mkdir -p /etc/cloud
touch /etc/cloud/cloud-init.disabled
for svc in cloud-init cloud-init-local cloud-config cloud-final \
           cloud-init-main.service cloud-init-network.service; do
  systemctl disable "${svc}" 2>/dev/null || true
  systemctl mask "${svc}" 2>/dev/null || true
done
echo "[ok] cloud-init disabled"

# 8) printk after boot
mkdir -p /etc/sysctl.d
cat >/etc/sysctl.d/20-quiet-console.conf <<'EOF'
kernel.printk = 0 4 1 3
EOF
echo "[ok] kernel.printk quieted"

# 9) Silence U-Boot video console (this is the white "U-Boot 2023…" text)
silence_uboot() {
  if command -v fw_setenv >/dev/null 2>&1; then
    fw_setenv silent 1 2>/dev/null || true
    fw_setenv bootdelay 0 2>/dev/null || true
    fw_setenv stdout serial 2>/dev/null || true
    fw_setenv stderr serial 2>/dev/null || true
    fw_setenv stdin serial 2>/dev/null || true
    echo "[ok] fw_setenv silent/stdout=serial"
    return 0
  fi

  # Ubuntu/flash-kernel style: drop a uEnv snippet if the boot partition is writable
  for envfile in \
      "${BOOTDIR}/uboot.env.txt" \
      "${BOOTDIR}/uEnv.txt" \
      "${BOOTDIR}/boot.env" \
      /boot/uboot.env.txt \
      /boot/uEnv.txt; do
    dir="$(dirname "${envfile}")"
    [[ -d "${dir}" ]] || continue
    cat >"${envfile}" <<'EOF'
silent=1
bootdelay=0
stdout=serial
stderr=serial
stdin=serial
EOF
    echo "[ok] wrote ${envfile}"
    return 0
  done

  # Last resort: boot.cmd fragment users can compile if they use boot.scr
  cat >"${BOOTDIR}/dot-silent-uboot.txt" <<'EOF'
# Dot: paste into U-Boot env or prepend to boot.cmd, then rebuild boot.scr:
#   setenv silent 1
#   setenv bootdelay 0
#   setenv stdout serial
#   setenv stderr serial
#   setenv stdin serial
#   saveenv
EOF
  echo "[warn] fw_setenv not found — see ${BOOTDIR}/dot-silent-uboot.txt for U-Boot silence"
  return 0
}
silence_uboot

# 10) Early black framebuffer oneshot (covers leftover glyphs until kmsdrm starts)
cat >/etc/systemd/system/dot-blank-hdmi.service <<'EOF'
[Unit]
Description=Blank HDMI framebuffer before Dot logo
DefaultDependencies=no
After=local-fs.target sysinit.target
Before=dot-display.service getty@tty1.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for v in /sys/class/vtconsole/vtcon*/bind; do echo 0 > "$v" 2>/dev/null || true; done; if [ -e /dev/fb0 ]; then dd if=/dev/zero of=/dev/fb0 bs=1024 count=8192 status=none 2>/dev/null || true; fi'

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable dot-blank-hdmi.service
echo "[ok] dot-blank-hdmi.service enabled"

echo ""
echo "Verify cmdline (should have quiet + fbcon=map:99, NO console=tty1/tty3):"
cat "${CMDLINE}"
echo ""
echo "Reboot required: sudo reboot"
echo "Expected: black panel → Dot logo (no U-Boot / kernel text)."
