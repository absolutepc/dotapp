# OTA updates (app → Dot)

Users install firmware updates from **Настройки** while the phone can reach Dot
(usually Dot on the iPhone hotspot — same link as the gallery).

## Flow

1. App fetches [`updates/manifest.json`](../updates/manifest.json) over the internet.
2. Compares `latest` to Dot `GET /api/status` → `version`.
3. User taps **Обновить** (Dot must be connected).
4. App downloads the package → uploads to Dot → Pi applies and restarts services.
5. Progress % in Settings: download / upload / install.

## Package

Build on a developer machine:

```bash
bash scripts/package-ota.sh
# → dist/dot-ota-<VERSION>.tar.gz + sha256 printed
```

Contents: `VERSION`, `firmware/`, `scripts/` (not full gallery assets).

Upload the tarball to GitHub Releases (or any HTTPS URL), then fill
`package_url`, `sha256`, `size_bytes` in `updates/manifest.json` and bump `latest`.

## Pi API

| Method | Path | Role |
|--------|------|------|
| GET | `/api/update/status` | Version + job progress |
| POST | `/api/update/upload` | Multipart `file` (+ optional `sha256`) |
| POST | `/api/update/apply` | Start install (background) |

Install script: [`scripts/apply-ota-update.sh`](../scripts/apply-ota-update.sh).

## Notes

- Upload limit: 100 MB (`MAX_OTA_BYTES`).
- `dot-api` restart is deferred so the HTTP response can finish.
- Keep a known-good checkout / SD image for recovery if an update fails.
