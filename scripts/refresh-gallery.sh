#!/usr/bin/env bash
# Regenerate built-in gallery and refresh manifest on the Pi.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

python3 scripts/generate_assets.py

# Clear manifest so new built-ins are registered
DATA_ROOT="${BMW_LOGO_DATA:-/var/lib/bmw-logo}"
if [[ -w "${DATA_ROOT}" || -w "${DATA_ROOT}/manifest.json" 2>/dev/null ]]; then
  rm -f "${DATA_ROOT}/manifest.json"
  rm -rf "${DATA_ROOT}/frames"/builtin-*
  rm -f "${DATA_ROOT}/previews"/builtin-*.jpg
fi

if systemctl is-active bmw-logo-api >/dev/null 2>&1; then
  sudo systemctl restart bmw-logo-api
  echo "Restarted bmw-logo-api"
fi

echo "Gallery refreshed. Open /api/gallery to verify."
