#!/usr/bin/env bash
set -euo pipefail

echo "=== BMW Logo hardware smoke test ==="

if command -v tvservice >/dev/null 2>&1; then
  echo "Display mode:"
  tvservice -s || true
else
  echo "tvservice not found (install raspberrypi-ui-mods or use fbset)"
fi

if command -v fbset >/dev/null 2>&1; then
  echo "Framebuffer:"
  fbset -s 2>/dev/null || true
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_IMAGE="${REPO_ROOT}/assets/bmw/default.gif"

if [[ ! -f "$TEST_IMAGE" ]]; then
  echo "Generating default test image..."
  python3 "${REPO_ROOT}/scripts/generate_assets.py"
fi

if command -v fbi >/dev/null 2>&1; then
  echo "Showing test image for 5 seconds..."
  timeout 5 fbi -T 1 -a "$TEST_IMAGE" || true
else
  echo "Install fbi to preview on HDMI: sudo apt install -y fbi"
fi

echo "=== Done. Verify round 480x480 image on display. ==="
