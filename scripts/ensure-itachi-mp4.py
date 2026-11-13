#!/usr/bin/env python3
"""Regenerate assets/bmw/itachi.webm (3-tomoe → Mangekyou bloom).

Requires a reference rim/iris extract or the checked-in stills under
assets/bmw/src/. Prefer rebuilding from /tmp/itachi/build2 workflow if
reference GIF is available.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "assets/bmw/itachi.webm"
MP4 = ROOT / "assets/bmw/itachi.mp4"

def main() -> int:
    if not WEB.exists():
        print("Missing", WEB, file=sys.stderr)
        return 1
    # Ensure MP4 sibling for Safari/mockup
    if not MP4.exists() or MP4.stat().st_mtime < WEB.stat().st_mtime:
        subprocess.check_call([
            "ffmpeg", "-y", "-i", str(WEB),
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-an", str(MP4),
        ])
        print("wrote", MP4)
    else:
        print("ok", WEB, MP4)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
