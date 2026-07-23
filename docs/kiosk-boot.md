# Kiosk boot — logo only, no desktop

Boot the Pi directly into the Dot logo renderer without the Raspberry Pi splash screen and without the desktop environment.

## Quick setup

```bash
cd ~/dotapp   # or /opt/dot
sudo bash scripts/setup-kiosk-boot.sh mercy119
sudo reboot
```

Replace `mercy119` with your Pi username.

## What the script does

1. Adds `disable_splash=1` to `config.txt` (hides rainbow / early logos)
2. Removes `splash` from `cmdline.txt` (disables Plymouth “Welcome to Raspberry Pi”)
3. Adds quiet boot flags (`quiet`, `logo.nologo`, …)
4. Sets default target to `multi-user.target` (no GUI)
5. Disables / masks desktop + Plymouth services
6. Installs kiosk `dot-display.service` (SDL: kmsdrm → fbcon → x11)

## Expected boot sequence

1. Power on  
2. ~20–40 s (Pi Zero 2W) — **black** round panel (no U-Boot / kernel text)  
3. Dot logo animation

## No text on the round display

```bash
cd ~/dotapp
git pull
sudo bash scripts/disable-splash.sh
# or full kiosk re-apply:
sudo bash scripts/setup-kiosk-boot.sh mercy119
sudo reboot
```

What this does:

- `disable_splash=1` / `avoid_warnings=1` in `config.txt`
- Removes `console=tty1` / `tty3` from cmdline (keeps serial only)
- Adds `quiet loglevel=0 logo.nologo fbcon=map:99`
- Tries to silence **U-Boot** (`fw_setenv silent` / `stdout=serial` when available)
- Enables `dot-blank-hdmi.service` to zero the framebuffer before the logo

If white **U-Boot …** lines still appear for a second, your image’s U-Boot was built with HDMI console and needs env silence — check `/boot/firmware/dot-silent-uboot.txt` (or run `fw_setenv` as printed by the script).

## Black screen stuck on `e2fsck … rootfs: clean`

The filesystem is fine. That text is leftover console output because **the logo renderer never took over HDMI**.

SSH in (Personal Hotspot / LAN) and run:

```bash
cd ~/dotapp   # or wherever the repo lives
bash scripts/diagnose-kiosk.sh
```

Typical repair (SDL / pygame with no video drivers):

```bash
cd ~/dotapp
git pull
bash scripts/fix-pygame-display.sh
# Expect at least one "OK auto" or "OK kmsdrm"
show anim3
sudo reboot
```

This recreates the venv with `--system-site-packages` so Debian’s `python3-pygame`
(linked to system SDL + kmsdrm) is used instead of a broken PyPI wheel.

## Black screen still shows `e2fsck` while logs say `kmsdrm`

The kernel **framebuffer console** can keep boot text on HDMI even while SDL
renders via KMSDRM. Latest units unbind `vtconsole` before starting the renderer.

```bash
cd ~/dotapp && git pull
sudo bash scripts/fix-systemd-paths.sh mercy119 kiosk
sudo systemctl restart dot-display
# Leave it alone for 30s — look at the ROUND Dot display (not the SSH PC)
journalctl -u dot-display -f
# expect repeating: heartbeat media=… frames=…
```

Check:

```bash
systemctl is-active dot-api dot-display
journalctl -u dot-display -n 50 --no-pager
```

You want `active` and a log line like `Display driver: kmsdrm` (or `fbcon`).

## If splash still appears

Check that `splash` is **gone** from cmdline:

```bash
cat /boot/firmware/cmdline.txt
# or: cat /boot/cmdline.txt
```

There should be `quiet` and `logo.nologo`, but **not** the word `splash`.

Then re-run:

```bash
sudo bash scripts/setup-kiosk-boot.sh mercy119
sudo reboot
```

Or via raspi-config: `1 System Options → S7 Splash Screen → No`.

## Restore desktop (for debugging)

```bash
sudo systemctl set-default graphical.target
sudo systemctl unmask lightdm getty@tty1 plymouth-start
sudo systemctl enable lightdm
sudo bash scripts/fix-systemd-paths.sh mercy119 desktop
sudo rm -f /etc/cloud/cloud-init.disabled
sudo reboot
```

## Troubleshooting

```bash
sudo journalctl -u dot-display -n 30 --no-pager
systemctl get-default
```

If display fails without desktop, the renderer tries `kmsdrm`, then `fbcon`, then `x11` automatically.
