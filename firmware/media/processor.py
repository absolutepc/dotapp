"""Convert uploaded/builtin media to 480x480 circular frame cache."""

from __future__ import annotations

import json
import logging
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageEnhance, ImageOps, ImageSequence, ImageStat

from firmware.config import DISPLAY_HEIGHT, DISPLAY_WIDTH, MAX_GIF_FRAMES, TARGET_FPS
from firmware.display.mask import apply_circle_mask, create_circle_mask
from firmware.media.storage import MediaItem, MediaStorage

logger = logging.getLogger(__name__)

VIDEO_SUFFIXES = {".webm", ".mp4", ".mov"}
MAX_VIDEO_FRAMES = 360
# 15 fps keeps motion smooth enough and finishes in seconds on Pi Zero
VIDEO_TARGET_FPS = 15.0
# Bump when PNG/JPEG cache encoding changes so ensure_frames rebuilds on Pi.
FRAME_CACHE_VERSION = 5
# Auto-zoom: fill this fraction of the round display with detected content.
CONTENT_FILL = 0.94
CONTENT_MIN_HEIGHT = 0.38
MAX_AUTO_ZOOM = 1.5


def list_frame_files(frame_dir: Path) -> list[Path]:
    """Cached display frames (GIF→PNG, video→JPEG)."""
    if not frame_dir.is_dir():
        return []
    return sorted(
        p
        for p in frame_dir.iterdir()
        if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg"}
    )


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

    def _ensure_visible(self, image: Image.Image) -> Image.Image:
        """Lift near-black neon/radar art so it reads on dim HDMI panels."""
        rgba = image.convert("RGBA")
        w, h = rgba.size
        sample = rgba.crop((w // 4, h // 4, 3 * w // 4, 3 * h // 4)).convert("RGB")
        lum = sum(ImageStat.Stat(sample).mean) / 3.0
        if lum < 12:
            factor = min(3.5, 28.0 / max(lum, 1.0))
            rgba = ImageEnhance.Brightness(rgba).enhance(factor)
            rgba = ImageEnhance.Contrast(rgba).enhance(1.4)
        elif lum < 28:
            rgba = ImageEnhance.Brightness(rgba).enhance(1.35)
            rgba = ImageEnhance.Contrast(rgba).enhance(1.2)
        return rgba

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

    def _decode_source(self, source: Path) -> Path:
        """Prefer H.264 .mp4 sibling — VP9 WebM decode is tiny on Pi Zero."""
        if source.suffix.lower() == ".webm":
            sibling = source.with_suffix(".mp4")
            if sibling.exists():
                logger.info("Decode via H.264 sibling %s (skip slow VP9)", sibling.name)
                return sibling
        return source

    def _probe_content_zoom(self, source: Path) -> float:
        """Zoom so small centered logos fill the round panel (e.g. Anim 3)."""
        import tempfile

        with tempfile.TemporaryDirectory(prefix="bmw-zoom-") as tmp:
            sample = Path(tmp) / "sample.png"
            cmd = [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-ss",
                "0.35",
                "-i",
                str(source),
                "-frames:v",
                "1",
                "-vf",
                f"scale={DISPLAY_WIDTH}:{DISPLAY_HEIGHT}",
                str(sample),
            ]
            result = subprocess.run(cmd, check=False, capture_output=True, timeout=60)
            if result.returncode != 0 or not sample.exists():
                return 1.0

            with Image.open(sample) as im:
                # Threshold to a mask, then bounding box of non-black content
                gray = im.convert("L")
                mask = gray.point(lambda p: 255 if p > 18 else 0)
                bbox = mask.getbbox()
                if not bbox:
                    return 1.0
                cw = bbox[2] - bbox[0]
                ch = bbox[3] - bbox[1]
                if cw * ch < 80:
                    return 1.0
                # Already fills enough of the round panel — leave framing alone
                if ch >= DISPLAY_HEIGHT * 0.28 and cw >= DISPLAY_WIDTH * 0.42:
                    return 1.0

        zoom_w = (DISPLAY_WIDTH * CONTENT_FILL) / max(cw, 1)
        zoom_h = (DISPLAY_HEIGHT * CONTENT_MIN_HEIGHT) / max(ch, 1)
        zoom = max(zoom_w, zoom_h, 1.0)
        zoom = min(zoom, MAX_AUTO_ZOOM)
        # Ignore tiny zooms — not worth re-encoding
        if zoom < 1.08:
            return 1.0
        logger.info(
            "Auto-zoom %s: content=%sx%s → zoom=%.2f",
            source.name,
            cw,
            ch,
            zoom,
        )
        return zoom

    def _extract_video_frames(self, source: Path, dest_dir: Path) -> tuple[list[Path], float]:
        """Extract WebM/MP4 directly to final 480x480 JPEGs (no per-frame Pillow)."""
        if shutil.which("ffmpeg") is None:
            raise RuntimeError(
                "ffmpeg is required for WebM/MP4. Install with: sudo apt install -y ffmpeg"
            )

        decode_src = self._decode_source(source)
        duration = self._probe_duration(decode_src) or self._probe_duration(source)
        if duration and duration > 0:
            fps = min(VIDEO_TARGET_FPS, MAX_VIDEO_FRAMES / duration)
        else:
            fps = VIDEO_TARGET_FPS
        fps = max(fps, 1.0)

        zoom = self._probe_content_zoom(decode_src)
        # Scale up then center-crop so small logos aren't tiny on the round HDMI
        scale_w = int(DISPLAY_WIDTH * zoom)
        scale_h = int(DISPLAY_HEIGHT * zoom)
        vf = (
            f"fps={fps:.4f},"
            f"scale={scale_w}:{scale_h}:flags=bilinear:"
            f"force_original_aspect_ratio=increase,"
            f"crop={DISPLAY_WIDTH}:{DISPLAY_HEIGHT},"
            "eq=contrast=1.35:brightness=0.12:gamma=1.25"
        )
        pattern = dest_dir / "%04d.jpg"
        cmd = [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-threads",
            "2",
            "-i",
            str(decode_src),
            "-an",
            "-vf",
            vf,
            "-frames:v",
            str(MAX_VIDEO_FRAMES),
            "-q:v",
            "5",
            str(pattern),
        ]
        logger.info(
            "ffmpeg extract %s → %s (fps=%.2f zoom=%.2f)",
            decode_src.name,
            dest_dir,
            fps,
            zoom,
        )
        result = subprocess.run(cmd, check=False, capture_output=True, timeout=420)
        if result.returncode != 0:
            err = (result.stderr or result.stdout or b"").decode("utf-8", errors="replace")
            raise RuntimeError(f"ffmpeg failed for {decode_src.name}: {err[-800:]}")

        frames = list_frame_files(dest_dir)
        if not frames:
            raise RuntimeError(f"ffmpeg produced no frames for {source}")
        logger.info("ffmpeg produced %d frames for %s", len(frames), source.name)
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
            # Write final JPEGs straight into frame_dir (fast path for Pi Zero)
            frame_paths, fps = self._extract_video_frames(source, frame_dir)
            durations = [1.0 / fps] * len(frame_paths)
            media_type = "animation"
        elif suffix == ".gif":
            with Image.open(source) as im:
                canvas = Image.new("RGBA", im.size, (0, 0, 0, 0))
                for idx, frame in enumerate(ImageSequence.Iterator(im)):
                    if idx >= MAX_GIF_FRAMES:
                        break
                    rgba = frame.convert("RGBA")
                    disposal = int(getattr(frame, "disposal_method", 0) or 0)
                    composed = canvas.copy()
                    composed.paste(rgba, (0, 0), rgba)
                    if disposal == 2:
                        canvas = Image.new("RGBA", im.size, (0, 0, 0, 0))
                    else:
                        canvas = composed

                    fitted = self._ensure_visible(self._fit_square(composed))
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
                fitted = self._ensure_visible(self._fit_square(im))
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
            "cache_version": FRAME_CACHE_VERSION,
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
        """Build frame cache for a manifest item if missing or stale."""
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

        existing = list_frame_files(frame_dir)
        meta_path = frame_dir / "meta.json"
        needs_rebuild = False
        meta: dict = {}
        if meta_path.exists():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
            except Exception:
                meta = {}
                needs_rebuild = True

        if not existing:
            needs_rebuild = True
        elif int(meta.get("cache_version") or 0) != FRAME_CACHE_VERSION:
            needs_rebuild = True
        elif meta.get("source_suffix") and meta.get("source_suffix") != source.suffix.lower():
            needs_rebuild = True
        elif int(meta.get("frame_count") or 0) != len(existing):
            needs_rebuild = True
        elif source.suffix.lower() in VIDEO_SUFFIXES and len(existing) <= 1:
            needs_rebuild = True
        elif source.suffix.lower() == ".gif":
            try:
                with Image.open(source) as im:
                    source_frames = min(int(getattr(im, "n_frames", 1) or 1), MAX_GIF_FRAMES)
                if len(existing) < source_frames:
                    needs_rebuild = True
            except Exception:
                needs_rebuild = True

        if not needs_rebuild:
            return

        logger.info("Rebuilding frames for %s from %s", item.id, source.name)
        self.process_file(item.id, source, item.name, builtin=item.builtin)
