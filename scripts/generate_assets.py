#!/usr/bin/env python3
"""Generate placeholder round 480x480 assets (no trademarked logos)."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BMW_DIR = ROOT / "assets" / "bmw"
EMOJI_DIR = ROOT / "assets" / "emoji"
SIZE = 480


def circle_mask(size: int = SIZE) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, size - 1, size - 1), fill=255)
    return mask


def apply_mask(img: Image.Image) -> Image.Image:
    bg = Image.new("RGBA", img.size, (0, 0, 0, 255))
    img.putalpha(circle_mask())
    return Image.alpha_composite(bg, img)


def draw_roundel(name: str, outer: str, inner: str, accent: str | None = None) -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy, r = SIZE // 2, SIZE // 2, SIZE // 2 - 8

    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=outer)
    draw.ellipse((cx - r + 36, cy - r + 36, cx + r - 36, cy + r - 36), fill=inner)
    if accent:
        draw.ellipse((cx - 50, cy - 50, cx + 50, cy + 50), fill=accent)

    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 52)
    except OSError:
        font = ImageFont.load_default()

    bbox = draw.textbbox((0, 0), name, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text((cx - tw // 2, cy - th // 2), name, fill="white", font=font)
    return apply_mask(img)


def save_gif_pulse(path: Path, base: Image.Image, frames: int = 30) -> None:
    seq = []
    for i in range(frames):
        scale = 0.92 + 0.08 * (0.5 + 0.5 * math.sin(2 * math.pi * i / frames))
        w = int(SIZE * scale)
        frame = base.resize((w, w), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
        canvas.paste(frame, ((SIZE - w) // 2, (SIZE - w) // 2), frame)
        seq.append(canvas.convert("RGB"))
    seq[0].save(path, save_all=True, append_images=seq[1:], duration=33, loop=0)


def save_gif_spin(path: Path, base: Image.Image, frames: int = 36) -> None:
    seq = []
    for i in range(frames):
        rotated = base.rotate(i * (360 / frames), resample=Image.Resampling.BICUBIC, expand=False)
        seq.append(rotated.convert("RGB"))
    seq[0].save(path, save_all=True, append_images=seq[1:], duration=28, loop=0)


def draw_emoji(label: str, color: str) -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = SIZE // 2, SIZE // 2
    draw.ellipse((60, 60, 420, 420), fill=color)
    draw.ellipse((150, 170, 210, 230), fill="white")
    draw.ellipse((270, 170, 330, 230), fill="white")
    draw.ellipse((165, 185, 195, 215), fill="black")
    draw.ellipse((285, 185, 315, 215), fill="black")
    draw.arc((140, 220, 340, 380), 20, 160, fill="black", width=8)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 28)
        draw.text((cx - 20, 400), label, fill="white", font=font, anchor="mm")
    except OSError:
        pass
    return apply_mask(img)


def main() -> None:
    BMW_DIR.mkdir(parents=True, exist_ok=True)
    EMOJI_DIR.mkdir(parents=True, exist_ok=True)

    classic = draw_roundel("M", "#0066B1", "#1a1a1a")
    classic.save(BMW_DIR / "default.png")
    classic.save(BMW_DIR / "classic-roundel.png")

    m_perf = draw_roundel("M", "#005A34", "#0066B1", "#003DA5")
    m_perf.save(BMW_DIR / "m-sport.png")
    save_gif_pulse(BMW_DIR / "pulse.gif", classic)
    save_gif_spin(BMW_DIR / "spin.gif", draw_roundel("", "#0066B1", "#1a1a1a"))

    emojis = [
        ("smile", "#FFD93D"),
        ("cool", "#6BCB77"),
        ("heart", "#FF6B6B"),
        ("star", "#4D96FF"),
        ("fire", "#FF8C42"),
    ]
    for name, color in emojis:
        draw_emoji(name[:1].upper(), color).save(EMOJI_DIR / f"{name}.png")

    wink = draw_emoji("W", "#C77DFF")
    frames = []
    for open_eye in (True, False, True, True):
        frame = wink.copy()
        if not open_eye:
            draw = ImageDraw.Draw(frame)
            draw.line((150, 200, 210, 200), fill="black", width=8)
        frames.append(frame.convert("RGB"))
    frames[0].save(EMOJI_DIR / "wink.gif", save_all=True, append_images=frames[1:], duration=200, loop=0)

    print(f"Generated assets in {BMW_DIR} and {EMOJI_DIR}")


if __name__ == "__main__":
    main()
