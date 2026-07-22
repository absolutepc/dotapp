import Foundation

struct DeviceStatus: Codable {
    let device: String
    let current: String?
    let currentName: String?
    let resolution: String
    let connected: Bool
    let mdnsHosts: [String]?
    let brightness: Int?
    let brightnessMin: Int?
    let brightnessMax: Int?

    enum CodingKeys: String, CodingKey {
        case device, current, resolution, connected, brightness
        case currentName = "current_name"
        case mdnsHosts = "mdns_hosts"
        case brightnessMin = "brightness_min"
        case brightnessMax = "brightness_max"
    }
}

struct BrightnessStatus: Codable {
    let ok: Bool?
    let brightness: Int
    let min: Int?
    let max: Int?
    let `default`: Int?
}

struct MediaItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let builtin: Bool
    let filename: String
    let frameCount: Int
    let fps: Double
    let previewUrl: String?
    let framesReady: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, type, builtin, filename, fps
        case frameCount = "frame_count"
        case previewUrl = "preview_url"
        case framesReady = "frames_ready"
    }

    var isAnimation: Bool { type == "animation" }
    var category: MediaCategory {
        if id.contains("emoji") || id.contains("builtin-emoji") { return .emoji }
        if id.contains("bmw") || id.contains("builtin-bmw") { return .bmw }
        return .custom
    }
}

enum MediaCategory: String, CaseIterable, Identifiable {
    case bmw = "Gallery"
    case emoji = "Emoji"
    case custom = "My Media"

    var id: String { rawValue }
}

struct UploadResponse: Codable {
    let mediaId: String
    let name: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case name, type
        case mediaId = "media_id"
    }
}

struct DisplayResponse: Codable {
    let ok: Bool
    let mediaId: String
    let preparing: Bool?
    let message: String?
    let frameCount: Int?
    let fps: Double?

    enum CodingKeys: String, CodingKey {
        case ok, preparing, message, fps
        case mediaId = "media_id"
        case frameCount = "frame_count"
    }
}

struct DisplayJobStatus: Codable {
    let mediaId: String?
    let state: String?
    let message: String?
    let progress: Double?
    let current: String?
    let ready: Bool?

    enum CodingKeys: String, CodingKey {
        case state, message, progress, current, ready
        case mediaId = "media_id"
    }
}

struct WifiStatus: Codable, Sendable {
    let mode: String
    let ok: Bool
    let message: String?
    let ssid: String?
    let ip: String?
    let updatedAt: String?
    let setupPortal: String?
    let needsSetup: Bool?
    let setupSsid: String?
    let mdnsHosts: [String]?

    enum CodingKeys: String, CodingKey {
        case mode, ok, message, ssid, ip
        case updatedAt = "updated_at"
        case setupPortal = "setup_portal"
        case needsSetup = "needs_setup"
        case setupSsid = "setup_ssid"
        case mdnsHosts = "mdns_hosts"
    }

    var isSetupAP: Bool {
        // Only true Setup AP — do NOT treat needs_setup alone as setup
        // (needs_setup can be true while mode=client if wifi-client.json is missing).
        mode == "setup_ap"
    }
}

struct WifiConfigureResponse: Codable {
    let ok: Bool
    let message: String?
}
