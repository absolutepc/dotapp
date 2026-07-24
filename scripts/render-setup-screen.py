#!/usr/bin/env python3
"""Render a 480×480 setup-info frame for the round HDMI (SSID, password, portal, QR).

Usage:
  python3 scripts/render-setup-screen.py --ssid Dot-Setup-Pi --password dotsetup1 \\
      --ip 192.168.4.1 --frames-dir /var/lib/dot/frames
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def _draw_qr(draw, box: tuple[int, int, int, int], data: str) -> None:
    """Draw a QR into `box` using qrcode if available, else a text fallback."""
    x0, y0, x1, y1 = box
    size = min(x1 - x0, y1 - y0)
    try:
        import qrcode

        qr = qrcode.QRCode(border=1, box_size=4)
        qr.add_data(data)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white").convert("RGB")
        img = img.resize((size, size))
        # Caller pastes — return via side channel
        _draw_qr.last = img  # type: ignore[attr-defined]
        return
    except Exception:
        _draw_qr.last = None  # type: ignore[attr-defined]
        draw.rectangle(box, outline=(220, 220, 220), width=2)
        draw.text((x0 + 8, y0 + size // 2 - 8), "open app", fill=(200, 200, 200))


def render(ssid: str, password: str, ip: str, out_dir: Path) -> Path:
    from PIL import Image, ImageDraw, ImageFont

    out_dir.mkdir(parents=True, exist_ok=True)
    # Clear legacy frames
    for old in out_dir.glob("*.*"):
        if old.name == "meta.json":
            continue
        old.unlink()

    img = Image.new("RGB", (480, 480), (12, 14, 18))
    draw = ImageDraw.Draw(img)
    try:
        font_lg = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 28)
        font_md = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
        font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    except OSError:
        font_lg = font_md = font_sm = ImageFont.load_default()

    draw.ellipse((8, 8, 472, 472), outline=(60, 90, 120), width=3)

    draw.text((40, 36), "Dot Setup", fill=(255, 255, 255), font=font_lg)
    draw.text((40, 78), "Подключите iPhone к Wi‑Fi", fill=(180, 190, 200), font=font_sm)

    draw.text((40, 120), "Сеть", fill=(140, 150, 160), font=font_sm)
    draw.text((40, 140), ssid[:28], fill=(255, 255, 255), font=font_md)

    draw.text((40, 180), "Пароль", fill=(140, 150, 160), font=font_sm)
    draw.text((40, 200), password, fill=(255, 220, 120), font=font_md)

    portal = f"http://{ip}/setup/"
    draw.text((40, 250), "Приложение или Safari", fill=(140, 150, 160), font=font_sm)
    draw.text((40, 270), portal, fill=(160, 200, 255), font=font_sm)

    qr_box = (300, 300, 440, 440)
    _draw_qr(draw, qr_box, portal)
    qr_img = getattr(_draw_qr, "last", None)
    if qr_img is not None:
        img.paste(qr_img, (300, 300))
    else:
        draw.rectangle(qr_box, outline=(100, 110, 120), width=2)
        draw.text((310, 360), ip, fill=(200, 200, 200), font=font_sm)

    draw.text((40, 420), "Затем: Режим модема → Dot", fill=(150, 160, 170), font=font_sm)

    frame = out_dir / "0000.jpg"
    img.save(frame, quality=90, optimize=True)
    meta = {
        "durations": [3600.0],
        "frame_count": 1,
        "fps": 1.0,
        "source_suffix": ".jpg",
        "cache_version": 7,
    }
    (out_dir / "meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return frame


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ssid", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--ip", default="192.168.4.1")
    parser.add_argument("--frames-dir", required=True, type=Path)
    parser.add_argument("--media-id", default="setup-info")
    args = parser.parse_args()

    dest = args.frames_dir / args.media_id
    path = render(args.ssid, args.password, args.ip, dest)
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
