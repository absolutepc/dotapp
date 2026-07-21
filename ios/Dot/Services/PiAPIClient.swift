import Combine
import Foundation
import UIKit

@MainActor
final class PiAPIClient: ObservableObject {
    private static let hostKey = "dot.api.host"
    private static let mdnsKey = "dot.api.mdns"

    @Published var status: DeviceStatus?
    @Published var gallery: [MediaItem] = []
    @Published var wifi: WifiStatus?
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// True when Dot is in first-time Dot-Setup AP mode (app should open Wi‑Fi setup).
    @Published var shouldOfferWifiSetup = false
    /// Live Apply progress text (preparing frames on Dot).
    @Published var applyProgress: String?

    /// Gallery only after normal day-to-day link (client / hotspot), not during setup AP.
    var canBrowseGallery: Bool {
        isConnected && !shouldOfferWifiSetup && wifi?.mode == "client"
    }

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

    private var rememberedMDNS: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.mdnsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.mdnsKey) }
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
            let after = value[value.index(after: colon)...]
            if after.allSatisfy(\.isNumber) {
                value = String(value[..<colon])
            }
        }
        return value.isEmpty ? "192.168.4.1" : value
    }

    /// Candidate Pi addresses: saved → mDNS → setup AP → hotspot LAN.
    static func discoveryCandidates(preferred: String, mdns: [String] = []) -> [String] {
        var list: [String] = []
        func add(_ value: String) {
            let host = sanitizeHost(value)
            if !list.contains(host) {
                list.append(host)
            }
        }
        add(preferred)
        for name in mdns {
            add(name)
        }
        add("dot.local")
        add("192.168.4.1")
        for last in 2...15 {
            add("172.20.10.\(last)")
        }
        return list
    }

    /// Probe hosts in parallel so the phone finds Dot quickly.
    func discoverAndConnect() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let candidates = Self.discoveryCandidates(preferred: host, mdns: rememberedMDNS)
        let found = await Self.probeAll(candidates)

        // Prefer setup AP, then client with IP, then preferred host, then first hit.
        let ranked = found.sorted { a, b in
            score(a.status, host: a.host) > score(b.status, host: b.host)
        }

        for hit in ranked {
            host = hit.host
            wifi = hit.status
            if let mdns = hit.status.mdnsHosts, !mdns.isEmpty {
                rememberedMDNS = mdns
            }

            // Setup AP: reachable, but do NOT open the gallery yet.
            if hit.status.mode == "setup_ap" || hit.status.isSetupAP {
                shouldOfferWifiSetup = true
                isConnected = false
                gallery = []
                status = nil
                errorMessage = "Dot найден в режиме настройки. Откройте «Настройка Wi‑Fi» и пройдите шаги."
                return
            }

            if let ip = hit.status.ip, !ip.isEmpty, hit.status.mode == "client" {
                host = ip
            }

            // Day-to-day: only treat as connected when joined to the phone hotspot.
            if hit.status.mode == "client" {
                do {
                    status = try await get("/api/status", as: DeviceStatus.self)
                    if let hosts = status?.mdnsHosts, !hosts.isEmpty {
                        rememberedMDNS = hosts
                    }
                    gallery = try await get("/api/gallery", as: [MediaItem].self)
                    shouldOfferWifiSetup = false
                    isConnected = hit.status.ok
                    errorMessage = isConnected ? nil : (hit.status.message ?? "Dot ещё не в сети модема")
                    return
                } catch {
                    shouldOfferWifiSetup = false
                    isConnected = false
                    errorMessage = "Dot отвечает, но галерея недоступна. Повторите поиск."
                    return
                }
            }

            // error / switching / unknown — keep user on connection screen
            shouldOfferWifiSetup = hit.status.needsSetup == true
            isConnected = false
            errorMessage = hit.status.message
                ?? "Dot найден, но ещё не подключён к Режиму модема. Включите модем или откройте настройку Wi‑Fi."
            return
        }

        isConnected = false
        shouldOfferWifiSetup = false
        errorMessage =
            "Не найден Dot. Первый раз: «Настройка Wi‑Fi (по шагам)» — сначала Dot-Setup, потом модем. "
            + "Обычная работа: включите Режим модема и подождите несколько секунд."
    }

    private func score(_ status: WifiStatus, host: String) -> Int {
        var value = 0
        if status.mode == "setup_ap" { value += 100 }
        if status.mode == "client", status.ok { value += 80 }
        if host == self.host { value += 20 }
        if host.hasSuffix(".local") { value += 10 }
        if host == "192.168.4.1" { value += 5 }
        return value
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let wifiStatus = try await get("/api/wifi/status", as: WifiStatus.self)
            wifi = wifiStatus
            if let mdns = wifiStatus.mdnsHosts, !mdns.isEmpty {
                rememberedMDNS = mdns
            }

            if wifiStatus.mode == "setup_ap" || wifiStatus.isSetupAP {
                shouldOfferWifiSetup = true
                isConnected = false
                gallery = []
                errorMessage = "Dot в режиме настройки. Откройте «Настройка Wi‑Fi» и пройдите шаги."
                return
            }

            guard wifiStatus.mode == "client" else {
                shouldOfferWifiSetup = wifiStatus.needsSetup == true
                isConnected = false
                errorMessage = wifiStatus.message
                    ?? "Включите Режим модема или откройте настройку Wi‑Fi."
                return
            }

            status = try await get("/api/status", as: DeviceStatus.self)
            if let hosts = status?.mdnsHosts, !hosts.isEmpty {
                rememberedMDNS = hosts
            }
            gallery = try await get("/api/gallery", as: [MediaItem].self)
            if let ip = wifiStatus.ip, !ip.isEmpty {
                host = ip
            }
            shouldOfferWifiSetup = false
            isConnected = wifiStatus.ok
            errorMessage = isConnected ? nil : wifiStatus.message
        } catch {
            await discoverAndConnect()
        }
    }

    func wifiStatus() async throws -> WifiStatus {
        let status = try await get("/api/wifi/status", as: WifiStatus.self)
        wifi = status
        shouldOfferWifiSetup = status.isSetupAP
        if let mdns = status.mdnsHosts, !mdns.isEmpty {
            rememberedMDNS = mdns
        }
        return status
    }

    func ensureReachableForSetup() async throws {
        // Prefer whatever discovery finds on the setup network.
        if let hit = await Self.probeAll(["192.168.4.1", "dot.local"]).first {
            host = hit.host
            wifi = hit.status
            shouldOfferWifiSetup = hit.status.isSetupAP
            return
        }
        throw APIError.setupUnreachable
    }

    func configureWifi(ssid: String, password: String, applyNow: Bool = false) async throws -> WifiConfigureResponse {
        try await ensureReachableForSetup()

        struct Body: Encodable {
            let ssid: String
            let password: String
            let apply_now: Bool
        }

        var request = URLRequest(url: baseURL.appending(path: "/api/wifi/configure"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try JSONEncoder().encode(Body(ssid: ssid, password: password, apply_now: applyNow))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        return try JSONDecoder().decode(WifiConfigureResponse.self, from: data)
    }

    /// After Personal Hotspot is on: tear down Setup AP and join once.
    func connectHotspot() async throws -> WifiConfigureResponse {
        var request = URLRequest(url: baseURL.appending(path: "/api/wifi/connect-hotspot"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        return try JSONDecoder().decode(WifiConfigureResponse.self, from: data)
    }

    func display(_ item: MediaItem) async throws {
        applyProgress = "Отправляю на Dot…"
        var request = URLRequest(url: baseURL.appending(path: "/api/display"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(["media_id": item.id])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            applyProgress = nil
            throw APIError.requestFailed
        }
        let decoded = try JSONDecoder().decode(DisplayResponse.self, from: data)
        if decoded.preparing == true {
            applyProgress = decoded.message ?? "Готовим кадры на Dot…"
            try await pollDisplayReady(mediaId: item.id)
        } else {
            applyProgress = decoded.message ?? "На экране"
        }
        applyProgress = nil
        await refresh()
    }

    private func pollDisplayReady(mediaId: String) async throws {
        for _ in 0..<90 {
            try await Task.sleep(nanoseconds: 500_000_000)
            guard let status = try? await get("/api/display/status", as: DisplayJobStatus.self) else {
                continue
            }
            if let message = status.message, !message.isEmpty {
                applyProgress = message
            }
            if status.state == "error", status.mediaId == mediaId {
                applyProgress = nil
                throw APIError.prepareFailed(status.message ?? "Prepare failed")
            }
            if status.mediaId == mediaId, status.state == "ready" || status.ready == true {
                return
            }
            // Also accept when current already switched
            if status.current == mediaId, status.state != "preparing" {
                return
            }
        }
        applyProgress = nil
        throw APIError.prepareFailed("Таймаут подготовки кадров")
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

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct ProbeHit: Sendable {
        let host: String
        let status: WifiStatus
    }

    nonisolated private static func probeAll(_ candidates: [String]) async -> [ProbeHit] {
        await withTaskGroup(of: ProbeHit?.self) { group in
            for candidate in candidates {
                group.addTask {
                    guard let status = await probe(host: candidate) else { return nil }
                    return ProbeHit(host: candidate, status: status)
                }
            }
            var hits: [ProbeHit] = []
            for await hit in group {
                if let hit {
                    hits.append(hit)
                }
            }
            return hits
        }
    }

    nonisolated private static func probe(host candidate: String) async -> WifiStatus? {
        guard let url = URL(string: "http://\(candidate):8080/api/wifi/status") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(WifiStatus.self, from: data)
        } catch {
            return nil
        }
    }
}

enum APIError: LocalizedError {
    case requestFailed
    case setupUnreachable
    case prepareFailed(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed:
            return "Не удалось связаться с Dot"
        case .setupUnreachable:
            return "Dot недоступен на 192.168.4.1. Подключите iPhone к Wi‑Fi Dot-Setup-… (пароль: dotsetup1) и повторите."
        case .prepareFailed(let message):
            return message
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
