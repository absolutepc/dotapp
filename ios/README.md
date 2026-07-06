# BMW Logo — iOS app

Native **SwiftUI** app for iPhone (iOS 16+).

## Open in Xcode

1. Create a new iOS App project named `BMWLogo` with SwiftUI lifecycle.
2. Replace generated sources with files from `ios/BMWLogo/`.
3. Set **Info.plist** keys from `ios/BMWLogo/Info.plist` (local network + photo library).
4. Set deployment target **iOS 16.0**.
5. Build and run on your iPhone (Developer Mode / Ad Hoc profile required).

## Usage

1. Connect iPhone to Pi Wi‑Fi AP (`BMW-Logo-XXXX`, password set via `scripts/setup-wifi-ap.sh`).
2. Open the app — it connects to `http://192.168.4.1:8080`.
3. Browse BMW / Emoji / My Media tabs, tap an item, **Apply to Display**.

## Bundled vs Pi gallery

Built-in assets ship on the Pi under `assets/`. The app loads the live gallery from `GET /api/gallery` after connecting.
