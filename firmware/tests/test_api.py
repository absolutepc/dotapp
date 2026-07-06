"""Tests for BMW Logo firmware."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from firmware.config import REPO_ROOT
from firmware.main import app
from firmware.media.processor import MediaProcessor
from firmware.media.storage import MediaStorage


@pytest.fixture
def client(tmp_path, monkeypatch):
    frames = tmp_path / "frames"
    monkeypatch.setattr("firmware.config.DATA_ROOT", tmp_path)
    monkeypatch.setattr("firmware.config.MEDIA_DIR", tmp_path / "media")
    monkeypatch.setattr("firmware.config.FRAMES_DIR", frames)
    monkeypatch.setattr("firmware.config.PREVIEW_DIR", tmp_path / "previews")
    monkeypatch.setattr("firmware.config.STATE_DIR", tmp_path / "state")
    monkeypatch.setattr("firmware.state.STATE_DIR", tmp_path / "state")
    monkeypatch.setattr("firmware.config.MANIFEST_FILE", tmp_path / "manifest.json")
    current = tmp_path / "state" / "current.json"
    monkeypatch.setattr("firmware.config.CURRENT_MEDIA_FILE", current)
    monkeypatch.setattr("firmware.state.CURRENT_MEDIA_FILE", current)
    monkeypatch.setattr("firmware.config.BUILTIN_ASSETS", REPO_ROOT / "assets")

    import firmware.api.routes as routes

    routes.storage = MediaStorage()
    routes.processor = MediaProcessor(routes.storage)

    return TestClient(app), frames


def test_status(client):
    test_client, _ = client
    response = test_client.get("/api/status")
    assert response.status_code == 200
    data = response.json()
    assert data["device"] == "bmw-logo"
    assert data["resolution"] == "480x480"


def test_upload_and_display_png(client):
    test_client, frames_dir = client
    png_path = REPO_ROOT / "assets" / "bmw" / "default.png"
    if not png_path.exists():
        pytest.skip("assets not generated")

    with png_path.open("rb") as f:
        upload = test_client.post("/api/upload", files={"file": ("test.png", f, "image/png")})
    assert upload.status_code == 200
    media_id = upload.json()["media_id"]

    display = test_client.post("/api/display", json={"media_id": media_id})
    assert display.status_code == 200

    frame_dir = frames_dir / media_id
    assert any(frame_dir.glob("*.png"))


def test_circle_mask_frame_size():
    from firmware.display.mask import apply_circle_mask, create_circle_mask
    from PIL import Image

    mask = create_circle_mask((480, 480))
    assert mask.size == (480, 480)

    img = Image.new("RGBA", (480, 480), (255, 0, 0, 255))
    result = apply_circle_mask(img, mask)
    assert result.size == (480, 480)
    # Corner should be black
    assert result.getpixel((0, 0)) == (0, 0, 0, 255)
