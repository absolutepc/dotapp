"""OTA update API — receive package from the iOS app and apply on device."""

from __future__ import annotations

import hashlib
import logging
import os
import subprocess
import threading
from pathlib import Path

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from pydantic import BaseModel

from firmware.config import MAX_OTA_BYTES, OTA_DIR, REPO_ROOT
from firmware.state import read_update_status, write_update_status
from firmware.version import read_version

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/update", tags=["update"])

_apply_lock = threading.Lock()
_APPLY_SCRIPT = REPO_ROOT / "scripts" / "apply-ota-update.sh"


class ApplyRequest(BaseModel):
    sha256: str | None = None
    version: str | None = None


def _ota_dir() -> Path:
    from firmware.config import DATA_ROOT as live_root

    path = live_root / "ota"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _package_path() -> Path:
    return _ota_dir() / "package.tar.gz"


@router.get("/status")
def update_status() -> dict:
    job = read_update_status()
    return {
        "ok": True,
        "version": read_version(),
        "state": job.get("state") or "idle",
        "message": job.get("message") or "",
        "progress": job.get("progress"),
        "phase": job.get("phase") or "",
        "target_version": job.get("version"),
    }


@router.post("/upload")
async def update_upload(
    file: UploadFile = File(...),
    sha256: str | None = Form(default=None),
    version: str | None = Form(default=None),
) -> dict:
    """Receive OTA tarball from the phone. Does not install yet."""
    job = read_update_status()
    if job.get("state") in {"installing", "restarting", "verifying"}:
        raise HTTPException(status_code=409, detail="Update already in progress")

    write_update_status(
        state="uploading",
        phase="upload",
        message="Получение пакета…",
        progress=0.05,
        version=version,
    )

    dest = _package_path()
    tmp = dest.with_suffix(".partial")
    hasher = hashlib.sha256()
    total = 0
    try:
        with tmp.open("wb") as out:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > MAX_OTA_BYTES:
                    raise HTTPException(status_code=413, detail="OTA package too large")
                hasher.update(chunk)
                out.write(chunk)
                # Rough receive progress up to 0.55 (phone also tracks upload %).
                pct = min(0.55, 0.05 + (total / max(MAX_OTA_BYTES, 1)) * 0.5)
                write_update_status(
                    state="uploading",
                    phase="upload",
                    message=f"Получено {total // (1024 * 1024)} МБ…",
                    progress=pct,
                    version=version,
                )
        digest = hasher.hexdigest()
        if sha256:
            expected = sha256.strip().lower()
            if expected and digest != expected:
                tmp.unlink(missing_ok=True)
                write_update_status(
                    state="error",
                    phase="verify",
                    message="SHA-256 не совпал",
                    progress=None,
                    version=version,
                )
                raise HTTPException(status_code=400, detail="SHA-256 mismatch")

        tmp.replace(dest)
        write_update_status(
            state="idle",
            phase="uploaded",
            message="Пакет загружен на Dot",
            progress=0.6,
            version=version,
        )
        return {
            "ok": True,
            "bytes": total,
            "sha256": digest,
            "path": str(dest),
            "version": version,
        }
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        logger.exception("OTA upload failed")
        tmp.unlink(missing_ok=True)
        write_update_status(
            state="error",
            phase="upload",
            message=str(exc),
            progress=None,
            version=version,
        )
        raise HTTPException(status_code=500, detail="Upload failed") from exc


def _run_apply(archive: Path, version: str | None) -> None:
    if not _apply_lock.acquire(blocking=False):
        write_update_status(
            state="error",
            phase="install",
            message="Установка уже выполняется",
            progress=None,
            version=version,
        )
        return
    try:
        write_update_status(
            state="verifying",
            phase="verify",
            message="Проверка пакета…",
            progress=0.65,
            version=version,
        )
        if not archive.is_file():
            write_update_status(
                state="error",
                phase="verify",
                message="Файл пакета не найден",
                progress=None,
                version=version,
            )
            return

        write_update_status(
            state="installing",
            phase="install",
            message="Установка на Dot…",
            progress=0.75,
            version=version,
        )

        script = _APPLY_SCRIPT
        if not script.is_file():
            write_update_status(
                state="error",
                phase="install",
                message="Скрипт установки не найден",
                progress=None,
                version=version,
            )
            return

        env = os.environ.copy()
        env["DOT_REPO"] = str(REPO_ROOT)
        env["DOT_OTA_VERSION"] = version or ""
        # Progress marker file the script can update (optional).
        progress_file = _ota_dir() / "apply-progress.txt"
        env["DOT_OTA_PROGRESS_FILE"] = str(progress_file)

        write_update_status(
            state="installing",
            phase="install",
            message="Распаковка и замена файлов…",
            progress=0.82,
            version=version,
        )

        proc = subprocess.run(
            ["bash", str(script), str(archive)],
            check=False,
            capture_output=True,
            text=True,
            env=env,
            timeout=600,
        )
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout or "apply failed").strip()[-400:]
            logger.error("OTA apply failed: %s", detail)
            write_update_status(
                state="error",
                phase="install",
                message=detail or "Ошибка установки",
                progress=None,
                version=version,
            )
            return

        write_update_status(
            state="restarting",
            phase="restart",
            message="Перезапуск сервисов Dot…",
            progress=0.95,
            version=version,
        )
        # Script schedules deferred restart; mark done so the app can reconnect.
        write_update_status(
            state="done",
            phase="done",
            message="Обновление установлено. Переподключитесь к Dot.",
            progress=1.0,
            version=version or read_version(),
        )
    except Exception as exc:  # noqa: BLE001
        logger.exception("OTA apply crashed")
        write_update_status(
            state="error",
            phase="install",
            message=str(exc),
            progress=None,
            version=version,
        )
    finally:
        _apply_lock.release()


@router.post("/apply")
def update_apply(req: ApplyRequest | None = None) -> dict:
    """Start background install of the uploaded package."""
    req = req or ApplyRequest()
    job = read_update_status()
    if job.get("state") in {"installing", "restarting", "verifying"}:
        raise HTTPException(status_code=409, detail="Update already in progress")

    archive = _package_path()
    if not archive.is_file():
        raise HTTPException(status_code=400, detail="No package uploaded")

    if req.sha256:
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != req.sha256.strip().lower():
            raise HTTPException(status_code=400, detail="SHA-256 mismatch")

    version = req.version
    threading.Thread(
        target=_run_apply,
        args=(archive, version),
        name="dot-ota-apply",
        daemon=True,
    ).start()

    write_update_status(
        state="verifying",
        phase="verify",
        message="Запуск установки…",
        progress=0.62,
        version=version,
    )
    return {"ok": True, "started": True, "version": version}
