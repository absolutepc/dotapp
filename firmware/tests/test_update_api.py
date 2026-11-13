"""OTA update API tests."""

from __future__ import annotations

import io
import tarfile
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from firmware.config import REPO_ROOT
from firmware.main import app
from firmware.media.processor import MediaProcessor
from firmware.media.storage import MediaStorage


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr("firmware.config.DATA_ROOT", tmp_path)
    monkeypatch.setattr("firmware.config.MEDIA_DIR", tmp_path / "media")
    monkeypatch.setattr("firmware.config.FRAMES_DIR", tmp_path / "frames")
    monkeypatch.setattr("firmware.config.PREVIEW_DIR", tmp_path / "previews")
    monkeypatch.setattr("firmware.config.STATE_DIR", tmp_path / "state")
    monkeypatch.setattr("firmware.state.STATE_DIR", tmp_path / "state")
    monkeypatch.setattr("firmware.config.MANIFEST_FILE", tmp_path / "manifest.json")
    monkeypatch.setattr("firmware.config.OTA_DIR", tmp_path / "ota")
    current = tmp_path / "state" / "current.json"
    monkeypatch.setattr("firmware.config.CURRENT_MEDIA_FILE", current)
    monkeypatch.setattr("firmware.state.CURRENT_MEDIA_FILE", current)
    monkeypatch.setattr("firmware.config.BUILTIN_ASSETS", REPO_ROOT / "assets")

    import firmware.api.routes as routes

    routes.storage = MediaStorage()
    routes.processor = MediaProcessor(routes.storage)

    # Point apply script at a no-op for unit tests.
    noop = tmp_path / "noop-apply.sh"
    noop.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    noop.chmod(0o755)
    monkeypatch.setattr("firmware.api.update._APPLY_SCRIPT", noop)

    return TestClient(app), tmp_path


def _tiny_package() -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        info = tarfile.TarInfo(name="VERSION")
        data = b"1.1.0\n"
        info.size = len(data)
        tar.addfile(info, io.BytesIO(data))
        # minimal firmware marker
        info2 = tarfile.TarInfo(name="firmware/.keep")
        info2.size = 0
        tar.addfile(info2, io.BytesIO(b""))
    return buf.getvalue()


def test_status_includes_version(client):
    test_client, _ = client
    response = test_client.get("/api/status")
    assert response.status_code == 200
    assert "version" in response.json()
    assert response.json()["version"]


def test_update_status_idle(client):
    test_client, _ = client
    response = test_client.get("/api/update/status")
    assert response.status_code == 200
    data = response.json()
    assert data["ok"] is True
    assert data["state"] == "idle"
    assert data["version"]


def test_update_upload_and_apply(client):
    test_client, tmp_path = client
    payload = _tiny_package()
    upload = test_client.post(
        "/api/update/upload",
        files={"file": ("dot-ota.tar.gz", payload, "application/gzip")},
        data={"version": "1.1.0"},
    )
    assert upload.status_code == 200
    body = upload.json()
    assert body["ok"] is True
    assert body["bytes"] == len(payload)
    assert (tmp_path / "ota" / "package.tar.gz").is_file()

    apply = test_client.post("/api/update/apply", json={"version": "1.1.0"})
    assert apply.status_code == 200
    assert apply.json()["started"] is True

    # Background thread should finish quickly with noop script.
    import time

    for _ in range(40):
        status = test_client.get("/api/update/status").json()
        if status["state"] in {"done", "error"}:
            break
        time.sleep(0.05)
    assert status["state"] == "done"
