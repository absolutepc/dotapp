"""Tests for Dot firmware."""

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
    assert data["device"] == "dot"
    assert data["resolution"] == "480x480"
    assert data["brightness"] == 100


def test_brightness_get_set(client):
    test_client, _ = client
    got = test_client.get("/api/brightness")
    assert got.status_code == 200
    assert got.json()["brightness"] == 100

    set_resp = test_client.post("/api/brightness", json={"brightness": 42})
    assert set_resp.status_code == 200
    assert set_resp.json()["brightness"] == 42

    status = test_client.get("/api/status")
    assert status.json()["brightness"] == 42

    clamped = test_client.post("/api/brightness", json={"brightness": 1})
    assert clamped.status_code == 200
    assert clamped.json()["brightness"] == 5


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
    assert any(frame_dir.glob("*.jpg")) or any(frame_dir.glob("*.png"))


def test_display_returns_preparing_when_cold(client, monkeypatch):
    test_client, _ = client
    import firmware.api.routes as routes
    from firmware.media.storage import MediaItem

    item = MediaItem(
        id="cold-anim",
        name="Cold",
        type="animation",
        builtin=False,
        filename="cold.gif",
        frame_count=0,
        fps=12.0,
    )
    routes.storage.add(item)
    monkeypatch.setattr(routes.processor, "frames_ready", lambda _item: False)

    ran = {"ok": False}

    def fake_prepare(item_id: str) -> None:
        ran["ok"] = True
        routes.write_prepare_status(
            media_id=item_id,
            state="ready",
            message="Готово",
            progress=1.0,
        )
        routes.set_current_media(item_id, 12.0)

    monkeypatch.setattr(routes, "_prepare_and_show", fake_prepare)

    # Force Thread to run target inline so we don't race
    import threading

    class InlineThread(threading.Thread):
        def start(self):  # noqa: D401
            self.run()

    monkeypatch.setattr(routes.threading, "Thread", InlineThread)

    response = test_client.post("/api/display", json={"media_id": "cold-anim"})
    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["preparing"] is True
    assert ran["ok"] is True

    status = test_client.get("/api/display/status")
    assert status.status_code == 200
    assert status.json()["state"] == "ready"


def test_preview_picks_brighter_frame(client, tmp_path, monkeypatch):
    """Preview should not stay near-black when a later frame is brighter."""
    from PIL import Image

    import firmware.api.routes as routes
    from firmware.media.processor import PREVIEW_VERSION, MediaProcessor
    from firmware.media.storage import MediaItem

    frames = tmp_path / "frames" / "neon-demo"
    frames.mkdir(parents=True)
    # Frame 0 almost black, frame 5 bright logo-like
    Image.new("RGB", (480, 480), (2, 2, 2)).save(frames / "0000.jpg", quality=90)
    Image.new("RGB", (480, 480), (2, 2, 2)).save(frames / "0001.jpg", quality=90)
    bright = Image.new("RGB", (480, 480), (8, 8, 8))
    for y in range(180, 300):
        for x in range(180, 300):
            bright.putpixel((x, y), (220, 40, 40))
    bright.save(frames / "0002.jpg", quality=90)
    (frames / "meta.json").write_text(
        '{"durations":[0.1,0.1,0.1],"frame_count":3,"fps":10,'
        '"cache_version":7,"preview_version":0}',
        encoding="utf-8",
    )

    item = MediaItem(
        id="neon-demo",
        name="Neon",
        type="animation",
        builtin=False,
        filename="neon.gif",
        frame_count=3,
        fps=10.0,
    )
    routes.storage.add(item)
    assert routes.processor.ensure_preview(item) is True

    preview = tmp_path / "previews" / "neon-demo.jpg"
    assert preview.exists()
    meta = (frames / "meta.json").read_text(encoding="utf-8")
    assert f'"preview_version": {PREVIEW_VERSION}' in meta or f'"preview_version":{PREVIEW_VERSION}' in meta
    from PIL import ImageStat

    with Image.open(preview) as preview_im:
        rgb = preview_im.convert("RGB")
        w, h = rgb.size
        # Outside the circle is black by design — score the center logo area.
        center = rgb.crop((w // 4, h // 4, 3 * w // 4, 3 * h // 4))
        lum = sum(ImageStat.Stat(center).mean) / 3.0
    assert lum > 40, f"preview center still too dark: {lum}"


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


def test_wifi_configure_writes_request(client, tmp_path, monkeypatch):
    test_client, _ = client
    import firmware.api.wifi as wifi

    monkeypatch.setattr(wifi, "DATA_ROOT", tmp_path)
    monkeypatch.setattr(wifi, "WIFI_REQUEST", tmp_path / "wifi-request.json")
    monkeypatch.setattr(wifi, "WIFI_STATUS", tmp_path / "wifi-status.json")
    monkeypatch.setattr(wifi, "WIFI_MODE", tmp_path / "wifi-mode.json")
    monkeypatch.setattr(wifi, "WIFI_CLIENT", tmp_path / "wifi-client.json")
    monkeypatch.setattr(wifi, "_trigger_apply", lambda: None)

    bad = test_client.post("/api/wifi/configure", json={"ssid": "Phone", "password": "short"})
    assert bad.status_code == 422

    ok = test_client.post(
        "/api/wifi/configure",
        json={"ssid": "iPhone Hotspot", "password": "secret123"},
    )
    assert ok.status_code == 200
    assert (tmp_path / "wifi-request.json").exists()
    data = json.loads((tmp_path / "wifi-request.json").read_text(encoding="utf-8"))
    assert data["ssid"] == "iPhone Hotspot"
    assert data["password"] == "secret123"

    status = test_client.get("/api/wifi/status")
    assert status.status_code == 200
    assert status.json()["mode"] == "switching"


def test_wifi_reprovision_requires_confirm_and_client(client, tmp_path, monkeypatch):
    test_client, _ = client
    import firmware.api.wifi as wifi

    monkeypatch.setattr(wifi, "DATA_ROOT", tmp_path)
    monkeypatch.setattr(wifi, "WIFI_STATUS", tmp_path / "wifi-status.json")
    monkeypatch.setattr(wifi, "WIFI_MODE", tmp_path / "wifi-mode.json")
    monkeypatch.setattr(wifi, "WIFI_CLIENT", tmp_path / "wifi-client.json")
    monkeypatch.setattr(wifi, "_trigger_setup_ap", lambda: None)

    # No confirm flag
    missing = test_client.post("/api/wifi/reprovision", json={})
    assert missing.status_code == 400

    # Not on hotspot / client
    (tmp_path / "wifi-status.json").write_text(
        json.dumps({"ok": False, "mode": "setup_ap", "message": "setup"}),
        encoding="utf-8",
    )
    blocked = test_client.post("/api/wifi/reprovision", json={"confirm": True})
    assert blocked.status_code == 409

    # Client + confirm → ok, flips role to setup and stops client markers
    (tmp_path / "wifi-status.json").write_text(
        json.dumps({"ok": True, "mode": "client", "message": "on hotspot", "ip": "172.20.10.2"}),
        encoding="utf-8",
    )
    (tmp_path / "wifi-client.json").write_text(
        json.dumps({"ssid": "iPhone", "ip": "172.20.10.2"}),
        encoding="utf-8",
    )
    ok = test_client.post("/api/wifi/reprovision", json={"confirm": True})
    assert ok.status_code == 200
    assert ok.json()["ok"] is True
    assert (tmp_path / "wifi-role").read_text(encoding="utf-8").strip() == "setup"
    assert (tmp_path / "setup-ap-hold").exists()
    assert not (tmp_path / "wifi-client.json").exists()
    status = json.loads((tmp_path / "wifi-status.json").read_text(encoding="utf-8"))
    assert status["mode"] == "setup_ap"
    mode = json.loads((tmp_path / "wifi-mode.json").read_text(encoding="utf-8"))
    assert mode["mode"] == "setup_ap"
