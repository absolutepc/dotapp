"""REST API routes for BMW Logo device."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel

from firmware.config import (
    DEVICE_NAME,
    DISPLAY_HEIGHT,
    DISPLAY_WIDTH,
    MAX_UPLOAD_BYTES,
    PREVIEW_DIR,
)
from firmware.media.processor import MediaProcessor
from firmware.media.storage import MediaStorage
from firmware.state import get_current_media_id, set_current_media

router = APIRouter(prefix="/api")
storage = MediaStorage()
processor = MediaProcessor(storage)


class DisplayRequest(BaseModel):
    media_id: str


@router.on_event("startup")
async def startup() -> None:
    storage.register_builtin_assets()
    for item in storage.list_all():
        try:
            processor.ensure_frames(item)
        except FileNotFoundError:
            continue

    current = get_current_media_id()
    if not current:
        default = next((m for m in storage.list_all() if "default" in m.id), None)
        if default:
            set_current_media(default.id, default.fps)


@router.get("/status")
def status() -> dict:
    current = get_current_media_id()
    item = storage.get(current) if current else None
    return {
        "device": DEVICE_NAME,
        "current": current,
        "current_name": item.name if item else None,
        "resolution": f"{DISPLAY_WIDTH}x{DISPLAY_HEIGHT}",
        "connected": True,
    }


@router.get("/gallery")
def gallery() -> list[dict]:
    items = []
    for item in storage.list_all():
        items.append(
            {
                **item.to_dict(),
                "preview_url": f"/api/preview/{item.id}",
                "source_url": f"/api/source/{item.id}",
            }
        )
    return items


@router.post("/upload")
async def upload(file: UploadFile = File(...)) -> dict:
    data = await file.read()
    if len(data) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=413, detail="File too large")

    if not file.filename:
        raise HTTPException(status_code=400, detail="Missing filename")

    suffix = Path(file.filename).suffix.lower()
    allowed = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
    if suffix not in allowed:
        raise HTTPException(status_code=400, detail=f"Unsupported type: {suffix}")

    media_id, dest = storage.save_upload(file.filename, data)
    name = Path(file.filename).stem.replace("-", " ").title()
    item = processor.process_file(media_id, dest, name, builtin=False)
    return {"media_id": item.id, "name": item.name, "type": item.type}


@router.post("/display")
def display(req: DisplayRequest) -> dict:
    item = storage.get(req.media_id)
    if not item:
        raise HTTPException(status_code=404, detail="Media not found")

    processor.ensure_frames(item)
    set_current_media(item.id, item.fps)
    return {"ok": True, "media_id": item.id}


@router.delete("/media/{media_id}")
def delete_media(media_id: str) -> dict:
    if not storage.delete(media_id):
        raise HTTPException(status_code=404, detail="Cannot delete media")
    current = get_current_media_id()
    if current == media_id:
        default = next((m for m in storage.list_all() if m.builtin), None)
        if default:
            set_current_media(default.id, default.fps)
    return {"ok": True}


@router.get("/preview/{media_id}")
def preview(media_id: str) -> FileResponse:
    path = PREVIEW_DIR / f"{media_id}.jpg"
    if not path.exists():
        item = storage.get(media_id)
        if not item:
            raise HTTPException(status_code=404, detail="Not found")
        processor.ensure_frames(item)
        path = PREVIEW_DIR / f"{media_id}.jpg"

    if not path.exists():
        raise HTTPException(status_code=404, detail="Preview not found")

    return FileResponse(path, media_type="image/jpeg")


@router.get("/source/{media_id}")
def source(media_id: str) -> FileResponse:
    """Original uploaded/builtin file (GIF/PNG) for web preview / animations."""
    item = storage.get(media_id)
    if not item:
        raise HTTPException(status_code=404, detail="Not found")
    path = storage.resolve_source_path(item)
    if not path.exists():
        raise HTTPException(status_code=404, detail="Source file not found")

    suffix = path.suffix.lower()
    media_types = {
        ".gif": "image/gif",
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".webp": "image/webp",
    }
    return FileResponse(
        path,
        media_type=media_types.get(suffix, "application/octet-stream"),
        filename=path.name,
    )
