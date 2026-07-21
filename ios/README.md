# Dot — iOS app

Native **SwiftUI** app for iPhone (iOS 16+).

## Open in Xcode

1. Create a new iOS App project named `Dot` (or any name) with SwiftUI lifecycle.
2. Replace generated sources with files from `ios/Dot/` (including `Views/OnboardingView.swift`, `Views/CachedAsyncImage.swift`, `Views/LastSeenLocationView.swift`, `Services/DotLocationTracker.swift`).
   - Keep only **one** `@main` app entry (use `DotApp.swift`; delete Xcode’s generated `*App.swift`).
3. Set **Info.plist** keys from `ios/Dot/Info.plist` (local network + location when in use + photo library + Allow Local Networking).
4. Set deployment target **iOS 16.0**.
5. Build and run on your iPhone (Developer Mode required on iOS 16+).

If Xcode reports `ObservableObject` / `@Published` errors, ensure `import Combine` is present in `PiAPIClient.swift` and `DotApp.swift`.

## Usage

1. **First launch:** the app shows 3 short onboarding slides (once; stored as `dot.onboarding.completed`).
2. **First Wi‑Fi:** join `Dot-Setup-…` on iPhone (Dot opens it after install), open **Настройка Wi‑Fi** → enter Personal Hotspot name/password.
3. **Every day:** enable Personal Hotspot → Dot joins → app auto-discovers via parallel probe / `*.local` / hotspot LAN.
4. Browse gallery, tap an item, **Apply to Display** (shows prepare progress if Dot is building frames). Custom photos → **Custom** tab.
5. **Где Dot** (toolbar pin): last place the iPhone saw Dot (phone GPS while connected). Shown in the Dot app and Apple Maps — **not** Apple Find My / Локатор (that requires Apple accessory certification).

The API host is saved in UserDefaults (`dot.api.host`). Preview images are cached under Caches/DotPreviews. Last-seen coordinates use `dot.lastSeen.v1`.

## Bundled vs Dot gallery

Built-in assets ship on Dot under `assets/`. The app loads the live gallery from `GET /api/gallery` after connecting.
