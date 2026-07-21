"""Shared state between API and display renderer."""

from __future__ import annotations

import json
from pathlib import Path

from firmware.config import CURRENT_MEDIA_FILE, DATA_ROOT, STATE_DIR, TARGET_FPS

PREPARE_STATUS_FILE = DATA_ROOT / "prepare-status.json"


def ensure_state_dir() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    DATA_ROOT.mkdir(parents=True, exist_ok=True)


def get_current_media_id() -> str | None:
    if not CURRENT_MEDIA_FILE.exists():
        return None
    data = json.loads(CURRENT_MEDIA_FILE.read_text(encoding="utf-8"))
    return data.get("media_id")


def set_current_media(media_id: str, fps: float = TARGET_FPS) -> None:
    ensure_state_dir()
    CURRENT_MEDIA_FILE.write_text(
        json.dumps({"media_id": media_id, "fps": fps}, indent=2),
        encoding="utf-8",
    )


def write_prepare_status(
    *,
    media_id: str | None,
    state: str,
    message: str = "",
    progress: float | None = None,
) -> None:
    """state: idle | preparing | ready | error"""
    ensure_state_dir()
    payload = {
        "media_id": media_id,
        "state": state,
        "message": message,
        "progress": progress,
    }
    tmp = PREPARE_STATUS_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload) + "\n", encoding="utf-8")
    tmp.replace(PREPARE_STATUS_FILE)


def read_prepare_status() -> dict:
    if not PREPARE_STATUS_FILE.exists():
        return {"media_id": None, "state": "idle", "message": "", "progress": None}
    try:
        return json.loads(PREPARE_STATUS_FILE.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return {"media_id": None, "state": "idle", "message": "", "progress": None}
