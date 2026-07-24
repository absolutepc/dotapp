"""Dot power-on splash — short branded intro before the selected logo plays.

Designed for the round 480×480 panel: one composition, brand-first, 2–3 motions,
deep space-blue (matches app theme), no clutter.
"""

from __future__ import annotations

import math
import os
import time

import pygame

from firmware.config import DISPLAY_HEIGHT, DISPLAY_WIDTH

# Soft navy / ice — aligned with ios DotTheme (not purple/cream AI defaults)
_VOID = (4, 8, 18)
_DEEP = (10, 22, 48)
_ICE = (120, 200, 255)
_HORIZON = (40, 120, 210)
_WHITE = (236, 244, 255)


def boot_splash_enabled() -> bool:
    raw = os.environ.get("DOT_BOOT_SPLASH", "1").strip().lower()
    return raw not in {"0", "false", "no", "off"}


def play_power_on_splash(
    screen: pygame.Surface,
    *,
    duration_s: float = 3.2,
    fps: int = 30,
) -> None:
    """Animate a compact Dot power-on sequence, then return (caller shows media)."""
    if not boot_splash_enabled():
        screen.fill((0, 0, 0))
        pygame.display.flip()
        return

    clock = pygame.time.Clock()
    cx, cy = DISPLAY_WIDTH // 2, DISPLAY_HEIGHT // 2
    font_lg = _font(72)
    font_sm = _font(22)
    t0 = time.monotonic()
    print(f"power-on splash ({duration_s:.1f}s)", flush=True)

    while True:
        now = time.monotonic()
        t = now - t0
        if t >= duration_s:
            break

        # Ignore quit during splash — kiosk must stay up
        for event in pygame.event.get():
            if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                return

        p = min(1.0, t / duration_s)
        # Phases: fade void → ring expand → wordmark → hold → soft fade to black
        ring = _ease_out_cubic(min(1.0, t / 1.1))
        mark = _ease_out_cubic(max(0.0, min(1.0, (t - 0.55) / 0.7)))
        pulse = 0.5 + 0.5 * math.sin(t * 3.2)
        fade_out = _ease_in_cubic(max(0.0, min(1.0, (t - (duration_s - 0.55)) / 0.55)))

        # Background atmosphere (subtle radial feel via layered circles)
        screen.fill(_VOID)
        glow_r = int(90 + 40 * pulse)
        glow = pygame.Surface((DISPLAY_WIDTH, DISPLAY_HEIGHT), pygame.SRCALPHA)
        for i, alpha in ((glow_r + 80, 18), (glow_r + 40, 28), (glow_r, 40)):
            pygame.draw.circle(glow, (*_DEEP, alpha), (cx, cy), i)
        screen.blit(glow, (0, 0))

        # Expanding ice ring (primary motion)
        r1 = int(40 + 160 * ring)
        w1 = max(2, int(8 - 4 * ring))
        col1 = (*_ICE, int(220 * (1.0 - 0.35 * fade_out)))
        ring_surf = pygame.Surface((DISPLAY_WIDTH, DISPLAY_HEIGHT), pygame.SRCALPHA)
        pygame.draw.circle(ring_surf, col1, (cx, cy), r1, w1)
        # Second slower ring
        r2 = int(20 + 200 * _ease_out_cubic(min(1.0, t / 1.6)))
        pygame.draw.circle(ring_surf, (*_HORIZON, int(120 * mark)), (cx, cy), r2, 2)
        screen.blit(ring_surf, (0, 0))

        # Brand wordmark
        if mark > 0.01:
            label = font_lg.render("DOT", True, _WHITE)
            label.set_alpha(int(255 * mark * (1.0 - fade_out)))
            lr = label.get_rect(center=(cx, cy - 8))
            screen.blit(label, lr)
            sub = font_sm.render("electronic logo", True, _ICE)
            sub.set_alpha(int(200 * mark * (1.0 - fade_out)))
            sr = sub.get_rect(center=(cx, cy + 42))
            screen.blit(sub, sr)

        # Outer round safe-frame (hints the physical circle)
        rim = pygame.Surface((DISPLAY_WIDTH, DISPLAY_HEIGHT), pygame.SRCALPHA)
        pygame.draw.circle(rim, (*_ICE, 40), (cx, cy), min(cx, cy) - 3, 2)
        screen.blit(rim, (0, 0))

        if fade_out > 0:
            veil = pygame.Surface((DISPLAY_WIDTH, DISPLAY_HEIGHT), pygame.SRCALPHA)
            veil.fill((0, 0, 0, int(255 * fade_out)))
            screen.blit(veil, (0, 0))

        pygame.display.flip()
        clock.tick(fps)

    screen.fill((0, 0, 0))
    pygame.display.flip()
    print("power-on splash done", flush=True)


def _font(size: int) -> pygame.font.Font:
    try:
        pygame.font.init()
    except pygame.error:
        pass
    # Prefer a clean geometric face when present; fall back to default.
    for name in (
        "DejaVuSans-Bold.ttf",
        "DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ):
        try:
            return pygame.font.Font(name, size)
        except (FileNotFoundError, OSError, pygame.error):
            continue
    return pygame.font.Font(None, size)


def _ease_out_cubic(x: float) -> float:
    return 1.0 - (1.0 - x) ** 3


def _ease_in_cubic(x: float) -> float:
    return x ** 3
