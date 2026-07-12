"""Pygame HDMI fullscreen renderer for round 480x480 @ 60fps."""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import pygame
from PIL import Image

from firmware.config import (
    CURRENT_MEDIA_FILE,
    DISPLAY_HEIGHT,
    DISPLAY_WIDTH,
    FRAMES_DIR,
    TARGET_FPS,
)
from firmware.display.mask import apply_circle_mask, create_circle_mask


def _init_pygame_display() -> pygame.Surface:
    """Try SDL drivers in order: env override, kmsdrm, fbcon, x11."""
    preferred = os.environ.get("SDL_VIDEODRIVER")
    drivers = [preferred] if preferred else []
    for driver in ("kmsdrm", "fbcon", "x11"):
        if driver not in drivers:
            drivers.append(driver)

    last_error: Exception | None = None
    for driver in drivers:
        if not driver:
            continue
        os.environ["SDL_VIDEODRIVER"] = driver
        pygame.display.quit()
        pygame.quit()
        try:
            pygame.init()
            pygame.display.init()
            screen = pygame.display.set_mode(
                (DISPLAY_WIDTH, DISPLAY_HEIGHT),
                pygame.FULLSCREEN,
            )
            print(f"Display driver: {driver}")
            return screen
        except pygame.error as exc:
            last_error = exc
            print(f"Driver {driver} failed: {exc}")

    raise RuntimeError(f"No SDL display driver available: {last_error}")


class HDMIRenderer:
    def __init__(self) -> None:
        self._screen = _init_pygame_display()
        pygame.display.set_caption("BMW Logo")
        pygame.mouse.set_visible(False)

        self._clock = pygame.time.Clock()
        self._mask = create_circle_mask()
        self._running = True
        self._current_media_id: str | None = None
        self._frame_paths: list[Path] = []
        self._frame_index = 0
        self._frame_durations: list[float] = []
        self._last_manifest_mtime = 0.0

    def _load_state(self) -> None:
        if not CURRENT_MEDIA_FILE.exists():
            return

        mtime = CURRENT_MEDIA_FILE.stat().st_mtime
        if mtime <= self._last_manifest_mtime:
            return

        self._last_manifest_mtime = mtime
        data = json.loads(CURRENT_MEDIA_FILE.read_text(encoding="utf-8"))
        media_id = data.get("media_id")
        if not media_id or media_id == self._current_media_id:
            return

        frame_dir = FRAMES_DIR / media_id
        if not frame_dir.is_dir():
            return

        paths = sorted(frame_dir.glob("*.png"))
        if not paths:
            return

        meta_path = frame_dir / "meta.json"
        durations: list[float] = []
        if meta_path.exists():
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
            durations = meta.get("durations", [])

        if not durations:
            fps = data.get("fps", TARGET_FPS)
            durations = [1.0 / fps] * len(paths)

        self._current_media_id = media_id
        self._frame_paths = paths
        self._frame_durations = durations
        self._frame_index = 0

    def _pil_to_surface(self, image: Image.Image) -> pygame.Surface:
        masked = apply_circle_mask(image, self._mask)
        rgb = masked.convert("RGB")
        return pygame.image.fromstring(
            rgb.tobytes(),
            rgb.size,
            "RGB",
        )

    def _show_frame_path(self, path: Path) -> None:
        with Image.open(path) as img:
            surface = self._pil_to_surface(img)
        self._screen.blit(surface, (0, 0))
        pygame.display.flip()

    def _handle_events(self) -> None:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                self._running = False
            elif event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                self._running = False

    def run(self) -> None:
        print(f"Renderer started {DISPLAY_WIDTH}x{DISPLAY_HEIGHT} @ {TARGET_FPS}fps")
        while self._running:
            self._handle_events()
            self._load_state()

            if self._frame_paths:
                self._show_frame_path(self._frame_paths[self._frame_index])
                duration = self._frame_durations[self._frame_index]
                self._frame_index = (self._frame_index + 1) % len(self._frame_paths)
                self._clock.tick(max(1, int(1.0 / duration)))
            else:
                self._screen.fill((0, 0, 0))
                pygame.display.flip()
                self._clock.tick(TARGET_FPS)

        pygame.quit()


def main() -> None:
    renderer = HDMIRenderer()
    try:
        renderer.run()
    except KeyboardInterrupt:
        pygame.quit()
        sys.exit(0)


if __name__ == "__main__":
    main()
