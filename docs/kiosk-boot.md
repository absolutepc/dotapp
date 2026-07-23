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
2. ~20–40 s (Pi Zero 2W) — mostly black screen (a brief `e2fsck … clean` line can flash and then disappear)
3. Dot logo animation on the round display

## Black screen stuck on `e2fsck … rootfs: clean`

The filesystem is fine. That text is leftover console output because **the logo renderer never took over HDMI**.

SSH in (Personal Hotspot / LAN) and run:

```bash
cd ~/dotapp   # or wherever the repo lives
bash scripts/diagnose-kiosk.sh
```

Typical repair:

```bash
cd ~/dotapp
git pull
# Rebuild pygame WITH kmsdrm (PyPI wheel has none — this is the usual fix)
bash scripts/fix-pygame-display.sh
show list
show anim3
sudo reboot
```

If `fix-pygame-display.sh` prints `OK kmsdrm` (or `fbcon`) and `dot-display` is `active`, the logo should appear.

Also re-apply kiosk units if needed:

```bash
sudo bash scripts/setup-kiosk-boot.sh mercy119
sudo reboot
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
