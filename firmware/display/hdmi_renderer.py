"""Pygame HDMI fullscreen renderer for round 480x480 @ 60fps."""

from __future__ import annotations

import json
import os
import sys
from collections import OrderedDict
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

# Never RAM-preload full clips on Pi Zero: blocking the loop makes the X11/SDL
# window look like it closed, and long stalls can trip the window manager.
# Always stream from disk with a small LRU + lookahead prefetch.
PRELOAD_FRAME_LIMIT = 0
SURFACE_CACHE_SIZE = 48
PREFETCH_AHEAD = 12


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
        pygame.display.set_caption("Dot")
        pygame.mouse.set_visible(False)

        self._clock = pygame.time.Clock()
        self._running = True
        self._current_media_id: str | None = None
        self._frame_paths: list[Path] = []
        self._surfaces: list[pygame.Surface | None] = []
        self._frame_durations: list[float] = []
        self._frame_index = 0
        self._accum = 0.0
        self._preload_all = True
        self._cache: OrderedDict[int, pygame.Surface] = OrderedDict()
        self._last_state_mtime = 0.0
        self._last_frames_mtime = 0.0

    def _dir_mtime(self, frame_dir: Path) -> float:
        try:
            mtimes = [frame_dir.stat().st_mtime]
            meta = frame_dir / "meta.json"
            if meta.exists():
                mtimes.append(meta.stat().st_mtime)
            return max(mtimes)
        except OSError:
            return 0.0

    def _load_surface(self, path: Path) -> pygame.Surface:
        # Prefer pygame loader for already-sized JPEG/PNG caches (much faster than Pillow).
        suffix = path.suffix.lower()
        if suffix in {".jpg", ".jpeg", ".png"}:
            try:
                surface = pygame.image.load(str(path))
                if surface.get_size() == (DISPLAY_WIDTH, DISPLAY_HEIGHT):
                    return surface.convert()
            except pygame.error:
                pass
        with Image.open(path) as img:
            rgb = img.convert("RGB")
            if rgb.size != (DISPLAY_WIDTH, DISPLAY_HEIGHT):
                rgb = rgb.resize((DISPLAY_WIDTH, DISPLAY_HEIGHT), Image.Resampling.BILINEAR)
            surface = pygame.image.fromstring(rgb.tobytes(), rgb.size, "RGB")
        return surface.convert()

    def _cache_put(self, index: int, surface: pygame.Surface) -> None:
        self._cache[index] = surface
        self._cache.move_to_end(index)
        while len(self._cache) > SURFACE_CACHE_SIZE:
            self._cache.popitem(last=False)

    def _load_cached(self, index: int) -> pygame.Surface | None:
        if index < 0 or index >= len(self._frame_paths):
            return None
        if index in self._cache:
            self._cache.move_to_end(index)
            return self._cache[index]
        try:
            surface = self._load_surface(self._frame_paths[index])
        except Exception as exc:  # noqa: BLE001
            print(f"Skip frame {index}: {exc}")
            return None
        self._cache_put(index, surface)
        return surface

    def _prefetch(self, index: int) -> None:
        """Warm the next few frames while the current one is on screen."""
        if self._preload_all:
            return
        n = len(self._frame_paths)
        if n == 0:
            return
        for offset in range(1, PREFETCH_AHEAD + 1):
            self._load_cached((index + offset) % n)

    def _get_surface(self, index: int) -> pygame.Surface | None:
        if self._preload_all:
            if 0 <= index < len(self._surfaces):
                return self._surfaces[index]
            return None
        surface = self._load_cached(index)
        self._prefetch(index)
        return surface

    def _load_state(self) -> None:
        if not CURRENT_MEDIA_FILE.exists():
            return

        state_mtime = CURRENT_MEDIA_FILE.stat().st_mtime
        data = json.loads(CURRENT_MEDIA_FILE.read_text(encoding="utf-8"))
        media_id = data.get("media_id")
        if not media_id:
            return

        frame_dir = FRAMES_DIR / media_id
        if not frame_dir.is_dir():
            return

        frames_mtime = self._dir_mtime(frame_dir)
        same_media = media_id == self._current_media_id
        if (
            same_media
            and state_mtime <= self._last_state_mtime
            and frames_mtime <= self._last_frames_mtime
        ):
            return

        paths = sorted(
            p
            for p in frame_dir.iterdir()
            if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg"}
        )
        if not paths:
            return

        meta_path = frame_dir / "meta.json"
        durations: list[float] = []
        if meta_path.exists():
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
            durations = meta.get("durations", [])

        if not durations or len(durations) != len(paths):
            fps = float(data.get("fps") or TARGET_FPS)
            durations = [1.0 / max(fps, 1.0)] * len(paths)

        self._cache.clear()
        self._surfaces = []
        self._frame_paths = paths
        self._preload_all = False
        print(
            f"Streaming media {media_id}: {len(paths)} frames "
            f"(cache {SURFACE_CACHE_SIZE})"
        )

        self._frame_durations = durations[: len(paths)]
        if len(self._frame_durations) < len(paths):
            pad = self._frame_durations[-1] if self._frame_durations else (1.0 / TARGET_FPS)
            self._frame_durations.extend([pad] * (len(paths) - len(self._frame_durations)))

        self._current_media_id = media_id
        self._frame_index = 0
        self._accum = 0.0
        self._last_state_mtime = state_mtime
        self._last_frames_mtime = frames_mtime
        # Show first frame immediately so the window never goes blank/closed-looking
        first = self._load_cached(0)
        if first is not None:
            self._screen.blit(first, (0, 0))
            pygame.display.flip()
        print(f"Loaded media {media_id}: {len(paths)} frames (disk+cache)")

    def _handle_events(self) -> None:
        for event in pygame.event.get():
            # Ignore QUIT: under X11 a transient WM event can kill the process;
            # systemd then restarts it as a *new* window when switching logos.
            if event.type == pygame.QUIT:
                print("Ignoring SDL QUIT (keep display process alive)")
                continue
            if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                print("ESC pressed — exiting renderer")
                self._running = False

    def run(self) -> None:
        print(f"Renderer started {DISPLAY_WIDTH}x{DISPLAY_HEIGHT} @ {TARGET_FPS}fps")
        while self._running:
            dt = self._clock.tick(TARGET_FPS) / 1000.0
            self._handle_events()
            self._load_state()

            if not self._frame_paths:
                # Dim gray (not pure black) so "no cache yet" is distinguishable
                self._screen.fill((18, 18, 22))
                pygame.display.flip()
                continue

            self._accum += dt
            guard = 0
            n = len(self._frame_paths)
            while guard < n and self._accum >= self._frame_durations[self._frame_index]:
                self._accum -= self._frame_durations[self._frame_index]
                self._frame_index = (self._frame_index + 1) % n
                guard += 1

            surface = self._get_surface(self._frame_index)
            if surface is not None:
                self._screen.blit(surface, (0, 0))
            else:
                self._screen.fill((18, 18, 22))
            pygame.display.flip()

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
