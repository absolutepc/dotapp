"""REST API routes for Dot device."""

from __future__ import annotations

import logging
import socket
import threading
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
from firmware.media.processor import MediaProcessor, PREVIEW_VERSION
from firmware.media.storage import MediaStorage
from firmware.state import (
    get_current_media_id,
    read_prepare_status,
    set_current_media,
    write_prepare_status,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api")
storage = MediaStorage()
processor = MediaProcessor(storage)

_prepare_lock = threading.Lock()
_warmup_started = False


class DisplayRequest(BaseModel):
    media_id: str


def _mdns_hosts() -> list[str]:
    hosts = ["dot.local"]
    try:
        name = socket.gethostname().strip().split(".")[0]
        if name:
            hosts.append(f"{name}.local")
    except Exception:  # noqa: BLE001
        pass
    # de-dupe preserve order
    seen: set[str] = set()
    out: list[str] = []
    for h in hosts:
        key = h.lower()
        if key not in seen:
            seen.add(key)
            out.append(h)
    return out


def _warmup_top_animations(skip_id: str | None) -> None:
    """Build frame caches for a few gallery items in the background."""
    warmed = 0
    for item in storage.list_all():
        if warmed >= 5:
            break
        if skip_id and item.id == skip_id:
            continue
        if item.type != "animation":
            continue
        if processor.frames_ready(item):
            try:
                processor.ensure_preview(item)
            except Exception as exc:  # noqa: BLE001
                logger.warning("Preview warmup failed for %s: %s", item.id, exc)
            continue
        try:
            logger.info("Warmup prepare %s", item.id)
            processor.ensure_frames(item)
            warmed += 1
        except Exception as exc:  # noqa: BLE001
            logger.warning("Warmup failed for %s: %s", item.id, exc)

    # Refresh any stale previews for the rest of the catalog (frames already on disk).
    for item in storage.list_all():
        try:
            if processor.frames_ready(item):
                processor.ensure_preview(item)
        except Exception as exc:  # noqa: BLE001
            logger.debug("Preview refresh skipped for %s: %s", item.id, exc)


def _prepare_and_show(item_id: str) -> None:
    try:
        item = storage.get(item_id)
        if not item:
            write_prepare_status(
                media_id=item_id,
                state="error",
                message="Media not found",
            )
            return
        write_prepare_status(
            media_id=item_id,
            state="preparing",
            message="Готовим кадры…",
            progress=0.15,
        )
        processor.ensure_frames(item)
        item = storage.get(item_id) or item
        write_prepare_status(
            media_id=item_id,
            state="preparing",
            message="Выводим на экран…",
            progress=0.9,
        )
        set_current_media(item.id, item.fps)
        write_prepare_status(
            media_id=item.id,
            state="ready",
            message="Готово",
            progress=1.0,
        )
        logger.info("Display ready %s frames=%s", item.id, item.frame_count)
    except Exception as exc:  # noqa: BLE001
        logger.exception("Background prepare failed for %s", item_id)
        write_prepare_status(
            media_id=item_id,
            state="error",
            message=str(exc),
        )


@router.on_event("startup")
async def startup() -> None:
    """Register catalog and prepare only the active logo quickly.

    Full gallery frame caches are built lazily on /api/display. Preparing every
    360-frame GIF at boot left the HDMI renderer on a black screen for minutes.
    A small background warmup then prepares a few more animations.
    """
    global _warmup_started

    storage.register_builtin_assets()
    write_prepare_status(media_id=None, state="idle", message="")

    current = get_current_media_id()
    priority = None
    if current:
        priority = storage.get(current)
    if priority is None:
        # Prefer first BMW catalog animation (default.gif may be gone after gallery updates)
        for item in storage.list_all():
            if item.builtin and item.id.startswith("builtin-bmw-") and item.type == "animation":
                priority = item
                break
        if priority:
            set_current_media(priority.id, priority.fps)

    if priority is not None:
        try:
            processor.ensure_frames(priority)
            logger.info("Prepared startup media %s (%s frames)", priority.id, priority.frame_count)
        except Exception as exc:  # noqa: BLE001
            logger.exception("Failed to prepare startup media %s: %s", priority.id, exc)

    if not _warmup_started:
        _warmup_started = True
        skip = priority.id if priority else None
        threading.Thread(
            target=_warmup_top_animations,
            args=(skip,),
            name="dot-warmup",
            daemon=True,
        ).start()


@router.get("/status")
def status() -> dict:
    current = get_current_media_id()
    item = storage.get(current) if current else None
    prepare = read_prepare_status()
    return {
        "device": DEVICE_NAME,
        "current": current,
        "current_name": item.name if item else None,
        "resolution": f"{DISPLAY_WIDTH}x{DISPLAY_HEIGHT}",
        "connected": True,
        "mdns_hosts": _mdns_hosts(),
        "prepare": prepare,
    }


@router.get("/gallery")
def gallery() -> list[dict]:
    items = []
    for item in storage.list_all():
        items.append(
            {
                **item.to_dict(),
                "preview_url": f"/api/preview/{item.id}?v={PREVIEW_VERSION}",
                "source_url": f"/api/source/{item.id}",
                "frames_ready": processor.frames_ready(item),
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
    allowed = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".webm", ".mp4"}
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

    logger.info("Display request for %s (%s)", item.id, item.filename)

    # Fast path: cache already warm — switch immediately.
    if processor.frames_ready(item):
        set_current_media(item.id, item.fps)
        write_prepare_status(
            media_id=item.id,
            state="ready",
            message="Готово",
            progress=1.0,
        )
        logger.info("Display set (cached) %s frames=%s", item.id, item.frame_count)
        return {
            "ok": True,
            "media_id": item.id,
            "fps": item.fps,
            "frame_count": item.frame_count,
            "preparing": False,
            "message": "На экране",
        }

    # Slow path: return immediately and prepare in background.
    with _prepare_lock:
        write_prepare_status(
            media_id=item.id,
            state="preparing",
            message="Готовим кадры на Pi…",
            progress=0.05,
        )
        threading.Thread(
            target=_prepare_and_show,
            args=(item.id,),
            name=f"dot-prepare-{item.id[:12]}",
            daemon=True,
        ).start()

    return {
        "ok": True,
        "media_id": item.id,
        "fps": item.fps,
        "frame_count": item.frame_count,
        "preparing": True,
        "message": "Готовим кадры на Pi…",
    }


@router.get("/display/status")
def display_status() -> dict:
    prepare = read_prepare_status()
    current = get_current_media_id()
    return {
        **prepare,
        "current": current,
        "ready": prepare.get("state") == "ready"
        and prepare.get("media_id") == current
        and current is not None,
    }


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
    item = storage.get(media_id)
    path = PREVIEW_DIR / f"{media_id}.jpg"
    if item is not None:
        try:
            if not processor.ensure_preview(item):
                # No frames yet — build full cache (also writes preview).
                processor.ensure_frames(item)
                processor.ensure_preview(item)
        except Exception as exc:  # noqa: BLE001
            logger.warning("Preview prepare failed for %s: %s", media_id, exc)
        path = PREVIEW_DIR / f"{media_id}.jpg"

    if not path.exists():
        if not item:
            raise HTTPException(status_code=404, detail="Not found")
        raise HTTPException(status_code=404, detail="Preview not found")

    return FileResponse(
        path,
        media_type="image/jpeg",
        headers={"Cache-Control": "public, max-age=86400"},
    )


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
        ".webm": "video/webm",
        ".mp4": "video/mp4",
    }
    # Do not set filename=… — that forces Content-Disposition: attachment and
    # breaks <img>/<video> playback inside the HTML mockup.
    return FileResponse(
        path,
        media_type=media_types.get(suffix, "application/octet-stream"),
    )
