import Combine
import SwiftUI

@main
struct DotApp: App {
    @StateObject private var api = PiAPIClient()
    @StateObject private var locationTracker = DotLocationTracker()
    @AppStorage("dot.appearance.dark") private var preferDark = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(api)
                .environmentObject(locationTracker)
                .preferredColorScheme(preferDark ? .dark : .light)
                .tint(DotTheme.toolbarTint(dark: preferDark))
        }
    }
}
