import SwiftUI
import UIKit

struct PreviewView: View {
    @EnvironmentObject private var api: PiAPIClient
    @Environment(\.dismiss) private var dismiss

    let item: MediaItem
    @Binding var showSuccess: Bool
    @State private var isApplying = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                AsyncImage(url: api.previewURL(for: item)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        ProgressView()
                    }
                }
                .frame(width: 280, height: 280)
                .clipShape(Circle())
                .shadow(radius: 8)

                Text(item.name)
                    .font(.title2.bold())

                Text(item.isAnimation ? "Animation · \(Int(item.fps)) fps" : "Static image")
                    .foregroundStyle(.secondary)

                Button {
                    Task { await apply() }
                } label: {
                    Group {
                        if isApplying {
                            ProgressView().tint(.white)
                        } else {
                            Text("Apply to Display")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying)

                if !item.builtin {
                    Button("Delete", role: .destructive) {
                        Task {
                            try? await api.delete(item)
                            dismiss()
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func apply() async {
        isApplying = true
        defer { isApplying = false }
        do {
            try await api.display(item)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showSuccess = true
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
