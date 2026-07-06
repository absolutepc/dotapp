import SwiftUI

@main
struct BMWLogoApp: App {
    @StateObject private var api = PiAPIClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(api)
        }
    }
}
