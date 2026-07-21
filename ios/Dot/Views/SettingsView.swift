import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var api: PiAPIClient
    @Environment(\.dismiss) private var dismiss

    @AppStorage("dot.appearance.dark") private var preferDark = false
    @AppStorage("dot.onboarding.completed") private var onboardingCompleted = true

    @State private var draftBrightness: Double = 100
    @State private var isSavingBrightness = false
    @State private var brightnessError: String?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isBusy = false
    @State private var showWifiSetup = false
    @State private var confirmReprovision = false
    @State private var confirmClearHost = false

    var onShowOnboarding: () -> Void = {}

    private var brightnessMin: Double {
        Double(api.status?.brightnessMin ?? 5)
    }

    private var brightnessMax: Double {
        Double(api.status?.brightnessMax ?? 100)
    }

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                brightnessSection
                deviceSection
                wifiSection
                helpSection
                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(statusIsError ? .red : .secondary)
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .preferredColorScheme(preferDark ? .dark : .light)
            .task { await loadBrightness() }
            .sheet(isPresented: $showWifiSetup) {
                WifiSetupView()
                    .environmentObject(api)
                    .preferredColorScheme(preferDark ? .dark : .light)
            }
            .confirmationDialog(
                "Вернуть Dot в режим настройки?",
                isPresented: $confirmReprovision,
                titleVisibility: .visible
            ) {
                Button("Открыть Dot-Setup", role: .destructive) {
                    Task { await reprovision() }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Dot создаст сеть Dot-Setup. Подключите к ней iPhone и заново введите имя и пароль модема.")
            }
            .confirmationDialog(
                "Сбросить сохранённый адрес?",
                isPresented: $confirmClearHost,
                titleVisibility: .visible
            ) {
                Button("Сбросить", role: .destructive) {
                    api.clearSavedHost()
                    statusMessage = "Адрес сброшен. Нажмите «Найти Dot»."
                    statusIsError = false
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Приложение забудет последний IP и mDNS. Поиск начнётся заново.")
            }
        }
    }

    private var appearanceSection: some View {
        Section("Оформление") {
            Toggle(isOn: $preferDark) {
                Label(preferDark ? "Тёмная тема" : "Светлая тема", systemImage: preferDark ? "moon.fill" : "sun.max.fill")
            }
        }
    }

    private var brightnessSection: some View {
        Section {
            if api.canBrowseGallery || api.isConnected {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Яркость экрана Dot", systemImage: "sun.max")
                        Spacer()
                        Text("\(Int(draftBrightness.rounded()))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $draftBrightness,
                        in: brightnessMin...brightnessMax,
                        step: 1
                    ) { editing in
                        if !editing {
                            Task { await saveBrightness() }
                        }
                    }
                    .disabled(isSavingBrightness || isBusy)
                    if let brightnessError {
                        Text(brightnessError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } else {
                Text("Подключитесь к Dot, чтобы регулировать яркость.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Дисплей")
        } footer: {
            Text("Программная яркость на круге. Значение сохраняется на Dot.")
        }
    }

    private var deviceSection: some View {
        Section("Устройство") {
            LabeledContent("Имя", value: api.status?.device ?? "dot")
            LabeledContent("Адрес", value: api.host)
            if let resolution = api.status?.resolution {
                LabeledContent("Разрешение", value: resolution)
            }
            if let current = api.status?.currentName ?? api.status?.current {
                LabeledContent("На экране", value: current)
            }
            if let mode = api.wifi?.mode {
                LabeledContent("Wi‑Fi", value: mode)
            }
            Button {
                Task {
                    isBusy = true
                    defer { isBusy = false }
                    await api.discoverAndConnect()
                    await loadBrightness()
                    statusMessage = api.canBrowseGallery ? "Dot найден." : (api.errorMessage ?? "Поиск завершён.")
                    statusIsError = !api.canBrowseGallery
                }
            } label: {
                Label("Найти Dot", systemImage: "magnifyingglass")
            }
            .disabled(isBusy)
        }
    }

    private var wifiSection: some View {
        Section("Wi‑Fi") {
            Button {
                showWifiSetup = true
            } label: {
                Label("Мастер настройки Wi‑Fi", systemImage: "wifi")
            }

            Button(role: .destructive) {
                confirmReprovision = true
            } label: {
                Label("Сбросить Wi‑Fi Dot (Dot-Setup)", systemImage: "arrow.counterclockwise")
            }
            .disabled(isBusy)

            Button(role: .destructive) {
                confirmClearHost = true
            } label: {
                Label("Сбросить сохранённый адрес", systemImage: "trash")
            }
        }
    }

    private var helpSection: some View {
        Section("Справка") {
            Button {
                onboardingCompleted = false
                onShowOnboarding()
                dismiss()
            } label: {
                Label("Показать введение", systemImage: "sparkles")
            }
        }
    }

    private func loadBrightness() async {
        guard api.canBrowseGallery || api.isConnected else {
            draftBrightness = Double(api.brightness)
            return
        }
        do {
            let level = try await api.fetchBrightness()
            draftBrightness = Double(level)
            brightnessError = nil
        } catch {
            draftBrightness = Double(api.status?.brightness ?? api.brightness)
        }
    }

    private func saveBrightness() async {
        let level = Int(draftBrightness.rounded())
        isSavingBrightness = true
        defer { isSavingBrightness = false }
        do {
            try await api.setBrightness(level)
            draftBrightness = Double(api.brightness)
            brightnessError = nil
            statusMessage = "Яркость обновлена."
            statusIsError = false
        } catch {
            brightnessError = error.localizedDescription
        }
    }

    private func reprovision() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await api.reprovisionWifi()
            statusMessage = result.message ?? "Dot переходит в Dot-Setup."
            statusIsError = false
            showWifiSetup = true
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(PiAPIClient())
}
