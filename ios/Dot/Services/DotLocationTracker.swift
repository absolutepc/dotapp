import Combine
import CoreLocation
import Foundation
import MapKit
import UIKit

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
    @Published private(set) var isCapturing = false
    @Published var statusMessage: String?

    private let manager = CLLocationManager()
    private var pendingHost: String?
    private var waitingForFix = false
    private var updatesStarted = false
    private var captureStartedAt: Date?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        lastSeen = Self.load()
        refreshAuthorizationFlags()
    }

    func reloadFromDisk() {
        if let loaded = Self.load() {
            lastSeen = loaded
        }
    }

    func requestPermissionIfNeeded() {
        refreshAuthorizationFlags()
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    /// Call after a successful connection to the Pi, or from the map screen to retry.
    func captureLastSeen(host: String?) {
        pendingHost = host
        statusMessage = nil
        waitingForFix = true
        isCapturing = true
        refreshAuthorizationFlags()

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            requestFix()
        case .denied, .restricted:
            authorizationDenied = true
            waitingForFix = false
            isCapturing = false
            statusMessage = "Разрешите геолокацию в Настройках → Dot → Геолокация"
        case .notDetermined:
            statusMessage = "Разрешите доступ к геолокации…"
            manager.requestWhenInUseAuthorization()
        @unknown default:
            waitingForFix = false
            isCapturing = false
        }
    }

    func openInMaps() {
        guard let lastSeen else { return }
        lastSeen.mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: lastSeen.coordinate),
        ])
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshAuthorizationFlags() {
        let status = manager.authorizationStatus
        authorizationDenied = (status == .denied || status == .restricted)
    }

    private func requestFix() {
        guard CLLocationManager.locationServicesEnabled() else {
            waitingForFix = false
            isCapturing = false
            statusMessage = "Службы геолокации выключены на iPhone"
            return
        }

        statusMessage = "Определяем координаты…"
        captureStartedAt = Date()

        // Continuous updates are more reliable than requestLocation() alone
        // under Personal Hotspot / indoors / first fix after install.
        if !updatesStarted {
            updatesStarted = true
            manager.startUpdatingLocation()
        }
        manager.requestLocation()

        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            guard !Task.isCancelled, waitingForFix else { return }
            stopUpdatesIfNeeded()
            waitingForFix = false
            isCapturing = false
            statusMessage = "Не удалось получить GPS за 25 с. Выйдите ближе к окну или на улицу и нажмите ещё раз."
        }
    }

    private func stopUpdatesIfNeeded() {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard updatesStarted else { return }
        updatesStarted = false
        manager.stopUpdatingLocation()
    }

    private func store(location: CLLocation) {
        guard waitingForFix else { return }
        guard location.horizontalAccuracy >= 0 else { return }

        let elapsed = Date().timeIntervalSince(captureStartedAt ?? Date())
        // Prefer a usable fix; accept coarser readings after a few seconds so
        // indoor / hotspot sessions still get a pin.
        let maxAccuracy: CLLocationAccuracy = elapsed < 4 ? 150 : 800
        guard location.horizontalAccuracy <= maxAccuracy else {
            statusMessage = "Сигнал слабый (±\(Int(location.horizontalAccuracy)) м)… ждём точнее"
            return
        }

        waitingForFix = false
        isCapturing = false
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
        let meters = Int(location.horizontalAccuracy.rounded())
        statusMessage = "Точка сохранена (±\(meters) м)"
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            refreshAuthorizationFlags()
            let status = manager.authorizationStatus
            if waitingForFix {
                switch status {
                case .authorizedWhenInUse, .authorizedAlways:
                    requestFix()
                case .denied, .restricted:
                    waitingForFix = false
                    isCapturing = false
                    statusMessage = "Разрешите геолокацию в Настройках → Dot → Геолокация"
                default:
                    break
                }
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
            // While streaming updates, ignore transient locationUnknown and keep waiting.
            if let cl = error as? CLError, cl.code == .locationUnknown, updatesStarted {
                statusMessage = "Ищем GPS…"
                return
            }

            stopUpdatesIfNeeded()
            waitingForFix = false
            isCapturing = false

            if let cl = error as? CLError {
                switch cl.code {
                case .denied:
                    authorizationDenied = true
                    statusMessage = "Геолокация запрещена в настройках"
                case .locationUnknown:
                    statusMessage = "GPS пока недоступен. Попробуйте ещё раз у окна или на улице."
                default:
                    statusMessage = "Ошибка GPS: \(cl.localizedDescription)"
                }
            } else if lastSeen == nil {
                statusMessage = "Не удалось получить координаты"
            }
        }
    }

    private static func load() -> DotLastSeen? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        let decoder = JSONDecoder()
        // Dates were encoded with the default deferredToDate strategy.
        return try? decoder.decode(DotLastSeen.self, from: data)
    }

    private static func save(_ value: DotLastSeen) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
