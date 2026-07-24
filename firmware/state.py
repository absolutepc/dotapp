"""Shared state between API and display renderer."""

from __future__ import annotations

import json
from pathlib import Path

from firmware.config import CURRENT_MEDIA_FILE, DATA_ROOT, STATE_DIR, TARGET_FPS

PREPARE_STATUS_FILE = DATA_ROOT / "prepare-status.json"
DEFAULT_BRIGHTNESS = 100
MIN_BRIGHTNESS = 5
MAX_BRIGHTNESS = 100


def ensure_state_dir() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    DATA_ROOT.mkdir(parents=True, exist_ok=True)


def _brightness_path() -> Path:
    # Resolve from live config so tests can monkeypatch DATA_ROOT.
    from firmware.config import DATA_ROOT as live_root

    return live_root / "brightness.json"


def _clamp_brightness(value: int | float) -> int:
    return max(MIN_BRIGHTNESS, min(MAX_BRIGHTNESS, int(round(value))))


def get_brightness() -> int:
    path = _brightness_path()
    if not path.exists():
        return DEFAULT_BRIGHTNESS
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return _clamp_brightness(data.get("brightness", DEFAULT_BRIGHTNESS))
    except Exception:  # noqa: BLE001
        return DEFAULT_BRIGHTNESS


def set_brightness(value: int | float) -> int:
    ensure_state_dir()
    from firmware.config import DATA_ROOT as live_root

    live_root.mkdir(parents=True, exist_ok=True)
    level = _clamp_brightness(value)
    path = _brightness_path()
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps({"brightness": level}) + "\n", encoding="utf-8")
    tmp.replace(path)
    return level


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
