# Dot — iOS app

Native **SwiftUI** app for iPhone (iOS 16+).

## Open in Xcode

1. Create a new iOS App project named `Dot` (or any name) with SwiftUI lifecycle.
2. Replace generated sources with files from `ios/Dot/` (including `Theme/DotTheme.swift`, `Views/OnboardingView.swift`, `Views/SettingsView.swift`, `Views/CachedAsyncImage.swift`, `Views/LastSeenLocationView.swift`, `Services/DotLocationTracker.swift`).
   - Keep only **one** `@main` app entry (use `DotApp.swift`; delete Xcode’s generated `*App.swift`).
3. Set **Info.plist** keys from `ios/Dot/Info.plist` (local network + location when in use + photo library + Allow Local Networking).
   - Prefer editing the target’s **Info** tab (or custom keys) — do **not** also add `ios/Dot/Info.plist` to **Copy Bundle Resources**.
   - If build fails with `Multiple commands produce …/Info.plist`: Target → **Build Phases** → **Copy Bundle Resources** → remove `Info.plist`. Then **Product → Clean Build Folder** and rebuild.
4. Set deployment target **iOS 16.0**.
5. Build and run on your iPhone (Developer Mode required on iOS 16+).

If Xcode reports `ObservableObject` / `@Published` errors, ensure `import Combine` is present in `PiAPIClient.swift` and `DotApp.swift`.

## Usage

1. **First launch (onboarding slides):** shown once per iPhone install, flag `UserDefaults` key `dot.onboarding.completed`. To see them again: **Настройки → Показать введение**, or connection screen → **Показать введение**.
2. **First Wi‑Fi pairing (Dot device):** while Dot is in `wifi-role=setup`, join `Dot-Setup-…`, run the in-app Wi‑Fi wizard, then enable Personal Hotspot. Dot switches to `wifi-role=client`.
3. **Every later day:** enable Personal Hotspot → Dot joins alone (boot + watch) → open app → **Найти автоматически** (probes saved IP, `dot.local`, `172.20.10.x`). No Setup AP needed.
4. Browse gallery: **top half** = selected animation + send-to-Dot; **bottom** = library grid. Theme (`Theme/DotTheme.swift`): **dark** = deeper space-blue; **light** = plain white. Toolbar sun/moon toggles (`dot.appearance.dark`, default dark).
5. **Настройки** (toolbar gear): brightness slider for the round display, theme, device info, Wi‑Fi wizard, **reset to Dot-Setup** (only while Dot is on Personal Hotspot / `mode=client`, with typed confirmation `СБРОС`), clear saved address, re-show intro.
6. **Где Dot** (toolbar pin): last place the iPhone saw Dot while connected — **not** Apple Find My.

### How the app knows “first” vs “later”

| What | Where stored | Meaning |
|------|----------------|---------|
| Onboarding slides done | iPhone `dot.onboarding.completed` | User saw intro slides |
| Saved Dot address | iPhone `dot.api.host` + mDNS cache | Faster rediscovery |
| Modem paired | Dot `/var/lib/dot/wifi-role` = `client` + NM profile `dot-phone-hotspot`; iPhone `dot.wifi.paired` | Auto-join hotspot; connection screen shows day-to-day steps first |
| Needs pairing UI | Dot API `mode=setup_ap` only | App opens Wi‑Fi wizard (not merely `needs_setup`) |

The app does **not** store a separate “first connection” boolean for Wi‑Fi: it asks Dot’s `/api/wifi/status`. If Dot is `client` and reachable on the hotspot LAN → gallery. If `setup_ap` → wizard.

## Bundled vs Dot gallery

Built-in assets ship on Dot under `assets/`. The app loads the live gallery from `GET /api/gallery` after connecting.
