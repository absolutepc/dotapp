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
WIFI_PENDING = DATA_ROOT / "wifi-pending.json"
WIFI_STATUS = DATA_ROOT / "wifi-status.json"
WIFI_MODE = DATA_ROOT / "wifi-mode.json"
WIFI_CLIENT = DATA_ROOT / "wifi-client.json"
SETUP_DIR = REPO_ROOT / "firmware" / "static" / "setup"


class WifiConfigureRequest(BaseModel):
    ssid: str = Field(min_length=1, max_length=32)
    password: str = Field(min_length=8, max_length=63)
    # False (default): only store credentials while still on Dot-Setup.
    # True: also tear down Setup AP and join immediately (legacy one-shot portal).
    apply_now: bool = False


class WifiReprovisionRequest(BaseModel):
    """Require an explicit confirm flag so accidental taps cannot reset Wi‑Fi."""

    confirm: bool = False


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


def _mdns_hosts() -> list[str]:
    hosts = ["dot.local"]
    try:
        import socket

        name = socket.gethostname().strip().split(".")[0]
        if name:
            hosts.append(f"{name}.local")
    except Exception:  # noqa: BLE001
        pass
    seen: set[str] = set()
    out: list[str] = []
    for h in hosts:
        key = h.lower()
        if key not in seen:
            seen.add(key)
            out.append(h)
    return out


def _has_client_ssid() -> bool:
    client = _read_json(WIFI_CLIENT)
    return bool((client.get("ssid") or "").strip())


def _trigger_apply() -> None:
    """Ask root helpers to apply the pending wifi-request.json.

    Prefer a single systemd start. The apply script uses flock so a second
    trigger (path unit) cannot run two joins at once and flap the hotspot.
    """
    for cmd in (
        ["sudo", "-n", "systemctl", "start", "dot-wifi-apply.service"],
        ["systemctl", "start", "dot-wifi-apply.service"],
        ["sudo", "-n", "/usr/local/sbin/dot-wifi-apply"],
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


@router.get("/status")
def wifi_status() -> dict:
    status = _read_json(WIFI_STATUS)
    mode = _read_json(WIFI_MODE)
    client = _read_json(WIFI_CLIENT)
    status_mode = (status.get("mode") or "").strip()
    file_mode = (mode.get("mode") or "").strip()
    # Prefer live setup_ap from mode file over a stale "error" left by a failed join.
    if file_mode == "setup_ap" and status_mode in ("", "error", "switching", "unknown"):
        resolved_mode = "setup_ap"
    else:
        resolved_mode = status_mode or file_mode or "unknown"
    ip = status.get("ip") or client.get("ip") or mode.get("ip") or _primary_ipv4()
    if resolved_mode == "setup_ap":
        ip = mode.get("ip") or ip or "192.168.4.1"
    needs_setup = resolved_mode == "setup_ap" or not _has_client_ssid()
    setup_ssid = mode.get("ssid") if resolved_mode == "setup_ap" else None
    message = status.get("message") or mode.get("message")
    if resolved_mode == "setup_ap" and setup_ssid:
        message = mode.get("message") or f"Setup AP ready: {setup_ssid}"
    return {
        "mode": resolved_mode,
        "ok": True if resolved_mode == "setup_ap" else (bool(status.get("ok")) if status else False),
        "message": message,
        "ssid": client.get("ssid") or mode.get("ssid"),
        "ip": ip,
        "updated_at": status.get("updated_at"),
        "setup_portal": "http://192.168.4.1/setup/",
        "needs_setup": needs_setup,
        "setup_ssid": setup_ssid,
        "mdns_hosts": _mdns_hosts(),
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
    # Always keep a pending copy (step wizard: save while still on Setup AP).
    pending_tmp = DATA_ROOT / "wifi-pending.json.tmp"
    pending_tmp.write_text(json.dumps(payload), encoding="utf-8")
    os.chmod(pending_tmp, 0o600)
    pending_tmp.replace(WIFI_PENDING)

    if not body.apply_now:
        WIFI_STATUS.write_text(
            json.dumps(
                {
                    "ok": True,
                    "mode": "setup_ap",
                    "message": f"Credentials saved for «{ssid}». Enable Personal Hotspot, then connect.",
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                }
            )
            + "\n",
            encoding="utf-8",
        )
        logger.info("Wi-Fi credentials pending for ssid=%s (apply deferred)", ssid)
        return {
            "ok": True,
            "deferred": True,
            "message": "Данные сохранены. Dot остаётся в Dot-Setup. Дальше выйдите из Dot-Setup, включите Режим модема и нажмите «Подключить».",
        }

    _queue_apply(payload)
    logger.info("Wi-Fi configure+apply requested for ssid=%s", ssid)
    return {
        "ok": True,
        "deferred": False,
        "message": "Сохранено. Dot выходит из сети настройки и подключается к точке iPhone…",
    }


@router.post("/connect-hotspot")
def wifi_connect_hotspot() -> dict:
    """Apply previously saved credentials (after user is ready to leave Setup AP)."""
    pending = _read_json(WIFI_PENDING)
    ssid = (pending.get("ssid") or "").strip()
    password = pending.get("password") or ""
    if not ssid or len(password) < 8:
        raise HTTPException(
            status_code=400,
            detail="No saved hotspot credentials. Complete step «имя и пароль модема» first.",
        )
    payload = {
        "ssid": ssid,
        "password": password,
        "requested_at": datetime.now(timezone.utc).isoformat(),
    }
    _queue_apply(payload)
    # Prefer the dedicated use-hotspot helper (exits Setup AP + retries join).
    for cmd in (
        ["sudo", "-n", "/usr/local/sbin/dot-wifi-use-hotspot"],
        ["sudo", "-n", "systemctl", "start", "dot-wifi-watch.service"],
    ):
        try:
            subprocess.Popen(  # noqa: S603
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception:  # noqa: BLE001
            continue
    logger.info("Wi-Fi connect-hotspot for ssid=%s", ssid)
    return {
        "ok": True,
        "message": "Dot выходит из Dot-Setup и подключается к модему. Включите Режим модема на iPhone.",
    }


def _queue_apply(payload: dict) -> None:
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
                "message": f"Joining «{payload.get('ssid')}»…",
                "updated_at": datetime.now(timezone.utc).isoformat(),
            }
        )
        + "\n",
        encoding="utf-8",
    )
    _trigger_apply()


@router.post("/reprovision")
def wifi_reprovision(req: WifiReprovisionRequest) -> dict:
    """Drop back into Dot-Setup AP so the user can re-enter hotspot credentials from the app.

    Guardrails:
    - Body must include ``{"confirm": true}`` (blocks accidental calls).
    - Dot must currently be in client mode on the phone hotspot — otherwise
      there is no reliable path to talk to Dot after the reset.
    """
    if not req.confirm:
        raise HTTPException(
            status_code=400,
            detail="Нужно явное подтверждение: отправьте {\"confirm\": true}.",
        )

    live = wifi_status()
    mode = (live.get("mode") or "").strip()
    if mode != "client" or not live.get("ok"):
        raise HTTPException(
            status_code=409,
            detail=(
                "Сброс в Dot-Setup доступен только когда Dot подключён к точке доступа "
                "(Режим модема), mode=client. Включите модем, найдите Dot и повторите."
            ),
        )

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
        "message": "Dot открывает сеть Dot-Setup. Подключите iPhone к ней и снова введите Режим модема.",
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
