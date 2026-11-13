#!/usr/bin/env bash
# Build a compact OTA tarball (VERSION + firmware + scripts + updates).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
DIST="$ROOT/dist"
STAGE="$DIST/dot-ota-${VERSION}"
OUT="$DIST/dot-ota-${VERSION}.tar.gz"

rm -rf "$STAGE"
mkdir -p "$STAGE"

cp "$ROOT/VERSION" "$STAGE/VERSION"
rsync -a --delete \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --exclude 'tests/' \
  "$ROOT/firmware/" "$STAGE/firmware/"
rsync -a \
  --exclude '__pycache__/' \
  "$ROOT/scripts/" "$STAGE/scripts/"
mkdir -p "$STAGE/updates"
cp "$ROOT/updates/manifest.json" "$STAGE/updates/manifest.json"

mkdir -p "$DIST"
tar -czf "$OUT" -C "$DIST" "dot-ota-${VERSION}"
SHA="$(sha256sum "$OUT" | awk '{print $1}')"
SIZE="$(wc -c < "$OUT" | tr -d ' ')"

echo "Wrote $OUT"
echo "version=$VERSION"
echo "sha256=$SHA"
echo "size_bytes=$SIZE"
echo "Update updates/manifest.json package_url / sha256 / size_bytes before publishing."
