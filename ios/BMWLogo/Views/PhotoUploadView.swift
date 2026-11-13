import AVFoundation
import CoreTransferable
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// PhotosPicker hands out temporary movie URLs. Copy the movie before the
/// transfer callback returns, or iOS may remove it before upload.
private struct PickedMovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("xdot-" + UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

struct PhotoUploadView: View {
    @EnvironmentObject private var api: PiAPIClient
    @Environment(\.dismiss) private var dismiss

    @Binding var showSuccess: Bool
    @State private var pickerItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var isLoading = false
    @State private var isUploading = false
    @State private var errorText: String?

    @State private var image: UIImage?
    @State private var movieURL: URL?
    @State private var uploadData: Data?
    @State private var uploadName = "upload.png"
    @State private var uploadType = "image/png"
    @State private var mediaWidth: CGFloat = 0
    @State private var mediaHeight: CGFloat = 0

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var liveDrag: CGSize = .zero
    @GestureState private var livePinch: CGFloat = 1

    private let previewSide: CGFloat = 280

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        PhotosPicker(
                            selection: $pickerItem,
                            matching: .any(of: [.images, .videos]),
                            preferredItemEncoding: .current
                        ) {
                            Label("Фото и видео", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            showFiles = true
                        } label: {
                            Label("Файлы", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }

                    if isLoading {
                        ProgressView("Открываем файл…")
                    }

                    if mediaWidth > 0 && mediaHeight > 0 {
                        Text("Круг Ø 71 мм · 480 × 480")
                            .font(.headline)

                        circlePreview
                            .frame(width: previewSide, height: previewSide)
                            .accessibilityLabel("Область круглой обрезки")

                        Text("Перемещайте изображение пальцем и меняйте масштаб двумя пальцами.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)

                        HStack {
                            Image(systemName: "minus.magnifyingglass")
                            Slider(value: $zoom, in: 1...4)
                                .onChange(of: zoom) { _, value in
                                    offset = clampedOffset(offset, at: value)
                                }
                            Image(systemName: "plus.magnifyingglass")
                            Button("Сброс") {
                                zoom = 1
                                offset = .zero
                            }
                            .font(.caption)
                        }

                        Button {
                            Task { await uploadCropped() }
                        } label: {
                            if isUploading {
                                ProgressView().tint(.white)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Обрезать и загрузить")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isUploading || isLoading)
                    } else {
                        Text("Выберите фото, GIF или видео. Круглая обрезка применится ко всем кадрам.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Круглая обрезка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await loadFromPhotos(item) }
            }
            .fileImporter(
                isPresented: $showFiles,
                allowedContentTypes: [.image, .movie],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await loadFromFiles(url) }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
            .onDisappear {
                if let movieURL, movieURL.lastPathComponent.hasPrefix("xdot-") {
                    try? FileManager.default.removeItem(at: movieURL)
                }
            }
        }
    }

    private var circlePreview: some View {
        let effectiveZoom = max(1, min(4, zoom * livePinch))
        let proposed = CGSize(width: offset.width + liveDrag.width,
                              height: offset.height + liveDrag.height)
        let effectiveOffset = clampedOffset(proposed, at: effectiveZoom)

        return ZStack {
            Color.black
            Group {
                if let movieURL {
                    LoopingCropVideo(url: movieURL)
                } else if let image {
                    AnimatedCropImage(image: image)
                }
            }
            .frame(width: previewSide, height: previewSide)
            .scaleEffect(effectiveZoom)
            .offset(effectiveOffset)
        }
        .frame(width: previewSide, height: previewSide)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($liveDrag) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    let next = CGSize(width: offset.width + value.translation.width,
                                      height: offset.height + value.translation.height)
                    offset = clampedOffset(next, at: zoom)
                }
                .simultaneously(with:
                    MagnificationGesture()
                        .updating($livePinch) { value, state, _ in state = value }
                        .onEnded { value in
                            zoom = max(1, min(4, zoom * value))
                            offset = clampedOffset(offset, at: zoom)
                        }
                )
        )
    }

    /// Keep the selected 480×480 crop fully inside the original frame.
    private func clampedOffset(_ point: CGSize, at magnification: CGFloat) -> CGSize {
        guard mediaWidth > 0 && mediaHeight > 0 else { return .zero }
        let fit = max(previewSide / mediaWidth, previewSide / mediaHeight) * magnification
        let maxX = max(0, (mediaWidth * fit - previewSide) / 2)
        let maxY = max(0, (mediaHeight * fit - previewSide) / 2)
        return CGSize(
            width: max(-maxX, min(maxX, point.width)),
            height: max(-maxY, min(maxY, point.height))
        )
    }

    private func cropParameters() -> [String: Double] {
        let scale = max(previewSide / mediaWidth, previewSide / mediaHeight) * zoom
        let side = previewSide / scale
        let adjusted = clampedOffset(offset, at: zoom)
        let x = max(0, min(mediaWidth - side, (mediaWidth - side) / 2 - adjusted.width / scale))
        let y = max(0, min(mediaHeight - side, (mediaHeight - side) / 2 - adjusted.height / scale))
        return [
            "x": Double(x / mediaWidth),
            "y": Double(y / mediaHeight),
            "w": Double(side / mediaWidth),
            "h": Double(side / mediaHeight)
        ]
    }

    @MainActor
    private func loadFromPhotos(_ item: PhotosPickerItem) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                guard let movie = try await item.loadTransferable(type: PickedMovieFile.self) else {
                    throw APIError.requestFailed
                }
                try await configureMovie(movie.url)
            } else {
                guard let raw = try await item.loadTransferable(type: Data.self) else {
                    throw APIError.requestFailed
                }
                try configureImage(raw)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func loadFromFiles(_ originalURL: URL) async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        let granted = originalURL.startAccessingSecurityScopedResource()
        defer { if granted { originalURL.stopAccessingSecurityScopedResource() } }
        do {
            let ext = originalURL.pathExtension.lowercased()
            if ["mov", "mp4", "m4v", "webm"].contains(ext) {
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent("xdot-" + UUID().uuidString + "." + ext)
                try FileManager.default.copyItem(at: originalURL, to: copy)
                try await configureMovie(copy)
            } else {
                try configureImage(Data(contentsOf: originalURL))
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func configureMovie(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw APIError.requestFailed
        }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let width = abs(natural.width * transform.a) + abs(natural.height * transform.c)
        let height = abs(natural.width * transform.b) + abs(natural.height * transform.d)
        guard width > 0 && height > 0 else { throw APIError.requestFailed }

        clearPreviousMovie()
        movieURL = url
        image = nil
        uploadData = nil
        let ext = url.pathExtension.lowercased()
        uploadName = "upload." + (["mov", "mp4", "webm"].contains(ext) ? ext : "mov")
        uploadType = ext == "mp4" ? "video/mp4" : "video/quicktime"
        mediaWidth = width
        mediaHeight = height
        resetTransform()
    }

    @MainActor
    private func configureImage(_ data: Data) throws {
        guard let decoded = UIImage(data: data), decoded.size.width > 0,
              decoded.size.height > 0 else { throw APIError.requestFailed }
        clearPreviousMovie()
        movieURL = nil
        let isGIF = data.starts(with: Data("GIF8".utf8))
        if isGIF {
            image = animatedGIF(data: data) ?? decoded
            uploadData = data  // Keep ALL original frames and their durations.
            uploadName = "upload.gif"
            uploadType = "image/gif"
        } else {
            // Normalizing orientation here makes the preview and server crop match.
            let renderer = UIGraphicsImageRenderer(size: decoded.size)
            uploadData = renderer.pngData { _ in
                decoded.draw(in: CGRect(origin: .zero, size: decoded.size))
            }
            image = UIImage(data: uploadData ?? Data()) ?? decoded
            uploadName = "upload.png"
            uploadType = "image/png"
        }
        mediaWidth = image?.size.width ?? decoded.size.width
        mediaHeight = image?.size.height ?? decoded.size.height
        resetTransform()
    }

    private func resetTransform() {
        zoom = 1
        offset = .zero
    }

    private func clearPreviousMovie() {
        if let movieURL, movieURL.lastPathComponent.hasPrefix("xdot-") {
            try? FileManager.default.removeItem(at: movieURL)
        }
    }

    @MainActor
    private func uploadCropped() async {
        guard mediaWidth > 0 && mediaHeight > 0 else { return }
        isUploading = true
        errorText = nil
        defer { isUploading = false }
        do {
            let data: Data
            if let uploadData {
                data = uploadData
            } else if let movieURL {
                data = try Data(contentsOf: movieURL)
            } else {
                throw APIError.requestFailed
            }
            let response = try await api.upload(
                data: data, filename: uploadName, mimeType: uploadType,
                crop: cropParameters()
            )
            if let uploaded = api.gallery.first(where: { $0.id == response.mediaId }) {
                try await api.display(uploaded)
            } else {
                throw APIError.requestFailed
            }
            showSuccess = true
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct AnimatedCropImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.image = image
    }
}

private func animatedGIF(data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let count = min(CGImageSourceGetCount(source), 90) // Keep preview memory bounded.
    guard count > 1 else { return nil }
    var frames: [UIImage] = []
    var duration: TimeInterval = 0
    for index in 0..<count {
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, index,
            [kCGImageSourceCreateThumbnailFromImageAlways: true,
             kCGImageSourceThumbnailMaxPixelSize: 600] as CFDictionary
        ) else { continue }
        frames.append(UIImage(cgImage: cgImage))
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double)
            ?? 0.1
        duration += max(0.02, delay)
    }
    guard !frames.isEmpty else { return nil }
    return UIImage.animatedImage(with: frames, duration: duration)
}

private struct LoopingCropVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingVideoUIView {
        LoopingVideoUIView(url: url)
    }

    func updateUIView(_ view: LoopingVideoUIView, context: Context) {}
}

private final class LoopingVideoUIView: UIView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    override static var layerClass: AnyClass { AVPlayerLayer.self }

    init(url: URL) {
        super.init(frame: .zero)
        let videoLayer = layer as! AVPlayerLayer
        videoLayer.player = player
        videoLayer.videoGravity = .resizeAspectFill
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.isMuted = true
        player.play()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    deinit { player.pause() }
}
