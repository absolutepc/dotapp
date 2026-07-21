import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var api: PiAPIClient
    @EnvironmentObject private var locationTracker: DotLocationTracker
    @AppStorage("dot.onboarding.completed") private var onboardingCompleted = false

    @State private var selectedCategory: MediaCategory = .bmw
    @State private var selectedItem: MediaItem?
    @State private var showPhotoPicker = false
    @State private var showSuccess = false
    @State private var showWifiSetup = false
    @State private var showOnboarding = false
    @State private var showLastSeen = false

    var filteredItems: [MediaItem] {
        api.gallery.filter { $0.category == selectedCategory || (selectedCategory == .custom && !$0.builtin) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if api.canBrowseGallery {
                    galleryContent
                } else {
                    ConnectionView(errorMessage: api.errorMessage) {
                        showWifiSetup = true
                    } onShowLocation: {
                        showLastSeen = true
                    } onShowOnboarding: {
                        onboardingCompleted = false
                        showOnboarding = true
                    }
                }
            }
            .navigationTitle("Dot")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        Button {
                            showWifiSetup = true
                        } label: {
                            Image(systemName: "wifi")
                        }
                        .accessibilityLabel("Wi-Fi setup")

                        Button {
                            showLastSeen = true
                        } label: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                        .accessibilityLabel("Last Dot location")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await api.discoverAndConnect() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                locationTracker.requestPermissionIfNeeded()
                // Present intro on first launch (flag lives in UserDefaults on this iPhone).
                if !onboardingCompleted {
                    showOnboarding = true
                } else {
                    await connectAfterOnboarding()
                }
            }
            .onAppear {
                // Belt-and-suspenders: some rebuilds miss the initial .task presentation.
                if !onboardingCompleted, !showOnboarding {
                    showOnboarding = true
                }
            }
            .refreshable { await api.discoverAndConnect() }
            .onChange(of: api.shouldOfferWifiSetup) { needsSetup in
                if needsSetup, onboardingCompleted, !showOnboarding {
                    showWifiSetup = true
                }
            }
            .onChange(of: api.canBrowseGallery) { ready in
                if ready {
                    locationTracker.captureLastSeen(host: api.host)
                }
            }
            .sheet(item: $selectedItem) { item in
                PreviewView(item: item, showSuccess: $showSuccess)
                    .environmentObject(api)
            }
            .sheet(isPresented: $showWifiSetup) {
                WifiSetupView()
                    .environmentObject(api)
            }
            .sheet(isPresented: $showLastSeen) {
                LastSeenLocationView(tracker: locationTracker)
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    onboardingCompleted = true
                    showOnboarding = false
                    Task { await connectAfterOnboarding() }
                }
            }
            .alert("Applied", isPresented: $showSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Image sent to the round display.")
            }
        }
    }

    private func connectAfterOnboarding() async {
        await api.discoverAndConnect()
        if api.canBrowseGallery {
            locationTracker.captureLastSeen(host: api.host)
        }
        if api.shouldOfferWifiSetup {
            showWifiSetup = true
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
            CachedAsyncImage(url: api.previewURL(for: item))
                .frame(width: 100, height: 100)
                .clipShape(Circle())

            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PiAPIClient())
        .environmentObject(DotLocationTracker())
}
