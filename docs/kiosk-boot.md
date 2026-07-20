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
2. ~20–40 s (Pi Zero 2W) — mostly black screen
3. Dot logo animation on the round display

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
