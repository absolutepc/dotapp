# Kiosk boot — logo only, no desktop

Boot the Pi directly into the BMW logo renderer without the Raspberry Pi splash screen and without the desktop environment.

## Quick setup

```bash
cd ~/dotapp   # or /opt/bmw-logo
sudo bash scripts/setup-kiosk-boot.sh mercy119
sudo reboot
```

Replace `mercy119` with your Pi username.

## What the script does

1. Adds `disable_splash=1` to `config.txt`
2. Adds quiet boot flags to `cmdline.txt`
3. Sets default target to `multi-user.target` (no GUI)
4. Disables `lightdm` / `wayfire` / Plymouth
5. Installs kiosk `bmw-logo-display.service` (auto-picks SDL driver: kmsdrm → fbcon → x11)

## Expected boot sequence

1. Power on
2. ~20–40 s (Pi Zero 2W) — black or minimal text screen
3. BMW logo animation on the round display

## Restore desktop (for debugging)

```bash
sudo systemctl set-default graphical.target
sudo systemctl enable lightdm
sudo cp ~/dotapp/firmware/systemd/bmw-logo-display.service /etc/systemd/system/
sudo sed -i 's/User=pi/User=YOUR_USER/' /etc/systemd/system/bmw-logo-display.service
sudo sed -i 's|/opt/bmw-logo|/home/YOUR_USER/dotapp|' /etc/systemd/system/bmw-logo-display.service
# Add for desktop:
echo 'Environment=DISPLAY=:0' >> /etc/systemd/system/bmw-logo-display.service
echo 'Environment=SDL_VIDEODRIVER=x11' >> /etc/systemd/system/bmw-logo-display.service
sudo systemctl daemon-reload
sudo reboot
```

## Troubleshooting

```bash
sudo journalctl -u bmw-logo-display -n 30 --no-pager
```

If display fails without desktop, the renderer tries `kmsdrm`, then `fbcon`, then `x11` automatically.
