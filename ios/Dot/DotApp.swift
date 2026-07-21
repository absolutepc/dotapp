import Combine
import SwiftUI

@main
struct DotApp: App {
    @StateObject private var api = PiAPIClient()
    @StateObject private var locationTracker = DotLocationTracker()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(api)
                .environmentObject(locationTracker)
        }
    }
}
