import SwiftUI

@main
struct DotApp: App {
    @StateObject private var api = PiAPIClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(api)
        }
    }
}
