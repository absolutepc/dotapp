#!/usr/bin/env python3
"""Generate stylized round 480x480 BMW-inspired assets and emoji (not official trademarks)."""

from __future__ import annotations

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BMW_DIR = ROOT / "assets" / "bmw"
EMOJI_DIR = ROOT / "assets" / "emoji"
META_FILE = ROOT / "assets" / "catalog.json"
SIZE = 480

# BMW-inspired palette (stylized, for personal projects)
BLACK = "#0a0a0a"
RING = "#111111"
BMW_BLUE = "#1C69D4"
BMW_BLUE_DARK = "#0653B6"
WHITE = "#F4F6F8"
SILVER = "#B8C4CE"
M_BLUE = "#00A3E0"
M_RED = "#E7222E"
M_NAVY = "#003B7A"
CHROME = "#D9DEE3"


def circle_mask(size: int = SIZE) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, size - 1, size - 1), fill=255)
    return mask


def apply_mask(img: Image.Image) -> Image.Image:
    bg = Image.new("RGBA", img.size, (0, 0, 0, 255))
    out = img.copy()
    out.putalpha(circle_mask())
    return Image.alpha_composite(bg, out)


def _font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    try:
        return ImageFont.truetype(f"/usr/share/fonts/truetype/dejavu/{name}", size)
    except OSError:
        return ImageFont.load_default()


def draw_roundel(
    *,
    rotation: float = 0,
    ring_color: str = RING,
    left_color: str = BMW_BLUE,
    right_color: str = WHITE,
    highlight: float = 0.0,
    m_stripe: bool = False,
    inner_gloss: bool = True,
) -> Image.Image:
    """Classic propeller-style roundel: blue/white quadrants + black ring."""
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    cx = cy = SIZE // 2
    outer_r = SIZE // 2 - 6
    ring_w = 28
    inner_r = outer_r - ring_w

    # Outer ring
    draw.ellipse((cx - outer_r, cy - outer_r, cx + outer_r, cy + outer_r), fill=ring_color)

    # Inner disc base
    draw.ellipse((cx - inner_r, cy - inner_r, cx + inner_r, cy + inner_r), fill=left_color)

    # White quadrants (top-right + bottom-left) — propeller look
    quad = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    qd = ImageDraw.Draw(quad)
    qd.pieslice((cx - inner_r, cy - inner_r, cx + inner_r, cy + inner_r), 0, 90, fill=right_color)
    qd.pieslice((cx - inner_r, cy - inner_r, cx + inner_r, cy + inner_r), 180, 270, fill=right_color)
    layer = Image.alpha_composite(layer, quad)

    if m_stripe:
        stripe = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        sd = ImageDraw.Draw(stripe)
        band_h = max(14, inner_r // 8)
        y0 = cy - band_h * 2
        sd.rectangle((cx - inner_r + 8, y0, cx + inner_r - 8, y0 + band_h), fill=M_BLUE)
        sd.rectangle((cx - inner_r + 8, y0 + band_h, cx + inner_r - 8, y0 + band_h * 2), fill=M_RED)
        sd.rectangle((cx - inner_r + 8, y0 + band_h * 2, cx + inner_r - 8, y0 + band_h * 3), fill=M_NAVY)
        layer = Image.alpha_composite(layer, stripe)

    if inner_gloss:
        gloss = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        gd = ImageDraw.Draw(gloss)
        gd.ellipse((cx - inner_r + 20, cy - inner_r + 12, cx + inner_r - 60, cy - 20), fill=(255, 255, 255, 45))
        layer = Image.alpha_composite(layer, gloss)

    if highlight > 0:
        hi = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        hd = ImageDraw.Draw(hi)
        angle = highlight * math.pi / 180
        x = cx + int(math.cos(angle) * inner_r * 0.55)
        y = cy + int(math.sin(angle) * inner_r * 0.55)
        hd.ellipse((x - 40, y - 40, x + 40, y + 40), fill=(255, 255, 255, 90))
        layer = Image.alpha_composite(layer, hi)

    if rotation:
        layer = layer.rotate(rotation, resample=Image.Resampling.BICUBIC, center=(cx, cy))

    img = Image.alpha_composite(img, layer)
    return apply_mask(img)


def draw_chrome_roundel() -> Image.Image:
    base = draw_roundel(ring_color=CHROME, left_color=BMW_BLUE_DARK, right_color=WHITE, inner_gloss=True)
    return base.filter(ImageFilter.UnsharpMask(radius=1, percent=130, threshold=2))


def draw_minimal_m() -> Image.Image:
    img = draw_roundel(left_color=BMW_BLUE, right_color=WHITE, m_stripe=False)
    draw = ImageDraw.Draw(img)
    font = _font(72, bold=True)
    text = "M"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text((SIZE // 2 - tw // 2, SIZE // 2 - th // 2 - 6), text, fill=WHITE, font=font)
    return img


def save_gif(frames: list[Image.Image], path: Path, duration_ms: int) -> None:
    rgb = [f.convert("RGB") for f in frames]
    rgb[0].save(path, save_all=True, append_images=rgb[1:], duration=duration_ms, loop=0, optimize=True)


def anim_pulse(frames: int = 40) -> list[Image.Image]:
    seq = []
    for i in range(frames):
        glow = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(2 * math.pi * i / frames))
        scale = 0.94 + 0.06 * glow
        base = draw_roundel(highlight=i * 9, inner_gloss=True)
        w = int(SIZE * scale)
        scaled = base.resize((w, w), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
        canvas.paste(scaled, ((SIZE - w) // 2, (SIZE - w) // 2), scaled)
        seq.append(apply_mask(canvas))
    return seq


def anim_spin(frames: int = 48) -> list[Image.Image]:
    return [draw_roundel(rotation=i * (360 / frames)) for i in range(frames)]


def anim_shimmer(frames: int = 36) -> list[Image.Image]:
    return [draw_roundel(highlight=i * (360 / frames), inner_gloss=True) for i in range(frames)]


def anim_m_stripe(frames: int = 30) -> list[Image.Image]:
    seq = []
    for i in range(frames):
        img = draw_roundel(m_stripe=True, highlight=0)
        draw = ImageDraw.Draw(img)
        offset = int((i / frames) * 120 - 60)
        band_h = 16
        y0 = SIZE // 2 - 24 + offset
        draw.rectangle((100, y0, 380, y0 + band_h), fill=(0, 163, 224, 180))
        draw.rectangle((100, y0 + band_h, 380, y0 + band_h * 2), fill=(231, 34, 46, 180))
        draw.rectangle((100, y0 + band_h * 2, 380, y0 + band_h * 3), fill=(0, 59, 122, 180))
        seq.append(img)
    return seq


def anim_breathe_blue(frames: int = 32) -> list[Image.Image]:
    seq = []
    for i in range(frames):
        t = 0.5 + 0.5 * math.sin(2 * math.pi * i / frames)
        blue = int(28 + t * 40)
        color = f"#{blue:02x}{int(105 + t * 50):02x}{int(180 + t * 40):02x}"
        seq.append(draw_roundel(left_color=color, right_color=WHITE))
    return seq


def anim_ring_pulse(frames: int = 24) -> list[Image.Image]:
    seq = []
    for i in range(frames):
        t = 0.5 + 0.5 * math.sin(2 * math.pi * i / frames)
        ring = f"#{int(30 + t * 140):02x}{int(30 + t * 140):02x}{int(30 + t * 140):02x}"
        seq.append(draw_roundel(ring_color=ring))
    return seq


def draw_emoji_face(base_color: str, *, smile: float = 0.5, wink: bool = False) -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse((70, 70, 410, 410), fill=base_color)
    draw.ellipse((70, 70, 410, 410), outline=(255, 255, 255, 80), width=4)
    # Eyes
    draw.ellipse((155, 175, 215, 235), fill=WHITE)
    draw.ellipse((265, 175, 325, 235), fill=WHITE)
    if wink:
        draw.line((155, 205, 215, 205), fill=BLACK, width=10)
    else:
        draw.ellipse((172, 192, 198, 218), fill=BLACK)
    draw.ellipse((282, 192, 308, 218), fill=BLACK)
    # Smile arc
    arc_y = int(250 + smile * 40)
    draw.arc((150, arc_y, 330, arc_y + 120), 15, 165, fill=BLACK, width=10)
    return apply_mask(img)


def anim_emoji_bounce(color: str, frames: int = 16) -> list[Image.Image]:
    seq = []
    for i in range(frames):
        bounce = abs(math.sin(math.pi * i / (frames - 1)))
        offset = int(bounce * 18)
        face = draw_emoji_face(color, smile=0.4 + bounce * 0.3)
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
        canvas.paste(face, (0, offset), face)
        seq.append(canvas)
    return seq


def write_catalog(entries: list[dict]) -> None:
    META_FILE.write_text(json.dumps(entries, indent=2, ensure_ascii=False), encoding="utf-8")


def main() -> None:
    BMW_DIR.mkdir(parents=True, exist_ok=True)
    EMOJI_DIR.mkdir(parents=True, exist_ok=True)
    for folder in (BMW_DIR, EMOJI_DIR):
        for old in folder.glob("*"):
            if old.suffix.lower() in {".png", ".gif"}:
                old.unlink()
    catalog: list[dict] = []

    # --- BMW static ---
    static_bmw = [
        ("default", "Classic Roundel", draw_roundel()),
        ("classic-roundel", "Blue Roundel", draw_roundel(left_color=BMW_BLUE, right_color=WHITE)),
        ("chrome-roundel", "Chrome Roundel", draw_chrome_roundel()),
        ("m-sport", "M Sport", draw_roundel(m_stripe=True)),
        ("minimal-m", "M Badge", draw_minimal_m()),
        ("midnight", "Midnight", draw_roundel(ring_color=BLACK, left_color=BMW_BLUE_DARK, right_color="#2a3540")),
        ("alpine", "Alpine White", draw_roundel(ring_color=SILVER, left_color=BMW_BLUE, right_color=WHITE)),
        ("motorsport", "Motorsport", draw_roundel(m_stripe=True, ring_color=BLACK, left_color=M_NAVY)),
    ]
    for stem, title, image in static_bmw:
        image.save(BMW_DIR / f"{stem}.png")
        catalog.append({"id": f"builtin-bmw-{stem}", "name": title, "category": "bmw", "type": "image", "file": f"bmw/{stem}.png"})

    # --- BMW animations ---
    animations_bmw = [
        ("pulse", "Pulse Glow", anim_pulse(), 42),
        ("spin", "Slow Spin", anim_spin(), 50),
        ("shimmer", "Shimmer", anim_shimmer(), 45),
        ("m-stripe-flow", "M Stripe Flow", anim_m_stripe(), 55),
        ("breathe-blue", "Blue Breathe", anim_breathe_blue(), 48),
        ("ring-pulse", "Ring Pulse", anim_ring_pulse(), 60),
    ]
    for stem, title, frames, duration in animations_bmw:
        save_gif(frames, BMW_DIR / f"{stem}.gif", duration)
        catalog.append({"id": f"builtin-bmw-{stem}", "name": title, "category": "bmw", "type": "animation", "file": f"bmw/{stem}.gif"})

    # --- Emoji static ---
    emoji_static = [
        ("smile", "Smile", "#FFD93D", {}),
        ("cool", "Cool", "#6BCB77", {}),
        ("heart-eyes", "Heart Eyes", "#FF8FAB", {}),
        ("star", "Star", "#4D96FF", {}),
        ("fire", "Fire", "#FF6B35", {}),
        ("party", "Party", "#C77DFF", {"smile": 0.8}),
    ]
    for stem, title, color, kwargs in emoji_static:
        draw_emoji_face(color, **kwargs).save(EMOJI_DIR / f"{stem}.png")
        catalog.append({"id": f"builtin-emoji-{stem}", "name": title, "category": "emoji", "type": "image", "file": f"emoji/{stem}.png"})

    # --- Emoji animations ---
    emoji_anim = [
        ("wink", "Wink", "#FFD93D", 220),
        ("bounce", "Bounce", "#6BCB77", 70),
        ("laugh", "Laugh", "#FFB703", 65),
    ]
    for stem, title, color, duration in emoji_anim:
        if stem == "wink":
            frames = []
            for wink in (False, True, True, False, False):
                frames.append(draw_emoji_face(color, wink=wink))
        elif stem == "laugh":
            frames = [draw_emoji_face(color, smile=0.7 + 0.2 * (i % 2)) for i in range(8)]
        else:
            frames = anim_emoji_bounce(color)
        save_gif(frames, EMOJI_DIR / f"{stem}.gif", duration)
        catalog.append({"id": f"builtin-emoji-{stem}", "name": title, "category": "emoji", "type": "animation", "file": f"emoji/{stem}.gif"})

    write_catalog(catalog)
    print(f"Generated {len(catalog)} assets")
    print(f"  BMW:   {len(list(BMW_DIR.glob('*')))} files -> {BMW_DIR}")
    print(f"  Emoji: {len(list(EMOJI_DIR.glob('*')))} files -> {EMOJI_DIR}")
    print(f"  Catalog: {META_FILE}")


if __name__ == "__main__":
    main()
