#!/usr/bin/env bash
# Apply an OTA tarball onto the Dot checkout, then deferred-restart services.
# Usage: bash scripts/apply-ota-update.sh /path/to/package.tar.gz
set -euo pipefail

ARCHIVE="${1:?package.tar.gz required}"
REPO="${DOT_REPO:-}"
if [[ -z "$REPO" ]]; then
  REPO="$(cd "$(dirname "$0")/.." && pwd)"
fi
REPO="$(cd "$REPO" && pwd)"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "archive not found: $ARCHIVE" >&2
  exit 1
fi

STAGING="$(mktemp -d /tmp/dot-ota-XXXXXX)"
cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

echo "Extracting into $STAGING"
tar -xzf "$ARCHIVE" -C "$STAGING"

# Allow either flat layout (VERSION at root) or nested single folder.
ROOT="$STAGING"
if [[ ! -f "$ROOT/VERSION" ]]; then
  # one top-level dir
  child="$(find "$STAGING" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"
  if [[ -n "$child" && -f "$child/VERSION" ]]; then
    ROOT="$child"
  fi
fi

if [[ ! -f "$ROOT/VERSION" || ! -d "$ROOT/firmware" ]]; then
  echo "invalid package: need VERSION + firmware/" >&2
  exit 1
fi

echo "Installing into $REPO (version $(cat "$ROOT/VERSION"))"
install -m 0644 "$ROOT/VERSION" "$REPO/VERSION"
rsync -a --delete \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  "$ROOT/firmware/" "$REPO/firmware/"

if [[ -d "$ROOT/scripts" ]]; then
  rsync -a "$ROOT/scripts/" "$REPO/scripts/"
fi

if [[ -d "$ROOT/updates" ]]; then
  mkdir -p "$REPO/updates"
  rsync -a "$ROOT/updates/" "$REPO/updates/"
fi

# Optional: refresh systemd unit paths if helper exists.
if [[ -x "$REPO/scripts/fix-systemd-paths.sh" ]]; then
  bash "$REPO/scripts/fix-systemd-paths.sh" || true
fi

# Deferred restart so the HTTP handler can finish responding.
restart_cmd='systemctl daemon-reload; systemctl restart dot-api; systemctl restart dot-display 2>/dev/null || systemctl restart dot-display-kiosk 2>/dev/null || true'
if command -v systemd-run >/dev/null 2>&1; then
  systemd-run --on-active=2s --unit=dot-ota-restart.service /bin/bash -lc "$restart_cmd" || \
    (nohup bash -lc "sleep 2; $restart_cmd" >/dev/null 2>&1 &)
else
  nohup bash -lc "sleep 2; $restart_cmd" >/dev/null 2>&1 &
fi

echo "OTA apply scheduled"
exit 0
