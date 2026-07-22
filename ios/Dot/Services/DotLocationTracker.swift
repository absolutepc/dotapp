import Combine
import CoreLocation
import Foundation
import MapKit

struct DotLastSeen: Codable, Equatable, Identifiable {
    var id: String { "\(latitude),\(longitude),\(timestamp.timeIntervalSince1970)" }
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date
    let host: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var mapItem: MKMapItem {
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = "Dot"
        return item
    }
}

/// Records the iPhone location whenever the app successfully talks to Dot.
/// Dot has no GPS — this is “last place the phone saw Dot”, shown in-app (not Apple Find My).
@MainActor
final class DotLocationTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    private static let storageKey = "dot.lastSeen.v1"

    @Published private(set) var lastSeen: DotLastSeen?
    @Published private(set) var authorizationDenied = false
    @Published var statusMessage: String?

    private let manager = CLLocationManager()
    private var pendingHost: String?
    private var waitingForFix = false
    private var updatesStarted = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
        lastSeen = Self.load()
    }

    func reloadFromDisk() {
        if let loaded = Self.load() {
            lastSeen = loaded
        }
    }

    func requestPermissionIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            authorizationDenied = true
        default:
            authorizationDenied = false
        }
    }

    /// Call after a successful connection to the Pi.
    func captureLastSeen(host: String?) {
        pendingHost = host
        statusMessage = nil
        waitingForFix = true
        requestPermissionIfNeeded()

        let status = manager.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            authorizationDenied = false
            requestFix()
        case .denied, .restricted:
            authorizationDenied = true
            waitingForFix = false
            statusMessage = "Разрешите геолокацию, чтобы запоминать место Dot"
        case .notDetermined:
            // waitingForFix stays true — resume in locationManagerDidChangeAuthorization
            break
        @unknown default:
            break
        }
    }

    func openInMaps() {
        guard let lastSeen else { return }
        lastSeen.mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: lastSeen.coordinate),
        ])
    }

    private func requestFix() {
        // Prefer a one-shot fix; also briefly start updates as a fallback for
        // Personal Hotspot / car scenarios where requestLocation alone can stall.
        manager.requestLocation()
        if !updatesStarted {
            updatesStarted = true
            manager.startUpdatingLocation()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                self.stopUpdatesIfNeeded()
            }
        }
    }

    private func stopUpdatesIfNeeded() {
        guard updatesStarted else { return }
        updatesStarted = false
        manager.stopUpdatingLocation()
    }

    private func store(location: CLLocation) {
        // Ignore clearly invalid / stale cache-only readings when possible.
        guard location.horizontalAccuracy >= 0 else { return }
        waitingForFix = false
        stopUpdatesIfNeeded()
        let seen = DotLastSeen(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            timestamp: Date(),
            host: pendingHost
        )
        lastSeen = seen
        Self.save(seen)
        statusMessage = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            authorizationDenied = (status == .denied || status == .restricted)
            if waitingForFix, status == .authorizedWhenInUse || status == .authorizedAlways {
                requestFix()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            store(location: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // Keep waitingForFix if we're still streaming updates.
            if !updatesStarted {
                waitingForFix = false
            }
            if lastSeen == nil {
                statusMessage = "Не удалось получить координаты"
            }
            print("Dot location error: \(error.localizedDescription)")
        }
    }

    private static func load() -> DotLastSeen? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(DotLastSeen.self, from: data)
    }

    private static func save(_ value: DotLastSeen) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        UserDefaults.standard.synchronize()
    }
}
