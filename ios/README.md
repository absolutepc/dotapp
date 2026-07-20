# BMW Logo — iOS app

Native **SwiftUI** app for iPhone (iOS 16+).

## Open in Xcode

1. Create a new iOS App project named `BMWLogo` (or any name) with SwiftUI lifecycle.
2. Replace generated sources with files from `ios/BMWLogo/`.
   - Keep only **one** `@main` app entry (delete the Xcode-generated `*App.swift` if you keep `BMWLogoApp.swift`).
3. Set **Info.plist** keys from `ios/BMWLogo/Info.plist` (local network + photo library + Allow Local Networking).
4. Set deployment target **iOS 16.0**.
5. Build and run on your iPhone (Developer Mode required on iOS 16+).

If Xcode reports `ObservableObject` / `@Published` errors, ensure `import Combine` is present in `PiAPIClient.swift` and `BMWLogoApp.swift`.

## Usage

1. Connect iPhone to Pi Wi‑Fi AP (`BMW-Logo-XXXX`, password set via `scripts/setup-wifi-ap.sh`).
2. Open the app — it connects to `http://192.168.4.1:8080`.
3. Browse Gallery / Emoji / My Media tabs, tap an item, **Apply to Display**.

## Bundled vs Pi gallery

Built-in assets ship on the Pi under `assets/`. The app loads the live gallery from `GET /api/gallery` after connecting.
