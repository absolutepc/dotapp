#!/usr/bin/env bash
# Recompress gallery assets safely (does NOT delete custom files / does NOT run generate_assets).
# - emoji PNG → optimized JPEG siblings not used; rewrites PNG with optimize
# - bmw MP4 → re-encode H.264 CRF 28 if larger savings (keeps WebM as source backup)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EMOJI="${ROOT}/assets/emoji"
BMW="${ROOT}/assets/bmw"

echo "Optimizing emoji PNGs…"
python3 - <<'PY' "${EMOJI}"
import sys
from pathlib import Path
from PIL import Image

root = Path(sys.argv[1])
saved = 0
for path in sorted(root.glob("*.png")):
    before = path.stat().st_size
    with Image.open(path) as im:
        im = im.convert("RGBA") if im.mode in {"P", "RGBA"} else im.convert("RGB")
        tmp = path.with_suffix(".tmp.png")
        if im.mode == "RGBA":
            im.save(tmp, optimize=True)
        else:
            im.save(tmp, optimize=True)
    after = tmp.stat().st_size
    if after < before:
        tmp.replace(path)
        saved += before - after
        print(f"  {path.name}: {before} → {after}")
    else:
        tmp.unlink(missing_ok=True)
print(f"emoji saved ≈ {saved} bytes")
PY

if command -v ffmpeg >/dev/null 2>&1; then
  echo "Recompressing BMW MP4 (CRF 28, keep if smaller)…"
  for mp4 in "${BMW}"/*.mp4; do
    [[ -f "${mp4}" ]] || continue
    tmp="${mp4}.opt.mp4"
    before=$(stat -c%s "${mp4}" 2>/dev/null || stat -f%z "${mp4}")
    if ffmpeg -y -hide_banner -loglevel error -i "${mp4}" \
      -an -c:v libx264 -preset veryfast -crf 28 -pix_fmt yuv420p \
      -movflags +faststart "${tmp}"; then
      after=$(stat -c%s "${tmp}" 2>/dev/null || stat -f%z "${tmp}")
      if [[ "${after}" -lt "${before}" ]]; then
        mv -f "${tmp}" "${mp4}"
        echo "  $(basename "${mp4}"): ${before} → ${after}"
      else
        rm -f "${tmp}"
        echo "  $(basename "${mp4}"): keep original (${before})"
      fi
    else
      rm -f "${tmp}"
      echo "  $(basename "${mp4}"): ffmpeg failed — skipped"
    fi
  done
else
  echo "ffmpeg not found — skipped MP4 recompress"
fi

echo "Done. Review git diff before commit."
du -sh "${EMOJI}" "${BMW}" 2>/dev/null || true
