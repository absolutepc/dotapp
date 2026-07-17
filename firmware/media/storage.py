"""Media file storage and manifest management."""

from __future__ import annotations

import json
import shutil
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

from firmware.config import (
    BUILTIN_ASSETS,
    FRAMES_DIR,
    MANIFEST_FILE,
    MEDIA_DIR,
    PREVIEW_DIR,
    REPO_ROOT,
)


@dataclass
class MediaItem:
    id: str
    name: str
    type: str  # "image" | "animation"
    builtin: bool
    filename: str
    frame_count: int = 1
    fps: float = 60.0
    created_at: str = ""

    def to_dict(self) -> dict:
        return asdict(self)


class MediaStorage:
    def __init__(self) -> None:
        for path in (MEDIA_DIR, FRAMES_DIR, PREVIEW_DIR, MANIFEST_FILE.parent):
            path.mkdir(parents=True, exist_ok=True)
        if not MANIFEST_FILE.exists():
            self._write_manifest([])

    def _read_manifest(self) -> list[MediaItem]:
        raw = json.loads(MANIFEST_FILE.read_text(encoding="utf-8"))
        return [MediaItem(**item) for item in raw]

    def _write_manifest(self, items: list[MediaItem]) -> None:
        MANIFEST_FILE.write_text(
            json.dumps([item.to_dict() for item in items], indent=2),
            encoding="utf-8",
        )

    def list_all(self) -> list[MediaItem]:
        return self._read_manifest()

    def get(self, media_id: str) -> MediaItem | None:
        return next((m for m in self._read_manifest() if m.id == media_id), None)

    def add(self, item: MediaItem) -> None:
        items = [m for m in self._read_manifest() if m.id != item.id]
        items.append(item)
        self._write_manifest(items)

    def delete(self, media_id: str) -> bool:
        items = self._read_manifest()
        item = next((m for m in items if m.id == media_id), None)
        if not item or item.builtin:
            return False

        items = [m for m in items if m.id != media_id]
        self._write_manifest(items)

        media_path = MEDIA_DIR / item.filename
        if media_path.exists():
            media_path.unlink()

        frame_dir = FRAMES_DIR / media_id
        if frame_dir.exists():
            shutil.rmtree(frame_dir)

        preview = PREVIEW_DIR / f"{media_id}.jpg"
        if preview.exists():
            preview.unlink()

        return True

    def save_upload(self, filename: str, data: bytes) -> tuple[str, Path]:
        media_id = str(uuid.uuid4())
        ext = Path(filename).suffix.lower() or ".bin"
        stored_name = f"{media_id}{ext}"
        dest = MEDIA_DIR / stored_name
        dest.write_bytes(data)
        return media_id, dest

    def register_builtin_assets(self) -> None:
        """Sync built-in assets from repo into manifest."""
        catalog_path = BUILTIN_ASSETS / "catalog.json"
        display_names: dict[str, str] = {}
        if catalog_path.exists():
            for entry in json.loads(catalog_path.read_text(encoding="utf-8")):
                display_names[entry["id"]] = entry.get("name", entry["id"])

        existing = {m.id: m for m in self._read_manifest()}
        items = [m for m in existing.values() if not m.builtin]

        for category in ("bmw", "emoji"):
            cat_dir = BUILTIN_ASSETS / category
            if not cat_dir.is_dir():
                continue
            for path in sorted(cat_dir.iterdir()):
                if path.suffix.lower() not in {
                    ".png",
                    ".gif",
                    ".jpg",
                    ".jpeg",
                    ".webp",
                    ".webm",
                    ".mp4",
                }:
                    continue
                asset_id = f"builtin-{category}-{path.stem}"
                is_anim = path.suffix.lower() in {".gif", ".webm", ".mp4", ".webp"}
                name = display_names.get(asset_id, path.stem.replace("-", " ").title())
                items.append(
                    MediaItem(
                        id=asset_id,
                        name=name,
                        type="animation" if is_anim else "image",
                        builtin=True,
                        filename=str(path.relative_to(REPO_ROOT)),
                        frame_count=1,
                        fps=60.0,
                        created_at=datetime.now(timezone.utc).isoformat(),
                    )
                )

        self._write_manifest(items)

    def resolve_source_path(self, item: MediaItem) -> Path:
        if item.builtin:
            return REPO_ROOT / item.filename
        return MEDIA_DIR / Path(item.filename).name
