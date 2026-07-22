#!/usr/bin/env bash
# Regenerate gallery preview JPEGs (after preview algorithm updates).
# Usage: sudo bash scripts/refresh-previews.sh
set -euo pipefail

PREVIEW_DIR="${DOT_PREVIEW_DIR:-/var/lib/dot/previews}"
FRAMES_DIR="${DOT_FRAMES_DIR:-/var/lib/dot/frames}"

echo "Clearing preview thumbs in ${PREVIEW_DIR}…"
mkdir -p "${PREVIEW_DIR}"
rm -f "${PREVIEW_DIR}"/*.jpg "${PREVIEW_DIR}"/*.jpeg 2>/dev/null || true

# Force ensure_preview to rebuild (preview_version mismatch).
if [[ -d "${FRAMES_DIR}" ]]; then
  find "${FRAMES_DIR}" -name meta.json -print0 2>/dev/null | while IFS= read -r -d '' meta; do
    python3 - "${meta}" <<'PY' || true
import json, sys
path = sys.argv[1]
try:
    data = json.load(open(path))
except Exception:
    raise SystemExit(0)
data["preview_version"] = 0
open(path, "w").write(json.dumps(data, indent=2) + "\n")
PY
  done
fi

echo "Restarting API so new PREVIEW_VERSION is served…"
systemctl restart dot-api 2>/dev/null || systemctl restart bmw-api 2>/dev/null || true
echo "Done. Open the iOS gallery — thumbs rebuild on first request."
