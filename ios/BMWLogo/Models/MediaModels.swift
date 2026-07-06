import Foundation

struct DeviceStatus: Codable {
    let device: String
    let current: String?
    let currentName: String?
    let resolution: String
    let connected: Bool

    enum CodingKeys: String, CodingKey {
        case device, current, resolution, connected
        case currentName = "current_name"
    }
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

    enum CodingKeys: String, CodingKey {
        case id, name, type, builtin, filename, fps
        case frameCount = "frame_count"
        case previewUrl = "preview_url"
    }

    var isAnimation: Bool { type == "animation" }
    var category: MediaCategory {
        if id.contains("emoji") || id.contains("builtin-emoji") { return .emoji }
        if id.contains("bmw") || id.contains("builtin-bmw") { return .bmw }
        return .custom
    }
}

enum MediaCategory: String, CaseIterable, Identifiable {
    case bmw = "BMW"
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

    enum CodingKeys: String, CodingKey {
        case ok
        case mediaId = "media_id"
    }
}
