"""FastAPI entrypoint for Dot Raspberry Pi service."""

import json
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

from firmware.api.routes import router
from firmware.api.wifi import router as wifi_router
from firmware.api.wifi import setup_pages
from firmware.config import BUILTIN_ASSETS, DATA_ROOT, REPO_ROOT

app = FastAPI(title="Dot API", version="1.0.0")
app.include_router(router)
app.include_router(wifi_router)
app.include_router(setup_pages)

MOCKUP_DIR = REPO_ROOT / "ios" / "mockup"
SETUP_DIR = REPO_ROOT / "firmware" / "static" / "setup"
if BUILTIN_ASSETS.is_dir():
    app.mount("/assets", StaticFiles(directory=str(BUILTIN_ASSETS)), name="assets")
if MOCKUP_DIR.is_dir():
    app.mount("/mockup", StaticFiles(directory=str(MOCKUP_DIR), html=True), name="mockup")


def _wifi_mode() -> str | None:
    path = DATA_ROOT / "wifi-mode.json"
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("mode")
    except Exception:  # noqa: BLE001
        return None


@app.get("/")
def root() -> RedirectResponse:
    if _wifi_mode() == "setup_ap" and (SETUP_DIR / "index.html").exists():
        return RedirectResponse(url="/setup/")
    if (MOCKUP_DIR / "index.html").exists():
        return RedirectResponse(url="/mockup/")
    return RedirectResponse(url="/api/status")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}
