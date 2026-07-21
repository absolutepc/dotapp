#!/usr/bin/env bash
# Regenerate gallery JPEG previews from existing frame caches (no full re-encode).
# On Pi: cd ~/dotapp && bash scripts/refresh-previews.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"
export PYTHONPATH="${ROOT}${PYTHONPATH:+:${PYTHONPATH}}"
PY="${ROOT}/venv/bin/python"
[[ -x "${PY}" ]] || PY=python3
"${PY}" - <<'PY'
from firmware.media.processor import MediaProcessor
from firmware.media.storage import MediaStorage

storage = MediaStorage()
storage.register_builtin_assets()
processor = MediaProcessor(storage)
ok = 0
for item in storage.list_all():
    try:
        if not processor.frames_ready(item):
            print("build-frames", item.id)
            processor.ensure_frames(item)
        if processor.ensure_preview(item):
            print("ok", item.id)
            ok += 1
        else:
            print("skip", item.id)
    except Exception as exc:
        print("fail", item.id, exc)
print(f"done {ok} previews")
PY
