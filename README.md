# dotapp — Dot electronic logo

Round **480×480 @ 60 Hz** display driven by **Raspberry Pi Zero 2W** via **UEDX6911-HDMI V2.0**, controlled from an **iPhone** app over Wi‑Fi.

## Architecture

- **Pi firmware** (`firmware/`): FastAPI server + Pygame HDMI renderer with circular mask
- **iOS app** (`ios/Dot/`): SwiftUI gallery, upload, apply to display
- **Assets** (`assets/`): Built-in roundel animations and emoji placeholders

## Quick start (Raspberry Pi)

```bash
# 1. Append docs/config.txt.example to /boot/firmware/config.txt and reboot
# 2. Wire Pi mini-HDMI → UEDX6911 HDMI, USB OTG → board USB-C (see docs/wiring.md)
# 3. Install firmware
sudo bash scripts/install-pi.sh mercy119 desktop
# 4. One-time Wi-Fi: Pi will join your iPhone Personal Hotspot (keeps phone internet)
sudo bash scripts/install-wifi-provision.sh
sudo bash scripts/enter-setup-ap.sh
```

After setup AP is up, on iPhone join `Dot-Setup-XXXX`, open `http://192.168.4.1/setup/`, enter hotspot name/password.

Day-to-day in the car: enable **Personal Hotspot** on iPhone → Pi joins automatically → use the app with the Pi LAN IP (`GET /api/wifi/status`).

Legacy always-on Pi AP (phone loses internet): `sudo bash scripts/setup-wifi-ap.sh`

After boot:

- Display shows gallery animation
- Switch logo: `show anim3` (also `show list`, `show status`)
- API status: `http://<pi-ip>:8080/api/status`
- Wi-Fi help: [docs/wifi-provision.md](docs/wifi-provision.md)

## Quick start (iOS)

See [ios/README.md](ios/README.md). Enable Personal Hotspot, wait for the Pi to join, open the app, pick a logo, tap **Apply to Display**.

## API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/status` | Device status |
| GET | `/api/gallery` | Media list |
| POST | `/api/upload` | Upload PNG/GIF/JPG |
| POST | `/api/display` | `{"media_id":"..."}` |
| DELETE | `/api/media/{id}` | Delete user media |
| GET | `/api/preview/{id}` | Thumbnail |
| GET | `/api/wifi/status` | Wi-Fi mode / Pi IP |
| POST | `/api/wifi/configure` | Save phone hotspot and switch |

## Development (off-Pi)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r firmware/requirements.txt
python3 scripts/generate_assets.py
PYTHONPATH=. uvicorn firmware.main:app --reload --port 8080
```

## Kiosk boot (logo only, no desktop)

```bash
sudo bash scripts/setup-kiosk-boot.sh YOUR_USERNAME
sudo reboot
```

See [docs/kiosk-boot.md](docs/kiosk-boot.md).

## Docs

- [Wiring & HDMI setup](docs/wiring.md)
- [config.txt example](docs/config.txt.example)
- [Wi-Fi / iPhone hotspot](docs/wifi-provision.md)
- [Kiosk boot](docs/kiosk-boot.md)
- [Car power & mounting](docs/car-power.md)
