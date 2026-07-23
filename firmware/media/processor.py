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
# 12 fps keeps motion readable and finishes faster on Pi Zero first prepare
VIDEO_TARGET_FPS = 12.0
# Bump when PNG/JPEG cache encoding changes so ensure_frames rebuilds on Pi.
# v7: GIF/static frames stored as JPEG (faster I/O on Pi Zero SD).
FRAME_CACHE_VERSION = 7
JPEG_QUALITY = 88
# Bump when preview picking / thumb enhancement changes (does not rebuild frames).
PREVIEW_VERSION = 3
PREVIEW_SIZE = 280


def list_frame_files(frame_dir: Path) -> list[Path]:
    """Cached display frames (all JPEG preferred; legacy PNG still accepted)."""
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

    def _score_preview_frame(self, image: Image.Image, *, index: int, total: int) -> float:
        """Prefer mid-clip frames that are bright enough, colorful, and detailed."""
        rgb = image.convert("RGB")
        w, h = rgb.size
        # Center crop — ignore outer black from circle / letterbox.
        sample = rgb.crop((w // 5, h // 5, 4 * w // 5, 4 * h // 5))
        stat = ImageStat.Stat(sample)
        r, g, b = stat.mean
        lum = (r + g + b) / 3.0
        var = sum(stat.var) / 3.0
        # Colorfulness: how far from gray.
        chroma = (abs(r - g) + abs(g - b) + abs(b - r)) / 3.0

        # Near-black / near-white thumbs look bad in the gallery.
        if lum < 18:
            return lum * 0.2
        if lum > 230:
            return 40.0

        # Prefer the middle of the clip (logo usually fully formed).
        t = index / max(total - 1, 1)
        mid_bonus = 1.0 - abs(t - 0.45) * 1.4  # peak near 45%
        mid_bonus = max(0.35, mid_bonus)

        # Target a readable mid-tone, not the absolute brightest flash frame.
        lum_score = 100.0 - abs(lum - 95.0) * 0.55
        return (lum_score + 0.04 * var + 1.8 * chroma) * mid_bonus

    def _pick_best_preview_frame(self, frame_paths: list[Path]) -> Image.Image:
        if not frame_paths:
            raise RuntimeError("No frames for preview")
        if len(frame_paths) == 1:
            return Image.open(frame_paths[0]).convert("RGB")

        n = len(frame_paths)
        # Sample more of the clip; still capped for Pi Zero.
        sample_count = min(28, n)
        indices = sorted({int(i * (n - 1) / max(sample_count - 1, 1)) for i in range(sample_count)})
        # Bias sampling toward the middle third.
        lo, hi = int(n * 0.2), max(int(n * 0.8), int(n * 0.2) + 1)
        mid_extra = list(range(lo, hi, max(1, (hi - lo) // 8)))
        indices = sorted(set(indices) | set(mid_extra))

        best_score = -1.0
        best: Image.Image | None = None
        for idx in indices:
            with Image.open(frame_paths[idx]) as im:
                score = self._score_preview_frame(im, index=idx, total=n)
                if score > best_score:
                    best_score = score
                    best = im.convert("RGB").copy()
        assert best is not None
        return best

    def _enhance_preview_thumb(self, image: Image.Image) -> Image.Image:
        """Make gallery thumbs readable without blowing out neon colors."""
        rgb = image.convert("RGB")
        # Gentle auto-contrast keeps structure without washing colors.
        rgb = ImageOps.autocontrast(rgb, cutoff=1)
        w, h = rgb.size
        sample = rgb.crop((w // 4, h // 4, 3 * w // 4, 3 * h // 4))
        lum = sum(ImageStat.Stat(sample).mean) / 3.0
        target = 92.0
        if lum < 40:
            rgb = ImageEnhance.Brightness(rgb).enhance(min(2.6, target / max(lum, 1.0)))
            rgb = ImageEnhance.Contrast(rgb).enhance(1.22)
        elif lum < 70:
            rgb = ImageEnhance.Brightness(rgb).enhance(min(1.55, target / max(lum, 1.0)))
            rgb = ImageEnhance.Contrast(rgb).enhance(1.12)
        elif lum > 160:
            rgb = ImageEnhance.Brightness(rgb).enhance(0.88)
            rgb = ImageEnhance.Contrast(rgb).enhance(1.08)
        rgb = ImageEnhance.Color(rgb).enhance(1.22)
        rgb = ImageEnhance.Sharpness(rgb).enhance(1.15)
        return rgb

    def _save_preview(self, media_id: str, frame: Image.Image) -> None:
        from firmware.config import PREVIEW_DIR

        PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
        enhanced = self._enhance_preview_thumb(frame)
        thumb = ImageOps.fit(
            enhanced,
            (PREVIEW_SIZE, PREVIEW_SIZE),
            method=Image.Resampling.LANCZOS,
            centering=(0.5, 0.5),
        )
        # Round mask so tiles match the Dot circle (black outside).
        mask = create_circle_mask((PREVIEW_SIZE, PREVIEW_SIZE))
        rounded = apply_circle_mask(thumb.convert("RGBA"), mask)
        rounded.convert("RGB").save(
            PREVIEW_DIR / f"{media_id}.jpg",
            quality=92,
            optimize=True,
        )

    def _write_preview_from_frames(self, media_id: str, frame_paths: list[Path], meta_path: Path) -> None:
        best = self._pick_best_preview_frame(frame_paths)
        try:
            self._save_preview(media_id, best)
        finally:
            best.close()
        meta: dict = {}
        if meta_path.exists():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
            except Exception:
                meta = {}
        meta["preview_version"] = PREVIEW_VERSION
        meta_path.write_text(json.dumps(meta, indent=2), encoding="utf-8")

    def ensure_preview(self, item: MediaItem) -> bool:
        """Refresh gallery thumb from existing frames if missing or stale."""
        from firmware.config import FRAMES_DIR, PREVIEW_DIR

        frame_dir = FRAMES_DIR / item.id
        paths = list_frame_files(frame_dir)
        if not paths:
            return False
        meta_path = frame_dir / "meta.json"
        preview_path = PREVIEW_DIR / f"{item.id}.jpg"
        meta: dict = {}
        if meta_path.exists():
            try:
                meta = json.loads(meta_path.read_text(encoding="utf-8"))
            except Exception:
                meta = {}
        if preview_path.exists() and int(meta.get("preview_version") or 0) == PREVIEW_VERSION:
            return True
        logger.info("Refreshing preview for %s (v%s)", item.id, PREVIEW_VERSION)
        self._write_preview_from_frames(item.id, paths, meta_path)
        return True

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

        vf = (
            f"fps={fps:.4f},"
            f"scale={DISPLAY_WIDTH}:{DISPLAY_HEIGHT}:flags=bilinear:"
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
            "1",
            "-i",
            str(decode_src),
            "-an",
            "-vf",
            vf,
            "-frames:v",
            str(MAX_VIDEO_FRAMES),
            "-q:v",
            "6",
            str(pattern),
        ]
        logger.info(
            "ffmpeg extract %s → %s (fps=%.2f)",
            decode_src.name,
            dest_dir,
            fps,
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
                    out = frame_dir / f"{idx:04d}.jpg"
                    masked.convert("RGB").save(
                        out, quality=JPEG_QUALITY, optimize=True
                    )
                    frame_paths.append(out)
                    duration_ms = frame.info.get("duration", int(1000 / TARGET_FPS))
                    durations.append(max(duration_ms, 1) / 1000.0)
            media_type = "animation"
            fps = 1.0 / (sum(durations) / len(durations)) if durations else TARGET_FPS
        else:
            with Image.open(source) as im:
                fitted = self._ensure_visible(self._fit_square(im))
                masked = apply_circle_mask(fitted, self._mask)
                out = frame_dir / "0000.jpg"
                masked.convert("RGB").save(out, quality=JPEG_QUALITY, optimize=True)
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
            "preview_version": PREVIEW_VERSION,
        }
        (frame_dir / "meta.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")

        self._write_preview_from_frames(media_id, frame_paths, frame_dir / "meta.json")

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

    def _resolve_source(self, item: MediaItem) -> Path:
        from firmware.config import REPO_ROOT

        source = self.storage.resolve_source_path(item)
        if not source.is_absolute():
            source = REPO_ROOT / source
        if not source.exists():
            # Common GitHub upload rename with spaces
            alt = source.parent / source.name.replace("_", " ")
            if alt.exists():
                return alt
            raise FileNotFoundError(f"Source not found: {source}")
        return source

    def frames_ready(self, item: MediaItem) -> bool:
        """True when on-disk frame cache is usable (no rebuild needed)."""
        from firmware.config import FRAMES_DIR

        try:
            source = self._resolve_source(item)
        except FileNotFoundError:
            return False

        frame_dir = FRAMES_DIR / item.id
        existing = list_frame_files(frame_dir)
        meta_path = frame_dir / "meta.json"
        if not existing or not meta_path.exists():
            return False
        try:
            meta = json.loads(meta_path.read_text(encoding="utf-8"))
        except Exception:
            return False
        if int(meta.get("cache_version") or 0) != FRAME_CACHE_VERSION:
            return False
        if meta.get("source_suffix") and meta.get("source_suffix") != source.suffix.lower():
            return False
        if int(meta.get("frame_count") or 0) != len(existing):
            return False
        if source.suffix.lower() in VIDEO_SUFFIXES and len(existing) <= 1:
            return False
        if source.suffix.lower() == ".gif":
            try:
                with Image.open(source) as im:
                    source_frames = min(int(getattr(im, "n_frames", 1) or 1), MAX_GIF_FRAMES)
                if len(existing) < source_frames:
                    return False
            except Exception:
                return False
        return True

    def ensure_frames(self, item: MediaItem) -> None:
        """Build frame cache for a manifest item if missing or stale."""
        if self.frames_ready(item):
            return
        source = self._resolve_source(item)
        logger.info("Rebuilding frames for %s from %s", item.id, source.name)
        self.process_file(item.id, source, item.name, builtin=item.builtin)
