import SwiftUI
import UIKit

/// Disk + memory cached remote image for gallery tiles / previews.
struct CachedAsyncImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                ZStack {
                    Color.white.opacity(0.06)
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(DotTheme.ice.opacity(0.45))
                }
            } else {
                ZStack {
                    Color.white.opacity(0.06)
                    ProgressView()
                        .tint(DotTheme.ice)
                }
            }
        }
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private func load() async {
        image = nil
        failed = false
        guard let url else {
            failed = true
            return
        }
        if let cached = PreviewImageCache.shared.image(for: url) {
            image = cached
            return
        }
        do {
            let loaded = try await PreviewImageCache.shared.load(url: url)
            image = loaded
            failed = loaded == nil
        } catch {
            failed = true
        }
    }
}

enum PreviewImageCache {
    static let shared = PreviewImageCacheStore()
}

final class PreviewImageCacheStore {
    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        folder = caches.appendingPathComponent("DotPreviews", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        memory.countLimit = 120
    }

    func image(for url: URL) -> UIImage? {
        let key = cacheKey(for: url) as NSString
        if let mem = memory.object(forKey: key) {
            return mem
        }
        let file = diskURL(for: url)
        guard let data = try? Data(contentsOf: file), let image = UIImage(data: data) else {
            return nil
        }
        memory.setObject(image, forKey: key)
        return image
    }

    func load(url: URL) async throws -> UIImage? {
        if let cached = image(for: url) {
            return cached
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let image = UIImage(data: data)
        else {
            return nil
        }
        let key = cacheKey(for: url) as NSString
        memory.setObject(image, forKey: key)
        try? data.write(to: diskURL(for: url), options: .atomic)
        return image
    }

    private func cacheKey(for url: URL) -> String {
        url.absoluteString
    }

    private func diskURL(for url: URL) -> URL {
        let name = cacheKey(for: url)
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "&", with: "_")
            .replacingOccurrences(of: "=", with: "_")
        return folder.appendingPathComponent(name + ".jpg")
    }
}
