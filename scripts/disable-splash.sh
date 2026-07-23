#!/usr/bin/env bash
# Soft silence for Dot HDMI boot (safe for Pi Zero 2W kiosk).
# Avoids fbcon=map:99 / stripping all VT consoles — those caused black screen
# + no Wi‑Fi after reboot on this hardware.
#
# Run: sudo bash scripts/disable-splash.sh
# Hard mode (may brick HDMI console until SD recovery): DOT_HARD_SILENCE=1 sudo bash …
set -euo pipefail

HARD="${DOT_HARD_SILENCE:-0}"

echo "=== Silence Dot HDMI boot console (hard=${HARD}) ==="

CONFIG="/boot/firmware/config.txt"
[[ -f "${CONFIG}" ]] || CONFIG="/boot/config.txt"
CMDLINE="/boot/firmware/cmdline.txt"
[[ -f "${CMDLINE}" ]] || CMDLINE="/boot/cmdline.txt"

if [[ ! -f "${CONFIG}" || ! -f "${CMDLINE}" ]]; then
  echo "ERROR: cannot find config.txt / cmdline.txt" >&2
  exit 1
fi

grep -qE '^[[:space:]]*disable_splash=1' "${CONFIG}" || echo "disable_splash=1" >>"${CONFIG}"
grep -qE '^[[:space:]]*avoid_warnings=1' "${CONFIG}" || echo "avoid_warnings=1" >>"${CONFIG}"
echo "[ok] ${CONFIG}: disable_splash=1 avoid_warnings=1"

cp -a "${CMDLINE}" "${CMDLINE}.bak.$(date +%s)"
python3 - "${CMDLINE}" "${HARD}" <<'PY'
import sys
path, hard = sys.argv[1], sys.argv[2] == "1"
tokens = open(path).read().strip().split()

# Always strip Plymouth splash tokens and our previous hard flags
drop_exact = {
    "splash", "nosplash", "plymouth.ignore-serial-consoles",
    "fbcon=map:99", "fbcon=logo-count:0",
}
kept = []
for t in tokens:
    if t in drop_exact:
        continue
    if t.startswith("fbcon="):
        continue
    if hard and t.startswith("console="):
        val = t.split("=", 1)[1]
        # In hard mode drop VT consoles (tty1/tty3); keep serial*
        if val.startswith("tty") and not val.startswith(("ttyS", "ttyAMA")) and "serial" not in val:
            continue
    kept.append(t)

# Soft quiet flags (no fbcon=map:99)
for need in (
    "quiet",
    "loglevel=3",  # softer than 0 — still hides most spam
    "logo.nologo",
    "vt.global_cursor_default=0",
    "consoleblank=0",
    "systemd.show_status=false",
):
    key = need.split("=")[0]
    kept = [t for t in kept if t != key and not t.startswith(key + "=")]
    kept.append(need)

# Prefer console=tty3 over tty1 so early text is less visible, but keep a VT
has_vt = any(
    t.startswith("console=tty") and not t.startswith(("console=ttyS", "console=ttyAMA"))
    for t in kept
)
if not hard:
    if any(t == "console=tty1" or t.startswith("console=tty1,") for t in kept):
        kept = ["console=tty3" if t.startswith("console=tty1") else t for t in kept]
    elif not has_vt:
        kept.append("console=tty3")
else:
    if not any(t.startswith("console=") for t in kept):
        kept.append("console=serial0,115200")

open(path, "w").write(" ".join(kept) + "\n")
print("[ok] cmdline rewritten")
print(open(path).read())
PY

for svc in plymouth-start plymouth-read-write plymouth-quit plymouth-quit-wait \
           plymouth-reboot plymouth-halt plymouth-kexec; do
  systemctl disable "${svc}" 2>/dev/null || true
  systemctl mask "${svc}" 2>/dev/null || true
done
systemctl disable getty@tty1 2>/dev/null || true
systemctl mask getty@tty1 2>/dev/null || true
echo "[ok] Plymouth + getty@tty1 masked"

if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_boot_splash 1 2>/dev/null || true
fi

mkdir -p /etc/cloud
touch /etc/cloud/cloud-init.disabled
for svc in cloud-init cloud-init-local cloud-config cloud-final \
           cloud-init-main.service cloud-init-network.service; do
  systemctl disable "${svc}" 2>/dev/null || true
  systemctl mask "${svc}" 2>/dev/null || true
done

mkdir -p /etc/sysctl.d
cat >/etc/sysctl.d/20-quiet-console.conf <<'EOF'
kernel.printk = 3 4 1 3
EOF

# Early blank — safe oneshot (does not unbind all vtcon forever at boot script time)
cat >/etc/systemd/system/dot-blank-hdmi.service <<'EOF'
[Unit]
Description=Blank HDMI framebuffer before Dot logo
DefaultDependencies=no
After=local-fs.target
Before=dot-display.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'if [ -e /dev/fb0 ]; then dd if=/dev/zero of=/dev/fb0 bs=1024 count=4096 status=none 2>/dev/null || true; fi'

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable dot-blank-hdmi.service
echo "[ok] dot-blank-hdmi.service enabled"

# Do NOT run update-initramfs here — slow on Zero 2W and risky mid-session.

echo ""
echo "Reboot: sudo reboot"
echo "If you need max silence later: DOT_HARD_SILENCE=1 sudo bash scripts/disable-splash.sh"
