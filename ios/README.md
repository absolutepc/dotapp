# Dot — iOS app

Native **SwiftUI** app for iPhone (iOS 16+).

## Open in Xcode

1. Create a new iOS App project named `Dot` (or any name) with SwiftUI lifecycle.
2. Replace generated sources with files from `ios/Dot/`.
   - Keep only **one** `@main` app entry (use `DotApp.swift`; delete Xcode’s generated `*App.swift`).
3. Set **Info.plist** keys from `ios/Dot/Info.plist` (local network + photo library + Allow Local Networking).
4. Set deployment target **iOS 16.0**.
5. Build and run on your iPhone (Developer Mode required on iOS 16+).

If Xcode reports `ObservableObject` / `@Published` errors, ensure `import Combine` is present in `PiAPIClient.swift` and `DotApp.swift`.

## Usage

1. Prefer **Personal Hotspot** mode (see [docs/wifi-provision.md](../docs/wifi-provision.md)): enable hotspot, wait for Pi to join, open the app.
2. Or use one-time setup portal at `http://192.168.4.1/setup/` while on `Dot-Setup-XXXX`.
3. Browse Gallery / Emoji / My Media, tap an item, **Apply to Display**.

## Bundled vs Pi gallery

Built-in assets ship on the Pi under `assets/`. The app loads the live gallery from `GET /api/gallery` after connecting.
