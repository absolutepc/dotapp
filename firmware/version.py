"""Firmware / OTA version helpers."""

from __future__ import annotations

from pathlib import Path

from firmware.config import REPO_ROOT


def read_version() -> str:
    path = REPO_ROOT / "VERSION"
    if path.is_file():
        text = path.read_text(encoding="utf-8").strip()
        if text:
            return text.splitlines()[0].strip()
    return "0.0.0"


def compare_versions(a: str, b: str) -> int:
    """Return -1 if a<b, 0 if equal, 1 if a>b (semver-ish numeric parts)."""

    def parts(v: str) -> list[int]:
        out: list[int] = []
        for chunk in v.strip().lstrip("v").split("."):
            num = ""
            for ch in chunk:
                if ch.isdigit():
                    num += ch
                else:
                    break
            out.append(int(num) if num else 0)
        return out or [0]

    pa, pb = parts(a), parts(b)
    n = max(len(pa), len(pb))
    pa += [0] * (n - len(pa))
    pb += [0] * (n - len(pb))
    if pa < pb:
        return -1
    if pa > pb:
        return 1
    return 0
