import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var api: PiAPIClient
    @EnvironmentObject private var locationTracker: DotLocationTracker
    @AppStorage("dot.onboarding.completed") private var onboardingCompleted = false
    @AppStorage("dot.appearance.dark") private var preferDark = true

    @State private var selectedCategory: MediaCategory = .bmw
    @State private var selectedItem: MediaItem?
    @State private var showPhotoPicker = false
    @State private var showWifiSetup = false
    @State private var showOnboarding = false
    @State private var showLastSeen = false
    @State private var showSettings = false
    @State private var isApplying = false
    @State private var applyError: String?
    @State private var previewGlow = false
    @State private var toastMessage: String?
    @State private var toastVisible = false

    var filteredItems: [MediaItem] {
        api.gallery.filter { $0.category == selectedCategory || (selectedCategory == .custom && !$0.builtin) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBlueBackground(dark: preferDark)

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
            }
            .navigationTitle("Dot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .dotNavigationChrome(dark: preferDark)
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
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    previewGlow = true
                }
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
                    .tint(DotTheme.toolbarTint(dark: preferDark))
            }
            .sheet(isPresented: $showLastSeen) {
                LastSeenLocationView(tracker: locationTracker)
                    .preferredColorScheme(preferDark ? .dark : .light)
                    .tint(DotTheme.toolbarTint(dark: preferDark))
            }
            .sheet(isPresented: $showPhotoPicker) {
                PhotoUploadView(onUploaded: {
                    showToast("Анимация на экране Dot")
                })
                    .environmentObject(api)
                    .preferredColorScheme(preferDark ? .dark : .light)
                    .tint(DotTheme.toolbarTint(dark: preferDark))
            }
            .sheet(isPresented: $showSettings) {
                SettingsView {
                    onboardingCompleted = false
                    showOnboarding = true
                }
                .environmentObject(api)
                .preferredColorScheme(preferDark ? .dark : .light)
                .tint(DotTheme.toolbarTint(dark: preferDark))
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    onboardingCompleted = true
                    showOnboarding = false
                    Task { await connectAfterOnboarding() }
                }
            }
            .overlay(alignment: .bottom) {
                if toastVisible, let toastMessage {
                    Text(toastMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DotTheme.void)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [DotTheme.ice, DotTheme.horizon],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                        .shadow(color: DotTheme.cobalt.opacity(0.45), radius: 12, y: 4)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toastVisible)
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
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Настройки")

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

            Rectangle()
                .fill(DotTheme.ice.opacity(preferDark ? 0.18 : 0.28))
                .frame(height: 1)
                .padding(.horizontal, 24)

            libraryPane
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
        }
    }

    private var selectedPreviewPane: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                DotTheme.ice.opacity(preferDark ? 0.28 : 0.35),
                                DotTheme.cobalt.opacity(0.15),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: previewGlow ? 150 : 130
                        )
                    )
                    .frame(width: 280, height: 280)
                    .allowsHitTesting(false)

                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [DotTheme.ice.opacity(0.55), DotTheme.horizon.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 228, height: 228)

                Circle()
                    .fill(DotTheme.panel(dark: preferDark))
                    .frame(width: 220, height: 220)

                if let selectedItem {
                    CachedAsyncImage(url: api.previewURL(for: selectedItem), contentMode: .fill)
                        .frame(width: 220, height: 220)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 48))
                        .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
                }
            }
            .shadow(color: DotTheme.cobalt.opacity(preferDark ? 0.55 : 0.3), radius: 22, y: 10)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedItem?.name ?? "Выберите анимацию")
                        .font(.title3.bold())
                        .foregroundStyle(DotTheme.primaryText(dark: preferDark))
                        .lineLimit(1)
                    Text(subtitle(for: selectedItem))
                        .font(.caption)
                        .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
                    if isApplying, let progress = api.applyProgress {
                        Text(progress)
                            .font(.caption2)
                            .foregroundStyle(DotTheme.ice.opacity(0.85))
                    }
                    if let applyError {
                        Text(applyError)
                            .font(.caption2)
                            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.5))
                    }
                }
                Spacer(minLength: 8)
                Button {
                    Task { await applySelected() }
                } label: {
                    Group {
                        if isApplying {
                            ProgressView()
                                .tint(DotTheme.void)
                                .frame(minWidth: 88)
                        } else {
                            Text("Apply")
                                .font(.headline.weight(.semibold))
                                .frame(minWidth: 88)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .foregroundStyle(DotTheme.void)
                    .background(
                        LinearGradient(
                            colors: [DotTheme.ice, DotTheme.horizon],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
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
                                    .fill(DotTheme.panel(dark: preferDark))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(DotTheme.panelStroke(dark: preferDark), lineWidth: 1)
                                    }
                                VStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.title2.weight(.semibold))
                                    Text("Добавить")
                                        .font(.caption2)
                                }
                                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
                            }
                            .aspectRatio(1, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(filteredItems) { item in
                        LibraryTile(
                            item: item,
                            isSelected: selectedItem?.id == item.id,
                            url: api.previewURL(for: item),
                            dark: preferDark
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
        .background(DotTheme.void.opacity(preferDark ? 0.28 : 0.08))
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
            showToast("Анимация на экране Dot")
            locationTracker.captureLastSeen(host: api.host)
        } catch {
            applyError = error.localizedDescription
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation { toastVisible = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                withAnimation { toastVisible = false }
            }
        }
    }
}

private struct LibraryTile: View {
    let item: MediaItem
    let isSelected: Bool
    let url: URL?
    var dark: Bool = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DotTheme.panel(dark: dark))
            CachedAsyncImage(url: url, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? LinearGradient(colors: [DotTheme.ice, DotTheme.horizon], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [DotTheme.panelStroke(dark: dark), DotTheme.panelStroke(dark: dark)], startPoint: .top, endPoint: .bottom),
                    lineWidth: isSelected ? 3 : 1
                )
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
