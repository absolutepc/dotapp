"""Shared state between API and display renderer."""

from __future__ import annotations

import json
from pathlib import Path

from firmware.config import CURRENT_MEDIA_FILE, STATE_DIR, TARGET_FPS


def ensure_state_dir() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)


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
