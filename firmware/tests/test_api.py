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
    png_path = REPO_ROOT / "assets" / "emoji" / "smile.png"
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


def test_upload_round_crop_persists_for_rebuild(client):
    """The source crop must survive cache rebuilding and remain 480×480."""
    from io import BytesIO
    from PIL import Image
    import shutil
    import firmware.api.routes as routes

    test_client, frames_dir = client
    source = Image.new("RGB", (800, 400), (230, 10, 10))
    # Right half is blue; selecting the left 400×400 must exclude it.
    source.paste((10, 10, 230), (400, 0, 800, 400))
    stream = BytesIO()
    source.save(stream, format="PNG")
    crop = {"x": 0.0, "y": 0.0, "w": 0.5, "h": 1.0}
    response = test_client.post(
        "/api/upload",
        files={"file": ("red-blue.png", stream.getvalue(), "image/png")},
        data={"crop": json.dumps(crop)},
    )
    assert response.status_code == 200, response.text
    item = routes.storage.get(response.json()["media_id"])
    assert item is not None and item.crop == crop
    frame_dir = frames_dir / item.id
    with Image.open(frame_dir / "0000.png") as rendered:
        assert rendered.size == (480, 480)
        r, g, b = rendered.convert("RGB").getpixel((240, 240))
        assert r > 200 and b < 30

    shutil.rmtree(frame_dir)
    routes.processor.ensure_frames(item)
    with Image.open(frame_dir / "0000.png") as rebuilt:
        r, g, b = rebuilt.convert("RGB").getpixel((240, 240))
        assert r > 200 and b < 30


@pytest.mark.parametrize("crop", [
    '{"x":-0.1,"y":0,"w":0.5,"h":0.5}',
    '{"x":0.8,"y":0.2,"w":0.5,"h":0.5}',
    '{"x":0,"y":0,"w":0.001,"h":1}',
    '{"x":0,"y":0,"w":"NaN","h":1}',
    '{"x":0,"y":0,"w":1}',
    "not-json",
])
def test_upload_rejects_invalid_crop(client, crop):
    test_client, _ = client
    response = test_client.post(
        "/api/upload",
        files={"file": ("test.png", b"x", "image/png")},
        data={"crop": crop},
    )
    assert response.status_code == 422
