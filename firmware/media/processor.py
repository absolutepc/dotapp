"""Convert uploaded/builtin media to 480x480 circular frame cache."""

from __future__ import annotations

import json
import logging
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageOps, ImageSequence

from firmware.config import DISPLAY_HEIGHT, DISPLAY_WIDTH, MAX_GIF_FRAMES, TARGET_FPS
from firmware.display.mask import apply_circle_mask, create_circle_mask
from firmware.media.storage import MediaItem, MediaStorage

logger = logging.getLogger(__name__)

VIDEO_SUFFIXES = {".webm", ".mp4", ".mov"}
MAX_VIDEO_FRAMES = 180
VIDEO_TARGET_FPS = 60.0


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
        thumb.thumbnail((160, 160), Image.Resampling.LANCZOS)
        thumb.convert("RGB").save(PREVIEW_DIR / f"{media_id}.jpg", quality=90)

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
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
            )
            value = (result.stdout or "").strip()
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
        # Keep 60 fps smoothness; take up to MAX_VIDEO_FRAMES (180 → ~3.0s at 60fps).
        # Longer source videos are truncated to the first 180 frames.
        fps = VIDEO_TARGET_FPS

        # rgb24 + mild lift so dark radar animations stay visible on HDMI
        vf = (
            f"fps={fps:.4f},"
            f"scale={DISPLAY_WIDTH}:{DISPLAY_HEIGHT}:force_original_aspect_ratio=increase,"
            f"crop={DISPLAY_WIDTH}:{DISPLAY_HEIGHT},"
            "eq=contrast=1.12:brightness=0.04,"
            "format=rgb24"
        )
        pattern = dest_dir / "raw_%04d.png"
        cmd = [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(source),
            "-an",
            "-vf",
            vf,
            "-frames:v",
            str(MAX_VIDEO_FRAMES),
            str(pattern),
        ]
        result = subprocess.run(cmd, check=False, capture_output=True, timeout=300)
        if result.returncode != 0:
            err = (result.stderr or result.stdout or b"").decode("utf-8", errors="replace")
            raise RuntimeError(f"ffmpeg failed for {source.name}: {err[-800:]}")

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
        fps = TARGET_FPS

        if suffix in VIDEO_SUFFIXES:
            raw_dir = frame_dir / "_raw"
            raw_dir.mkdir(parents=True, exist_ok=True)
            try:
                raw_frames, fps = self._extract_video_frames(source, raw_dir)
                for idx, raw in enumerate(raw_frames):
                    with Image.open(raw) as im:
                        fitted = self._fit_square(im)
                        masked = apply_circle_mask(fitted, self._mask)
                        out = frame_dir / f"{idx:04d}.png"
                        masked.convert("RGB").save(out, optimize=False)
                        frame_paths.append(out)
                        durations.append(1.0 / fps)
            finally:
                shutil.rmtree(raw_dir, ignore_errors=True)
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

        if not frame_paths:
            raise RuntimeError(f"No frames produced for {source}")

        meta = {
            "durations": durations,
            "frame_count": len(frame_paths),
            "fps": fps,
            "source_suffix": suffix,
        }
        (frame_dir / "meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

        with Image.open(frame_paths[0]) as first:
            self._save_preview(media_id, first)

        # Keep relative path for builtins so resolve_source_path stays stable
        if builtin:
            try:
                from firmware.config import REPO_ROOT

                rel = source.resolve().relative_to(REPO_ROOT.resolve())
                filename = str(rel)
            except Exception:
                filename = str(source)
        else:
            filename = source.name

        item = MediaItem(
            id=media_id,
            name=name,
            type=media_type,
            builtin=builtin,
            filename=filename,
            frame_count=len(frame_paths),
            fps=fps,
        )
        # Always refresh manifest entry (fps/frame_count matter for display)
        self.storage.add(item)
        return item

    def ensure_frames(self, item: MediaItem) -> None:
        """Build frame cache for a manifest item if missing or stale video placeholder."""
        from firmware.config import FRAMES_DIR, REPO_ROOT

        frame_dir = FRAMES_DIR / item.id
        source = self.storage.resolve_source_path(item)
        if not source.is_absolute():
            source = REPO_ROOT / source
        if not source.exists():
            # Common GitHub upload rename with spaces
            alt = source.parent / source.name.replace("_", " ")
            if alt.exists():
                source = alt
            else:
                raise FileNotFoundError(f"Source not found: {source}")

        existing = sorted(frame_dir.glob("*.png")) if frame_dir.exists() else []
        meta_path = frame_dir / "meta.json"
        needs_rebuild = False
        if not existing:
            needs_rebuild = True
        elif source.suffix.lower() in VIDEO_SUFFIXES:
            if len(existing) <= 1:
                needs_rebuild = True
            elif meta_path.exists():
                try:
                    meta = json.loads(meta_path.read_text(encoding="utf-8"))
                    if meta.get("source_suffix") not in VIDEO_SUFFIXES:
                        needs_rebuild = True
                    if int(meta.get("frame_count") or 0) != len(existing):
                        needs_rebuild = True
                except Exception:
                    needs_rebuild = True
            else:
                needs_rebuild = True

        if not needs_rebuild:
            return

        self.process_file(item.id, source, item.name, builtin=item.builtin)
