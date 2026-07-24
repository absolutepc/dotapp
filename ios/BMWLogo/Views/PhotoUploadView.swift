import PhotosUI
import SwiftUI
import UIKit

struct PhotoUploadView: View {
    @EnvironmentObject private var api: PiAPIClient
    @Environment(\.dismiss) private var dismiss

    @Binding var showSuccess: Bool
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                PhotosPicker(selection: $pickerItem, matching: .any(of: [.images, .livePhotos])) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)

                Text("Images are resized to 480×480 before upload.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isUploading {
                    ProgressView("Uploading…")
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Upload")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { newItem in
                guard let newItem else { return }
                Task { await upload(item: newItem) }
            }
        }
    }

    private func upload(item: PhotosPickerItem) async {
        isUploading = true
        errorText = nil
        defer { isUploading = false }

        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                throw APIError.requestFailed
            }

            if let image = UIImage(data: raw), let png = ImageResizer.pngData(from: image) {
                let response = try await api.upload(data: png, filename: "upload.png", mimeType: "image/png")
                if let uploaded = api.gallery.first(where: { $0.id == response.mediaId }) {
                    try await api.display(uploaded)
                }
            } else {
                try await api.upload(data: raw, filename: "upload.gif", mimeType: "image/gif")
            }

            showSuccess = true
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
