"""FastAPI entrypoint for BMW Logo Raspberry Pi service."""

from fastapi import FastAPI

from firmware.api.routes import router

app = FastAPI(title="BMW Logo API", version="1.0.0")
app.include_router(router)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}
