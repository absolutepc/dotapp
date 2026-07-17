"""Convert uploaded/builtin media to 480x480 circular frame cache."""

from __future__ import annotations

import json
import logging
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageOps, ImageSequence

from firmware.config import DISPLAY_HEIGHT, DISPLAY_WIDTH, MAX_GIF_FRAMES, TARGET_FPS
from firmware.display.mask import apply_circle_mask, create_circle_mask
from firmware.media.storage import MediaItem, MediaStorage

logger = logging.getLogger(__name__)

VIDEO_SUFFIXES = {".webm", ".mp4", ".mov"}
MAX_VIDEO_FRAMES = MAX_GIF_FRAMES
VIDEO_TARGET_FPS = 20.0


class MediaProcessor:
    def __init__(self, storage: MediaStorage | None = None) -> None:
        self.storage = storage or MediaStorage()
        self._mask = create_circle_mask()

    def _fit_square(self, image: Image.Image) -> Image.Image:
        return ImageOps.fit(
            image.convert("RGBA"),
            (DISPLAY_WIDTH, DISPLAY_HEIGHT),
            method=Image.Resampling.LANCZOS,
            centering=(0.5, 0.5),
        )

    def _save_preview(self, media_id: str, frame: Image.Image) -> None:
        from firmware.config import PREVIEW_DIR

        PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
        thumb = frame.copy()
        thumb.thumbnail((120, 120), Image.Resampling.LANCZOS)
        thumb.convert("RGB").save(PREVIEW_DIR / f"{media_id}.jpg", quality=85)

    def _probe_duration(self, source: Path) -> float | None:
        try:
            result = subprocess.run(
                [
                    "ffprobe",
                    "-v",
                    "error",
                    "-show_entries",
                    "format=duration",
                    "-of",
                    "default=noprint_wrappers=1:nokey=1",
                    str(source),
                ],
                check=True,
                capture_output=True,
                text=True,
                timeout=30,
            )
            value = result.stdout.strip()
            return float(value) if value else None
        except (subprocess.SubprocessError, ValueError, FileNotFoundError) as exc:
            logger.warning("ffprobe failed for %s: %s", source, exc)
            return None

    def _extract_video_frames(self, source: Path, dest_dir: Path) -> tuple[list[Path], float]:
        """Extract WebM/MP4 frames via ffmpeg into dest_dir as raw PNGs."""
        if shutil.which("ffmpeg") is None:
            raise RuntimeError(
                "ffmpeg is required for WebM/MP4. Install with: sudo apt install -y ffmpeg"
            )

        duration = self._probe_duration(source)
        if duration and duration > 0:
            fps = min(VIDEO_TARGET_FPS, MAX_VIDEO_FRAMES / duration)
        else:
            fps = VIDEO_TARGET_FPS
        fps = max(fps, 1.0)

        vf = (
            f"fps={fps:.4f},"
            f"scale={DISPLAY_WIDTH}:{DISPLAY_HEIGHT}:force_original_aspect_ratio=increase,"
            f"crop={DISPLAY_WIDTH}:{DISPLAY_HEIGHT}"
        )
        pattern = dest_dir / "raw_%04d.png"
        cmd = [
            "ffmpeg",
            "-y",
            "-i",
            str(source),
            "-vf",
            vf,
            "-frames:v",
            str(MAX_VIDEO_FRAMES),
            str(pattern),
        ]
        subprocess.run(cmd, check=True, capture_output=True, timeout=300)
        frames = sorted(dest_dir.glob("raw_*.png"))
        if not frames:
            raise RuntimeError(f"ffmpeg produced no frames for {source}")
        return frames, fps

    def process_file(
        self,
        media_id: str,
        source: Path,
        name: str,
        builtin: bool = False,
    ) -> MediaItem:
        suffix = source.suffix.lower()
        from firmware.config import FRAMES_DIR

        frame_dir = FRAMES_DIR / media_id
        if frame_dir.exists():
            shutil.rmtree(frame_dir)
        frame_dir.mkdir(parents=True, exist_ok=True)

        durations: list[float] = []
        frame_paths: list[Path] = []

        if suffix in VIDEO_SUFFIXES:
            with tempfile.TemporaryDirectory(prefix="bmw-video-") as tmp:
                raw_frames, fps = self._extract_video_frames(source, Path(tmp))
                for idx, raw in enumerate(raw_frames):
                    with Image.open(raw) as im:
                        fitted = self._fit_square(im)
                        masked = apply_circle_mask(fitted, self._mask)
                        out = frame_dir / f"{idx:04d}.png"
                        masked.convert("RGB").save(out)
                        frame_paths.append(out)
                        durations.append(1.0 / fps)
            media_type = "animation"
        elif suffix == ".gif":
            with Image.open(source) as im:
                for idx, frame in enumerate(ImageSequence.Iterator(im)):
                    if idx >= MAX_GIF_FRAMES:
                        break
                    fitted = self._fit_square(frame.convert("RGBA"))
                    masked = apply_circle_mask(fitted, self._mask)
                    out = frame_dir / f"{idx:04d}.png"
                    masked.convert("RGB").save(out)
                    frame_paths.append(out)
                    duration_ms = frame.info.get("duration", int(1000 / TARGET_FPS))
                    durations.append(max(duration_ms, 1) / 1000.0)
            media_type = "animation"
            fps = 1.0 / (sum(durations) / len(durations)) if durations else TARGET_FPS
        else:
            with Image.open(source) as im:
                fitted = self._fit_square(im)
                masked = apply_circle_mask(fitted, self._mask)
                out = frame_dir / "0000.png"
                masked.convert("RGB").save(out)
                frame_paths.append(out)
                durations = [1.0 / TARGET_FPS]
            media_type = "image"
            fps = TARGET_FPS

        meta = {"durations": durations, "frame_count": len(frame_paths), "fps": fps}
        (frame_dir / "meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

        with Image.open(frame_paths[0]) as first:
            self._save_preview(media_id, first)

        item = MediaItem(
            id=media_id,
            name=name,
            type=media_type,
            builtin=builtin,
            filename=str(source.name if not builtin else source),
            frame_count=len(frame_paths),
            fps=fps,
        )
        if not builtin:
            self.storage.add(item)
        return item

    def ensure_frames(self, item: MediaItem) -> None:
        """Build frame cache for a manifest item if missing."""
        from firmware.config import FRAMES_DIR, REPO_ROOT

        frame_dir = FRAMES_DIR / item.id
        source = self.storage.resolve_source_path(item)
        if not source.is_absolute():
            source = REPO_ROOT / source
        if not source.exists():
            raise FileNotFoundError(f"Source not found: {source}")

        existing = sorted(frame_dir.glob("*.png")) if frame_dir.exists() else []
        # Rebuild old WebM placeholders (single frame) now that ffmpeg extraction exists
        if existing and not (
            source.suffix.lower() in VIDEO_SUFFIXES and len(existing) <= 1
        ):
            return

        self.process_file(item.id, source, item.name, builtin=item.builtin)
