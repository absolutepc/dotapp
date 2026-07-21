import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var api: PiAPIClient
    @EnvironmentObject private var locationTracker: DotLocationTracker
    @AppStorage("dot.onboarding.completed") private var onboardingCompleted = false
    @AppStorage("dot.appearance.dark") private var preferDark = false

    @State private var selectedCategory: MediaCategory = .bmw
    @State private var selectedItem: MediaItem?
    @State private var showPhotoPicker = false
    @State private var showSuccess = false
    @State private var showWifiSetup = false
    @State private var showOnboarding = false
    @State private var showLastSeen = false
    @State private var isApplying = false
    @State private var applyError: String?

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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .preferredColorScheme(preferDark ? .dark : .light)
            .task {
                locationTracker.requestPermissionIfNeeded()
                if !onboardingCompleted {
                    showOnboarding = true
                } else {
                    await connectAfterOnboarding()
                }
            }
            .onAppear {
                if !onboardingCompleted, !showOnboarding {
                    showOnboarding = true
                }
                syncSelectionFromGallery()
            }
            .onChange(of: api.gallery) { _ in
                syncSelectionFromGallery()
            }
            .onChange(of: selectedCategory) { _ in
                if let selectedItem, filteredItems.contains(where: { $0.id == selectedItem.id }) {
                    return
                }
                selectedItem = filteredItems.first
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
                    syncSelectionFromGallery()
                }
            }
            .sheet(isPresented: $showWifiSetup) {
                WifiSetupView()
                    .environmentObject(api)
                    .preferredColorScheme(preferDark ? .dark : .light)
            }
            .sheet(isPresented: $showLastSeen) {
                LastSeenLocationView(tracker: locationTracker)
                    .preferredColorScheme(preferDark ? .dark : .light)
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoUploadView(showSuccess: $showSuccess)
                    .environmentObject(api)
                    .preferredColorScheme(preferDark ? .dark : .light)
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    onboardingCompleted = true
                    showOnboarding = false
                    Task { await connectAfterOnboarding() }
                }
            }
            .alert("На экране Dot", isPresented: $showSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Анимация отправлена на круглый дисплей.")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 14) {
                Button {
                    showWifiSetup = true
                } label: {
                    Image(systemName: "wifi")
                }
                .accessibilityLabel("Wi-Fi")

                Button {
                    showLastSeen = true
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                }
                .accessibilityLabel("Где Dot")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 14) {
                Button {
                    preferDark.toggle()
                } label: {
                    Image(systemName: preferDark ? "sun.max.fill" : "moon.fill")
                }
                .accessibilityLabel(preferDark ? "Светлая тема" : "Тёмная тема")

                Button {
                    Task { await api.discoverAndConnect() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Обновить")
            }
        }
    }

    private func connectAfterOnboarding() async {
        await api.discoverAndConnect()
        if api.canBrowseGallery {
            locationTracker.captureLastSeen(host: api.host)
            syncSelectionFromGallery()
        }
        if api.shouldOfferWifiSetup {
            showWifiSetup = true
        }
    }

    private func syncSelectionFromGallery() {
        guard api.canBrowseGallery, !api.gallery.isEmpty else { return }
        if let selectedItem, api.gallery.contains(where: { $0.id == selectedItem.id }) {
            return
        }
        if let currentId = api.status?.current,
           let match = api.gallery.first(where: { $0.id == currentId }) {
            selectedItem = match
            selectedCategory = match.category
            return
        }
        selectedItem = filteredItems.first ?? api.gallery.first
    }

    // MARK: - Gallery layout (top preview + bottom library)

    private var galleryContent: some View {
        VStack(spacing: 0) {
            selectedPreviewPane
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Divider()

            libraryPane
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
    }

    private var selectedPreviewPane: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 220, height: 220)

                if let selectedItem {
                    CachedAsyncImage(url: api.previewURL(for: selectedItem), contentMode: .fill)
                        .frame(width: 220, height: 220)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                }
            }
            .shadow(color: .black.opacity(preferDark ? 0.45 : 0.12), radius: 18, y: 8)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedItem?.name ?? "Выберите анимацию")
                        .font(.title3.bold())
                        .lineLimit(1)
                    Text(subtitle(for: selectedItem))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isApplying, let progress = api.applyProgress {
                        Text(progress)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let applyError {
                        Text(applyError)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    Task { await applySelected() }
                } label: {
                    Group {
                        if isApplying {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.down.to.line.circle.fill")
                                .font(.system(size: 36))
                        }
                    }
                }
                .disabled(selectedItem == nil || isApplying)
                .accessibilityLabel("Отправить на экран Dot")
            }
        }
    }

    private var libraryPane: some View {
        VStack(spacing: 12) {
            Picker("Category", selection: $selectedCategory) {
                ForEach(MediaCategory.allCases) { cat in
                    Text(cat.libraryTitle).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 10
                ) {
                    if selectedCategory == .custom {
                        Button {
                            showPhotoPicker = true
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                                VStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.title2.weight(.semibold))
                                    Text("Добавить")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.secondary)
                            }
                            .aspectRatio(1, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(filteredItems) { item in
                        LibraryTile(
                            item: item,
                            isSelected: selectedItem?.id == item.id,
                            url: api.previewURL(for: item)
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedItem = item
                            }
                        }
                        .contextMenu {
                            if !item.builtin {
                                Button("Удалить", role: .destructive) {
                                    Task {
                                        try? await api.delete(item)
                                        if selectedItem?.id == item.id {
                                            selectedItem = filteredItems.first
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func subtitle(for item: MediaItem?) -> String {
        guard let item else {
            return api.status?.resolution ?? "Нет выбора"
        }
        if item.isAnimation {
            return "Анимация · \(Int(item.fps)) fps"
        }
        return "Статичное изображение"
    }

    private func applySelected() async {
        guard let selectedItem else { return }
        isApplying = true
        applyError = nil
        defer { isApplying = false }
        do {
            try await api.display(selectedItem)
            showSuccess = true
        } catch {
            applyError = error.localizedDescription
        }
    }
}

private struct LibraryTile: View {
    let item: MediaItem
    let isSelected: Bool
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
            CachedAsyncImage(url: url, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        }
        .accessibilityLabel(item.name)
    }
}

private extension MediaCategory {
    var libraryTitle: String {
        switch self {
        case .bmw: return "Галерея"
        case .emoji: return "Emoji"
        case .custom: return "Мои"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PiAPIClient())
        .environmentObject(DotLocationTracker())
}
