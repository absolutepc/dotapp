import SwiftUI
import UIKit

struct PreviewView: View {
    @EnvironmentObject private var api: PiAPIClient
    @Environment(\.dismiss) private var dismiss

    let item: MediaItem
    @Binding var showSuccess: Bool
    @State private var isApplying = false
    @State private var applied = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                CachedAsyncImage(url: api.previewURL(for: item), contentMode: .fit)
                    .frame(width: 280, height: 280)
                    .clipShape(Circle())
                    .shadow(radius: 8)

                Text(item.name)
                    .font(.title2.bold())

                Text(item.isAnimation ? "Animation · \(Int(item.fps)) fps" : "Static image")
                    .foregroundStyle(.secondary)

                if applied {
                    Text("На экране Dot")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }

                if isApplying, let progress = api.applyProgress {
                    Text(progress)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await apply() }
                } label: {
                    Group {
                        if isApplying {
                            ProgressView().tint(.white)
                        } else {
                            Text(applied ? "Ещё раз на экран" : "Apply to Display")
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
        errorText = nil
        defer { isApplying = false }
        do {
            try await api.display(item)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            applied = true
            showSuccess = true
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorText = error.localizedDescription
        }
    }
}
