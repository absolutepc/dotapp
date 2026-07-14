"""FastAPI entrypoint for BMW Logo Raspberry Pi service."""

from fastapi import FastAPI
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

from firmware.api.routes import router
from firmware.config import BUILTIN_ASSETS, REPO_ROOT

app = FastAPI(title="BMW Logo API", version="1.0.0")
app.include_router(router)

MOCKUP_DIR = REPO_ROOT / "ios" / "mockup"
if BUILTIN_ASSETS.is_dir():
    app.mount("/assets", StaticFiles(directory=str(BUILTIN_ASSETS)), name="assets")
if MOCKUP_DIR.is_dir():
    app.mount("/mockup", StaticFiles(directory=str(MOCKUP_DIR), html=True), name="mockup")


@app.get("/")
def root() -> RedirectResponse:
    if (MOCKUP_DIR / "index.html").exists():
        return RedirectResponse(url="/mockup/")
    return RedirectResponse(url="/api/status")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}
