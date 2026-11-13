#!/usr/bin/env bash
# Apply / restore Dot 480×480 HDMI timing in config.txt
# Run on Pi: sudo bash scripts/fix-hdmi-480.sh [--offset]
#
# Default: hdmi_cvt=480 480 …
# --offset: use hdmi_timings fallback when part of the round panel is blank/shifted
set -euo pipefail

OFFSET=0
if [[ "${1:-}" == "--offset" ]]; then
  OFFSET=1
fi

CONFIG="/boot/firmware/config.txt"
[[ -f "${CONFIG}" ]] || CONFIG="/boot/config.txt"
if [[ ! -f "${CONFIG}" ]]; then
  echo "ERROR: config.txt not found" >&2
  exit 1
fi

cp -a "${CONFIG}" "${CONFIG}.bak.dot.$(date +%Y%m%d%H%M%S)"

# Strip previous Dot HDMI blocks (commented or not)
python3 - "${CONFIG}" "${OFFSET}" <<'PY'
import re, sys
from pathlib import Path

path = Path(sys.argv[1])
offset = sys.argv[2] == "1"
text = path.read_text(encoding="utf-8", errors="replace")

# Remove marked Dot block
text = re.sub(
    r"\n?#\s*---\s*Dot round[\s\S]*?#\s*---\s*end Dot HDMI\s*---\s*",
    "\n",
    text,
    flags=re.IGNORECASE,
)
# Also drop bare known keys we own (avoid duplicates)
drop_prefixes = (
    "hdmi_force_hotplug=",
    "hdmi_group=",
    "hdmi_mode=",
    "hdmi_cvt=",
    "hdmi_timings=",
    "hdmi_drive=",
    "config_hdmi_boost=",
    "framebuffer_width=",
    "framebuffer_height=",
)
lines = []
for line in text.splitlines():
    raw = line.strip()
    bare = raw.lstrip("#").strip()
    if any(bare.startswith(p) for p in drop_prefixes):
        # keep unrelated commented history? drop to avoid conflict
        continue
    if bare.startswith("max_usb_current=") or bare.startswith("gpu_mem="):
        # only remove if it was part of our block; keep user's other gpu_mem if unsure
        # Safer: leave gpu_mem/max_usb alone unless inside our block (already stripped)
        pass
    lines.append(line)
text = "\n".join(lines).rstrip() + "\n"

if offset:
    block = """
# --- Dot round 480x480 @ 60Hz (UEDX6911-HDMI) offset-fix ---
hdmi_force_hotplug=1
hdmi_group=2
hdmi_mode=87
hdmi_timings=480 1 10 20 50 480 1 10 10 5 0 0 0 60 0 16960000 4
hdmi_drive=2
config_hdmi_boost=7
max_usb_current=1
framebuffer_width=480
framebuffer_height=480
gpu_mem=128
# --- end Dot HDMI ---
"""
else:
    block = """
# --- Dot round 480x480 @ 60Hz (UEDX6911-HDMI) ---
hdmi_force_hotplug=1
hdmi_group=2
hdmi_mode=87
hdmi_cvt=480 480 60 4 0 0 0
hdmi_drive=2
config_hdmi_boost=7
max_usb_current=1
framebuffer_width=480
framebuffer_height=480
gpu_mem=128
# --- end Dot HDMI ---
"""

path.write_text(text + "\n" + block.lstrip("\n"), encoding="utf-8")
print(f"Updated {path} (offset={offset})")
print("--- Dot HDMI block ---")
print(block)
PY

echo ""
echo "Reboot required for HDMI timing: sudo reboot"
echo "If part of the circle is still blank after reboot:"
echo "  sudo bash scripts/fix-hdmi-480.sh --offset && sudo reboot"
