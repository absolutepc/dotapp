"""Wi-Fi provisioning: setup AP → join iPhone Personal Hotspot."""

from __future__ import annotations

import json
import logging
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from firmware.config import DATA_ROOT, REPO_ROOT

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/wifi", tags=["wifi"])

WIFI_REQUEST = DATA_ROOT / "wifi-request.json"
WIFI_STATUS = DATA_ROOT / "wifi-status.json"
WIFI_MODE = DATA_ROOT / "wifi-mode.json"
WIFI_CLIENT = DATA_ROOT / "wifi-client.json"
SETUP_DIR = REPO_ROOT / "firmware" / "static" / "setup"


class WifiConfigureRequest(BaseModel):
    ssid: str = Field(min_length=1, max_length=32)
    password: str = Field(min_length=8, max_length=63)


def _read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return {}


def _primary_ipv4() -> str | None:
    try:
        out = subprocess.check_output(
            [
                "bash",
                "-c",
                "ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1",
            ],
            text=True,
            timeout=3,
        ).strip()
        return out or None
    except Exception:  # noqa: BLE001
        return None


def _trigger_apply() -> None:
    """Ask root helpers to apply the pending wifi-request.json."""
    for cmd in (
        ["sudo", "-n", "/usr/local/sbin/dot-wifi-apply"],
        ["sudo", "-n", "systemctl", "start", "dot-wifi-apply.service"],
        ["systemctl", "start", "dot-wifi-apply.service"],
    ):
        try:
            subprocess.Popen(  # noqa: S603
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            return
        except Exception:  # noqa: BLE001
            continue
    logger.warning("Could not start wifi apply helper; relying on dot-wifi-apply.path")


def _trigger_setup_ap() -> None:
    """Re-enter Dot-Setup AP without SSH (for app /reprovision)."""
    for cmd in (
        ["sudo", "-n", "/usr/local/sbin/dot-enter-setup-ap"],
        ["sudo", "-n", "systemctl", "start", "dot-wifi-boot.service"],
    ):
        try:
            subprocess.Popen(  # noqa: S603
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            return
        except Exception:  # noqa: BLE001
            continue
    logger.warning("Could not start setup AP helper")


def _has_client_ssid() -> bool:
    client = _read_json(WIFI_CLIENT)
    return bool((client.get("ssid") or "").strip())


@router.get("/status")
def wifi_status() -> dict:
    status = _read_json(WIFI_STATUS)
    mode = _read_json(WIFI_MODE)
    client = _read_json(WIFI_CLIENT)
    resolved_mode = status.get("mode") or mode.get("mode") or "unknown"
    ip = status.get("ip") or client.get("ip") or mode.get("ip") or _primary_ipv4()
    needs_setup = resolved_mode == "setup_ap" or not _has_client_ssid()
    return {
        "mode": resolved_mode,
        "ok": bool(status.get("ok")) if status else False,
        "message": status.get("message") or mode.get("message"),
        "ssid": client.get("ssid") or mode.get("ssid"),
        "ip": ip,
        "updated_at": status.get("updated_at"),
        "setup_portal": "http://192.168.4.1/setup/",
        "needs_setup": needs_setup,
        "setup_ssid": mode.get("ssid") if resolved_mode == "setup_ap" else None,
    }


@router.post("/configure")
def wifi_configure(body: WifiConfigureRequest) -> dict:
    ssid = body.ssid.strip()
    if not ssid:
        raise HTTPException(status_code=400, detail="SSID is required")
    if len(body.password) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters")

    DATA_ROOT.mkdir(parents=True, exist_ok=True)
    payload = {
        "ssid": ssid,
        "password": body.password,
        "requested_at": datetime.now(timezone.utc).isoformat(),
    }
    tmp = DATA_ROOT / "wifi-request.json.tmp"
    tmp.write_text(json.dumps(payload), encoding="utf-8")
    os.chmod(tmp, 0o600)
    if WIFI_REQUEST.exists():
        WIFI_REQUEST.unlink()
    tmp.replace(WIFI_REQUEST)

    WIFI_STATUS.write_text(
        json.dumps(
            {
                "ok": False,
                "mode": "switching",
                "message": f"Joining «{ssid}»…",
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        + "\n",
        encoding="utf-8",
    )

    _trigger_apply()
    logger.info("Wi-Fi configure requested for ssid=%s", ssid)
    return {
        "ok": True,
        "message": "Сохранено. Pi выходит из сети настройки и подключается к точке iPhone…",
    }


@router.post("/reprovision")
def wifi_reprovision() -> dict:
    """Drop back into Dot-Setup AP so the user can re-enter hotspot credentials from the app."""
    DATA_ROOT.mkdir(parents=True, exist_ok=True)
    WIFI_STATUS.write_text(
        json.dumps(
            {
                "ok": False,
                "mode": "setup_ap",
                "message": "Re-entering setup AP…",
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        + "\n",
        encoding="utf-8",
    )
    _trigger_setup_ap()
    return {
        "ok": True,
        "message": "Pi открывает сеть Dot-Setup. Подключите iPhone к ней и снова введите Режим модема.",
        "setup_portal": "http://192.168.4.1/setup/",
    }


setup_pages = APIRouter(tags=["wifi-setup-ui"])


@setup_pages.get("/setup")
@setup_pages.get("/setup/")
def setup_index() -> FileResponse:
    index = SETUP_DIR / "index.html"
    if not index.is_file():
        raise HTTPException(status_code=404, detail="Setup page missing")
    return FileResponse(index)
