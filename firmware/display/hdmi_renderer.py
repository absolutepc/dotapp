"""Pygame HDMI fullscreen renderer for round 480x480 @ 60fps."""

from __future__ import annotations

import json
import os
import sys
import threading
import time
from collections import OrderedDict
from pathlib import Path

# Must be set before importing pygame/SDL — otherwise ALSA hotplug threads
# start and hang systemd stop (SIGKILL of SDLHotplugALSA).
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
os.environ.setdefault("SDL_VIDEODRIVER", "KMSDRM")
os.environ.setdefault("SDL_VIDEO_EGL_DRIVER", "libEGL.so.1")
os.environ.setdefault("SDL_VIDEO_GL_DRIVER", "libGLESv2.so.2")
if not os.environ.get("XDG_RUNTIME_DIR"):
    os.environ["XDG_RUNTIME_DIR"] = "/run/dot-display"

import pygame
from PIL import Image

from firmware.config import (
    CURRENT_MEDIA_FILE,
    DISPLAY_HEIGHT,
    DISPLAY_WIDTH,
    FRAMES_DIR,
    TARGET_FPS,
)
from firmware.state import get_brightness

# Never RAM-preload full clips on Pi Zero: blocking the loop makes the X11/SDL
# window look like it closed, and long stalls can trip the window manager.
# Always stream from disk with a small LRU + lookahead prefetch.
PRELOAD_FRAME_LIMIT = 0
SURFACE_CACHE_SIZE = 48
PREFETCH_AHEAD = 12


def _init_pygame_display() -> pygame.Surface:
    """Try SDL drivers until a *real* on-screen backend works (not offscreen)."""
    os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
    os.environ.setdefault("SDL_VIDEO_EGL_DRIVER", "libEGL.so.1")
    os.environ.setdefault("SDL_VIDEO_GL_DRIVER", "libGLESv2.so.2")
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or "/run/dot-display")
    try:
        runtime.mkdir(parents=True, exist_ok=True)
        os.environ["XDG_RUNTIME_DIR"] = str(runtime)
    except OSError:
        os.environ["XDG_RUNTIME_DIR"] = "/tmp"

    preferred = os.environ.get("SDL_VIDEODRIVER")
    drivers: list[str] = []
    if preferred and preferred.lower() not in {"auto", "default"}:
        drivers.append(preferred)
    # SDL lists the driver as "KMSDRM"; lowercase often reports "not available".
    for driver in ("KMSDRM", "kmsdrm", "fbcon", "x11"):
        if driver not in drivers:
            drivers.append(driver)

    last_error: Exception | None = None
    for driver in drivers:
        os.environ["SDL_VIDEODRIVER"] = driver
        try:
            pygame.display.quit()
        except pygame.error:
            pass
        try:
            if pygame.get_init():
                pygame.quit()
        except pygame.error:
            pass
        try:
            # Full init with dummy audio (set above) so timer/events work on KMSDRM.
            pygame.init()
            try:
                pygame.mixer.quit()
            except pygame.error:
                pass
            pygame.display.init()
            pygame.mouse.set_visible(False)
            flags = pygame.FULLSCREEN
            if hasattr(pygame, "DOUBLEBUF"):
                flags |= pygame.DOUBLEBUF
            screen = pygame.display.set_mode(
                (DISPLAY_WIDTH, DISPLAY_HEIGHT),
                flags,
            )
            used = (pygame.display.get_driver() or "").lower()
            info = pygame.display.Info()
            print(
                f"Display driver: {used} (requested={driver}) "
                f"mode={info.current_w}x{info.current_h} bits={info.bitsize}",
                flush=True,
            )
            if used in {"offscreen", "dummy", "evdev"}:
                raise pygame.error(f"refusing non-display backend: {used}")
            # Optional diagnostic splash (DOT_BOOT_SPLASH=1). Default: stay black until logo frames.
            if os.environ.get("DOT_BOOT_SPLASH", "").strip() in {"1", "true", "yes"}:
                screen.fill((0, 90, 180))
                pygame.draw.circle(screen, (255, 255, 255), (DISPLAY_WIDTH // 2, DISPLAY_HEIGHT // 2), 110, 10)
                pygame.draw.line(
                    screen, (0, 255, 210),
                    (30, DISPLAY_HEIGHT // 2), (DISPLAY_WIDTH - 30, DISPLAY_HEIGHT // 2), 8,
                )
                pygame.draw.line(
                    screen, (0, 255, 210),
                    (DISPLAY_WIDTH // 2, 30), (DISPLAY_WIDTH // 2, DISPLAY_HEIGHT - 30), 8,
                )
                pygame.display.flip()
                print("boot splash drawn (DOT_BOOT_SPLASH=1)", flush=True)
            else:
                screen.fill((0, 0, 0))
                pygame.display.flip()
            return screen
        except pygame.error as exc:
            last_error = exc
            print(f"Driver {driver} failed: {exc}", flush=True)

    raise RuntimeError(f"No SDL display driver available: {last_error}")


class HDMIRenderer:
    def __init__(self) -> None:
        self._screen = _init_pygame_display()
        pygame.display.set_caption("Dot")
        pygame.mouse.set_visible(False)
        if os.environ.get("DOT_BOOT_SPLASH", "").strip() in {"1", "true", "yes"}:
            time.sleep(2.0)

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
        self._cache_lock = threading.Lock()
        self._last_state_mtime = 0.0
        self._last_frames_mtime = 0.0
        self._brightness = get_brightness()
        print(f"brightness={self._brightness} state={CURRENT_MEDIA_FILE}", flush=True)
        self._brightness_check_at = 0.0
        self._dim_overlay = pygame.Surface((DISPLAY_WIDTH, DISPLAY_HEIGHT))
        self._dim_overlay.fill((0, 0, 0))
        self._apply_brightness_overlay_alpha()

        self._prefetch_index = 0
        self._prefetch_wake = threading.Event()
        self._prefetch_thread = threading.Thread(
            target=self._prefetch_loop,
            name="dot-prefetch",
            daemon=True,
        )
        self._prefetch_thread.start()

    def _apply_brightness_overlay_alpha(self) -> None:
        # 100 = full brightness (no dim). 5 ≈ almost dark.
        level = max(0, min(100, int(self._brightness)))
        alpha = int(round((100 - level) / 100 * 255))
        self._dim_overlay.set_alpha(alpha)

    def _refresh_brightness(self, now: float) -> None:
        if now - self._brightness_check_at < 0.25:
            return
        self._brightness_check_at = now
        level = get_brightness()
        if level != self._brightness:
            self._brightness = level
            self._apply_brightness_overlay_alpha()

    def _blit_with_brightness(self, surface: pygame.Surface | None) -> None:
        if surface is not None:
            self._screen.blit(surface, (0, 0))
        else:
            # Bright red = missing frame (near-black was indistinguishable from "off")
            self._screen.fill((160, 20, 40))
        if self._brightness < 100:
            self._screen.blit(self._dim_overlay, (0, 0))
        pygame.display.flip()

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
                    try:
                        return surface.convert()
                    except pygame.error:
                        return surface
            except pygame.error:
                pass
        with Image.open(path) as img:
            rgb = img.convert("RGB")
            if rgb.size != (DISPLAY_WIDTH, DISPLAY_HEIGHT):
                rgb = rgb.resize((DISPLAY_WIDTH, DISPLAY_HEIGHT), Image.Resampling.BILINEAR)
            surface = pygame.image.fromstring(rgb.tobytes(), rgb.size, "RGB")
        try:
            return surface.convert()
        except pygame.error:
            return surface

    def _cache_put(self, index: int, surface: pygame.Surface) -> None:
        with self._cache_lock:
            self._cache[index] = surface
            self._cache.move_to_end(index)
            while len(self._cache) > SURFACE_CACHE_SIZE:
                self._cache.popitem(last=False)

    def _load_cached(self, index: int) -> pygame.Surface | None:
        if index < 0 or index >= len(self._frame_paths):
            return None
        with self._cache_lock:
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

    def _prefetch_loop(self) -> None:
        """Warm upcoming frames off the render thread so FPS stays stable."""
        while self._running:
            self._prefetch_wake.wait(timeout=0.25)
            self._prefetch_wake.clear()
            if not self._running or self._preload_all:
                continue
            n = len(self._frame_paths)
            if n == 0:
                continue
            start = self._prefetch_index
            for offset in range(1, PREFETCH_AHEAD + 1):
                if not self._running:
                    break
                idx = (start + offset) % n
                with self._cache_lock:
                    if idx in self._cache:
                        continue
                self._load_cached(idx)
                # Yield so the blit thread keeps priority on a single-core Zero
                time.sleep(0.002)

    def _request_prefetch(self, index: int) -> None:
        if self._preload_all:
            return
        self._prefetch_index = index
        self._prefetch_wake.set()

    def _get_surface(self, index: int) -> pygame.Surface | None:
        if self._preload_all:
            if 0 <= index < len(self._surfaces):
                return self._surfaces[index]
            return None
        surface = self._load_cached(index)
        self._request_prefetch(index)
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

        with self._cache_lock:
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
        self._blit_with_brightness(first)
        self._request_prefetch(0)
        print(f"Loaded media {media_id}: {len(paths)} frames (disk+cache)")

    def _handle_events(self) -> None:
        for event in pygame.event.get():
            # Never quit the kiosk renderer from SDL events (QUIT/ESC/etc).
            if event.type == pygame.QUIT:
                print("Ignoring SDL QUIT (keep display process alive)", flush=True)
                continue
            if event.type == pygame.KEYDOWN:
                print(f"Ignoring key {event.key} (kiosk stays up)", flush=True)
                continue

    def run(self) -> None:
        print(f"Renderer started {DISPLAY_WIDTH}x{DISPLAY_HEIGHT} @ {TARGET_FPS}fps", flush=True)
        last_beat = 0.0
        while self._running:
            dt = self._clock.tick(TARGET_FPS) / 1000.0
            self._handle_events()
            now = time.monotonic()
            self._refresh_brightness(now)
            self._load_state()

            if now - last_beat >= 15.0:
                last_beat = now
                print(
                    f"heartbeat media={self._current_media_id} "
                    f"frames={len(self._frame_paths)} idx={self._frame_index} "
                    f"brightness={self._brightness}",
                    flush=True,
                )

            if not self._frame_paths:
                # Dim gray (not pure black) so "no cache yet" is distinguishable
                self._blit_with_brightness(None)
                continue

            self._accum += dt
            guard = 0
            n = len(self._frame_paths)
            while guard < n and self._accum >= self._frame_durations[self._frame_index]:
                self._accum -= self._frame_durations[self._frame_index]
                self._frame_index = (self._frame_index + 1) % n
                guard += 1

            surface = self._get_surface(self._frame_index)
            self._blit_with_brightness(surface)

        print("Renderer loop ended", flush=True)
        self._prefetch_wake.set()


def main() -> None:
    import signal

    renderer: HDMIRenderer | None = None

    def _stop(signum: int, *_args: object) -> None:
        print(f"signal {signum} received — stopping renderer", flush=True)
        if renderer is not None:
            renderer._running = False
        # Hard-exit if SDL teardown blocks (common with KMSDRM).
        signal.signal(signal.SIGALRM, lambda *_: os._exit(0))
        signal.alarm(2)

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    # Do not die if the controlling terminal goes away
    signal.signal(signal.SIGHUP, signal.SIG_IGN)

    renderer = HDMIRenderer()
    try:
        renderer.run()
    finally:
        print("renderer main() exiting", flush=True)
        try:
            pygame.display.quit()
        except pygame.error:
            pass
        try:
            pygame.quit()
        except pygame.error:
            pass


if __name__ == "__main__":
    main()
