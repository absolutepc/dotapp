# dotapp — BMW Electronic Logo

Round **480×480 @ 60 Hz** display driven by **Raspberry Pi Zero 2W** via **UEDX6911-HDMI V2.0**, controlled from an **iPhone** app over Wi‑Fi.

## Architecture

- **Pi firmware** (`firmware/`): FastAPI server + Pygame HDMI renderer with circular mask
- **iOS app** (`ios/BMWLogo/`): SwiftUI gallery, upload, apply to display
- **Assets** (`assets/`): Built-in roundel animations and emoji placeholders

## Quick start (Raspberry Pi)

```bash
# 1. Append docs/config.txt.example to /boot/firmware/config.txt and reboot
# 2. Wire Pi mini-HDMI → UEDX6911 HDMI, USB OTG → board USB-C (see docs/wiring.md)
# 3. Install firmware
sudo bash scripts/install-pi.sh
sudo bash scripts/setup-wifi-ap.sh
sudo reboot
```

After boot:

- Display shows default roundel animation
- API: `http://192.168.4.1:8080/api/status`
- Wi‑Fi AP: `BMW-Logo-XXXX`

## Quick start (iOS)

See [ios/README.md](ios/README.md). Connect iPhone to the Pi AP, open the app, pick a logo, tap **Apply to Display**.

## API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/status` | Device status |
| GET | `/api/gallery` | Media list |
| POST | `/api/upload` | Upload PNG/GIF/JPG |
| POST | `/api/display` | `{"media_id":"..."}` |
| DELETE | `/api/media/{id}` | Delete user media |
| GET | `/api/preview/{id}` | Thumbnail |

## Development (off-Pi)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r firmware/requirements.txt
python3 scripts/generate_assets.py
PYTHONPATH=. uvicorn firmware.main:app --reload --port 8080
```

## Docs

- [Wiring & HDMI setup](docs/wiring.md)
- [config.txt example](docs/config.txt.example)
- [Car power & mounting](docs/car-power.md)
