import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var api: PiAPIClient
    @State private var selectedCategory: MediaCategory = .bmw
    @State private var selectedItem: MediaItem?
    @State private var showPhotoPicker = false
    @State private var showSuccess = false
    @State private var showWifiSetup = false

    var filteredItems: [MediaItem] {
        api.gallery.filter { $0.category == selectedCategory || (selectedCategory == .custom && !$0.builtin) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if api.isConnected {
                    galleryContent
                } else {
                    ConnectionView(errorMessage: api.errorMessage) {
                        showWifiSetup = true
                    }
                }
            }
            .navigationTitle("Dot")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showWifiSetup = true
                    } label: {
                        Image(systemName: "wifi")
                    }
                    .accessibilityLabel("Wi-Fi setup")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await api.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task { await api.refresh() }
            .refreshable { await api.refresh() }
            .sheet(item: $selectedItem) { item in
                PreviewView(item: item, showSuccess: $showSuccess)
                    .environmentObject(api)
            }
            .sheet(isPresented: $showWifiSetup) {
                WifiSetupView()
                    .environmentObject(api)
            }
            .alert("Applied", isPresented: $showSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Image sent to the round display.")
            }
        }
    }

    private var galleryContent: some View {
        VStack(spacing: 0) {
            if let status = api.status {
                HStack {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text(status.currentName ?? "Ready")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(status.resolution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Picker("Category", selection: $selectedCategory) {
                ForEach(MediaCategory.allCases) { cat in
                    Text(cat.rawValue).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                    if selectedCategory == .custom {
                        Button {
                            showPhotoPicker = true
                        } label: {
                            VStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 36))
                                Text("Upload")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity, minHeight: 110)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(filteredItems) { item in
                        MediaTile(item: item)
                            .onTapGesture { selectedItem = item }
                    }
                }
                .padding(.horizontal)
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoUploadView(showSuccess: $showSuccess)
                .environmentObject(api)
        }
    }
}

struct MediaTile: View {
    @EnvironmentObject private var api: PiAPIClient
    let item: MediaItem

    var body: some View {
        VStack(spacing: 6) {
            AsyncImage(url: api.previewURL(for: item)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())

            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
        }
    }
}

#Preview {
    ContentView().environmentObject(PiAPIClient())
}
