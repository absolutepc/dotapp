#!/usr/bin/env bash
set -euo pipefail

echo "=== Dot hardware smoke test ==="

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
TEST_IMAGE="${REPO_ROOT}/assets/bmw/anim3.webm"
# fbi needs a raster image; extract one frame if possible
TEST_FRAME="${REPO_ROOT}/assets/bmw/.hardware-test-frame.jpg"
if command -v ffmpeg >/dev/null 2>&1 && [[ -f "$TEST_IMAGE" ]]; then
  ffmpeg -y -i "$TEST_IMAGE" -vframes 1 "$TEST_FRAME" >/dev/null 2>&1 || true
fi
if [[ -f "$TEST_FRAME" ]]; then
  TEST_IMAGE="$TEST_FRAME"
elif [[ ! -f "$TEST_IMAGE" ]]; then
  echo "No test media found under assets/bmw/" >&2
  exit 1
fi

if command -v fbi >/dev/null 2>&1; then
  echo "Showing test image for 5 seconds..."
  timeout 5 fbi -T 1 -a "$TEST_IMAGE" || true
else
  echo "Install fbi to preview on HDMI: sudo apt install -y fbi"
fi

echo "=== Done. Verify round 480x480 image on display. ==="
