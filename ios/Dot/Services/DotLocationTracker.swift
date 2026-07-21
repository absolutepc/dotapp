import Combine
import CoreLocation
import Foundation
import MapKit

struct DotLastSeen: Codable, Equatable, Identifiable {
    var id: String { "\(latitude),\(longitude),\(timestamp)" }
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

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        lastSeen = Self.load()
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
        requestPermissionIfNeeded()
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            if status == .denied || status == .restricted {
                authorizationDenied = true
                statusMessage = "Разрешите геолокацию, чтобы запоминать место Dot"
            }
            return
        }
        waitingForFix = true
        manager.requestLocation()
    }

    func openInMaps() {
        guard let lastSeen else { return }
        lastSeen.mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: lastSeen.coordinate),
        ])
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            authorizationDenied = (status == .denied || status == .restricted)
            if waitingForFix, status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            waitingForFix = false
            let seen = DotLastSeen(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy,
                timestamp: location.timestamp,
                host: pendingHost
            )
            lastSeen = seen
            Self.save(seen)
            statusMessage = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            waitingForFix = false
            statusMessage = "Не удалось получить координаты"
            print("Dot location error: \(error.localizedDescription)")
        }
    }

    private static func load() -> DotLastSeen? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(DotLastSeen.self, from: data)
    }

    private static func save(_ value: DotLastSeen) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
