import Foundation
import UIKit

@MainActor
final class PiAPIClient: ObservableObject {
    @Published var status: DeviceStatus?
    @Published var gallery: [MediaItem] = []
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    var baseURL: URL {
        URL(string: "http://192.168.4.1:8080")!
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            status = try await get("/api/status", as: DeviceStatus.self)
            gallery = try await get("/api/gallery", as: [MediaItem].self)
            isConnected = true
        } catch {
            isConnected = false
            errorMessage = error.localizedDescription
        }
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

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: path))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.requestFailed
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum APIError: LocalizedError {
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .requestFailed: return "Request to Dot device failed"
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
