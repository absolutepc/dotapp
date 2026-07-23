"""Circular mask + black treatment for round 480x480 display.

IPS panels lift near-black to blue-grey, and soft ellipse AA leaves a glowing
fringe against the physical bezel. We inset a hard circle and crush near-black
pixels to true RGB(0,0,0) so the rim matches the frame better.
"""

from __future__ import annotations

from PIL import Image, ImageDraw

from firmware.config import DISPLAY_HEIGHT, DISPLAY_WIDTH

# Leave a pure-black ring at the edge (physical bezel blend).
MASK_INSET_PX = 5
# Channels at or below this become absolute black (crush raised IPS “blacks”).
BLACK_CRUSH_THRESHOLD = 22


def create_circle_mask(size: tuple[int, int] | None = None, inset: int = MASK_INSET_PX) -> Image.Image:
    """Hard circular mask inset from the frame edge (no soft AA halo)."""
    width, height = size or (DISPLAY_WIDTH, DISPLAY_HEIGHT)
    mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask)
    # Slightly inset so the outermost pixels stay pure black after composite.
    pad = max(0, int(inset))
    # Use integer box; avoid AA by not using ImageDraw antialias (default is hard).
    draw.ellipse((pad, pad, width - 1 - pad, height - 1 - pad), fill=255)
    return mask


def crush_blacks(frame: Image.Image, threshold: int = BLACK_CRUSH_THRESHOLD) -> Image.Image:
    """Force near-black pixels to true black (helps IPS glow vs bezel)."""
    thr = max(0, min(255, int(threshold)))
    if thr <= 0:
        return frame
    rgb = frame.convert("RGB")
    # Point ops are fast enough for 480×480 on Pi Zero.
    bands = []
    for band in rgb.split():
        bands.append(band.point(lambda p, t=thr: 0 if p <= t else p))
    out = Image.merge("RGB", bands)
    if frame.mode == "RGBA":
        out = out.convert("RGBA")
        out.putalpha(frame.getchannel("A"))
    return out


def apply_circle_mask(frame: Image.Image, mask: Image.Image | None = None) -> Image.Image:
    """Apply circular mask; outside + near-black crush → true black."""
    if frame.mode != "RGBA":
        frame = frame.convert("RGBA")

    circle_mask = mask or create_circle_mask(frame.size)
    if circle_mask.size != frame.size:
        # NEAREST keeps a hard edge (LANCZOS would reintroduce a grey fringe).
        circle_mask = circle_mask.resize(frame.size, Image.Resampling.NEAREST)

    background = Image.new("RGBA", frame.size, (0, 0, 0, 255))
    frame.putalpha(circle_mask)
    composited = Image.alpha_composite(background, frame)
    # Crush after composite so fringe + dark navy fills go to 0,0,0.
    crushed = crush_blacks(composited.convert("RGB"))
    return crushed.convert("RGBA")
