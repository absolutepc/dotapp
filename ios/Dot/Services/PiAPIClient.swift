import Combine
import Foundation
import UIKit

@MainActor
final class PiAPIClient: ObservableObject {
    private static let hostKey = "dot.api.host"

    @Published var status: DeviceStatus?
    @Published var gallery: [MediaItem] = []
    @Published var wifi: WifiStatus?
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// True when Pi is in first-time Dot-Setup AP mode (app should open Wi‑Fi setup).
    @Published var shouldOfferWifiSetup = false

    /// Host only, e.g. `192.168.4.1` or `172.20.10.5` (no scheme/port).
    @Published var host: String {
        didSet {
            let cleaned = Self.sanitizeHost(host)
            if cleaned != host {
                host = cleaned
                return
            }
            UserDefaults.standard.set(cleaned, forKey: Self.hostKey)
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.hostKey) ?? "192.168.4.1"
        self.host = Self.sanitizeHost(saved)
    }

    var baseURL: URL {
        URL(string: "http://\(host):8080")!
    }

    static func sanitizeHost(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "https://", with: "")
        value = value.replacingOccurrences(of: "http://", with: "")
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        if let colon = value.firstIndex(of: ":") {
            // strip :8080 if user pasted full URL host:port
            let after = value[value.index(after: colon)...]
            if after.allSatisfy(\.isNumber) {
                value = String(value[..<colon])
            }
        }
        return value.isEmpty ? "192.168.4.1" : value
    }

    /// Candidate Pi addresses: saved → setup AP → common iPhone hotspot LAN.
    static func discoveryCandidates(preferred: String) -> [String] {
        var list: [String] = []
        func add(_ value: String) {
            let host = sanitizeHost(value)
            if !list.contains(host) {
                list.append(host)
            }
        }
        add(preferred)
        add("192.168.4.1")
        // iPhone Personal Hotspot typically NATs as 172.20.10.1; Pi often gets .2+.
        for last in 2...15 {
            add("172.20.10.\(last)")
        }
        return list
    }

    /// Probe hosts until one answers; used on launch so the user need not type an IP.
    func discoverAndConnect() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let candidates = Self.discoveryCandidates(preferred: host)
        for candidate in candidates {
            if let probed = await probe(host: candidate) {
                host = candidate
                wifi = probed
                shouldOfferWifiSetup = probed.isSetupAP
                do {
                    status = try await get("/api/status", as: DeviceStatus.self)
                    gallery = try await get("/api/gallery", as: [MediaItem].self)
                    if let ip = probed.ip, !ip.isEmpty, probed.mode == "client" {
                        host = ip
                    }
                    isConnected = true
                    errorMessage = nil
                    return
                } catch {
                    // Reachable wifi status but gallery failed — still treat as connected for setup.
                    if probed.isSetupAP {
                        isConnected = true
                        shouldOfferWifiSetup = true
                        errorMessage = nil
                        return
                    }
                }
            }
        }

        isConnected = false
        shouldOfferWifiSetup = false
        errorMessage =
            "Не найден Dot. Для первого раза: Wi‑Fi → Dot-Setup-… (пароль dotsetup1), затем «Настройка Wi‑Fi». "
            + "Обычная работа: включите Режим модема и подождите несколько секунд."
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            status = try await get("/api/status", as: DeviceStatus.self)
            gallery = try await get("/api/gallery", as: [MediaItem].self)
            wifi = try? await get("/api/wifi/status", as: WifiStatus.self)
            if let wifi {
                shouldOfferWifiSetup = wifi.isSetupAP
                if let ip = wifi.ip, !ip.isEmpty, wifi.mode == "client" {
                    host = ip
                }
            }
            isConnected = true
        } catch {
            // Fall back to discovery instead of leaving the user stuck on a stale IP.
            await discoverAndConnect()
        }
    }

    func wifiStatus() async throws -> WifiStatus {
        let status = try await get("/api/wifi/status", as: WifiStatus.self)
        wifi = status
        shouldOfferWifiSetup = status.isSetupAP
        return status
    }

    /// Confirm the API is reachable on the current host before sending credentials.
    func ensureReachableForSetup() async throws {
        host = "192.168.4.1"
        guard let status = await probe(host: host) else {
            throw APIError.setupUnreachable
        }
        wifi = status
        shouldOfferWifiSetup = status.isSetupAP
    }

    /// Send phone hotspot credentials while connected to Dot-Setup AP.
    func configureWifi(ssid: String, password: String) async throws -> WifiConfigureResponse {
        try await ensureReachableForSetup()

        var request = URLRequest(url: baseURL.appending(path: "/api/wifi/configure"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try JSONEncoder().encode([
            "ssid": ssid,
            "password": password,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        return try JSONDecoder().decode(WifiConfigureResponse.self, from: data)
    }

    func display(_ item: MediaItem) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/display"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["media_id": item.id])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        await refresh()
    }

    func upload(data: Data, filename: String, mimeType: String) async throws -> UploadResponse {
        let boundary = UUID().uuidString
        var request = URLRequest(url: baseURL.appending(path: "/api/upload"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        let upload = try JSONDecoder().decode(UploadResponse.self, from: responseData)
        await refresh()
        return upload
    }

    func delete(_ item: MediaItem) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/media/\(item.id)"))
        request.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        await refresh()
    }

    func previewURL(for item: MediaItem) -> URL {
        baseURL.appending(path: item.previewUrl ?? "/api/preview/\(item.id)")
    }

    private func probe(host candidate: String) async -> WifiStatus? {
        guard let url = URL(string: "http://\(candidate):8080/api/wifi/status") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(WifiStatus.self, from: data)
        } catch {
            return nil
        }
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum APIError: LocalizedError {
    case requestFailed
    case setupUnreachable

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Request to Dot device failed"
        case .setupUnreachable:
            return "Pi недоступен на 192.168.4.1. Подключите iPhone к Wi‑Fi Dot-Setup-… (пароль: dotsetup1) и повторите."
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

enum ImageResizer {
    static func resizeToSquare(_ image: UIImage, size: CGFloat = 480) -> UIImage? {
        let target = CGSize(width: size, height: size)
        UIGraphicsBeginImageContextWithOptions(target, true, 1)
        defer { UIGraphicsEndImageContext() }
        let aspect = min(size / image.size.width, size / image.size.height)
        let w = image.size.width * aspect
        let h = image.size.height * aspect
        let rect = CGRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h)
        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: target))
        image.draw(in: rect)
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    static func pngData(from image: UIImage) -> Data? {
        resizeToSquare(image)?.pngData()
    }
}
