"""Circular alpha mask for round 480x480 display."""

from __future__ import annotations

from PIL import Image, ImageDraw

from firmware.config import DISPLAY_HEIGHT, DISPLAY_WIDTH


def create_circle_mask(size: tuple[int, int] | None = None) -> Image.Image:
    width, height = size or (DISPLAY_WIDTH, DISPLAY_HEIGHT)
    mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, width - 1, height - 1), fill=255)
    return mask


def apply_circle_mask(frame: Image.Image, mask: Image.Image | None = None) -> Image.Image:
    """Apply circular mask; areas outside circle are black."""
    if frame.mode != "RGBA":
        frame = frame.convert("RGBA")

    circle_mask = mask or create_circle_mask(frame.size)
    if circle_mask.size != frame.size:
        circle_mask = circle_mask.resize(frame.size, Image.Resampling.LANCZOS)

    background = Image.new("RGBA", frame.size, (0, 0, 0, 255))
    frame.putalpha(circle_mask)
    return Image.alpha_composite(background, frame)
