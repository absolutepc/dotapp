import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var api: PiAPIClient
    @Environment(\.dismiss) private var dismiss

    @AppStorage("dot.appearance.dark") private var preferDark = true
    @AppStorage("dot.onboarding.completed") private var onboardingCompleted = true

    @State private var draftBrightness: Double = 100
    @State private var isSavingBrightness = false
    @State private var brightnessError: String?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isBusy = false
    @State private var showWifiSetup = false
    @State private var showReprovisionConfirm = false
    @State private var confirmClearHost = false

    var onShowOnboarding: () -> Void = {}

    /// Reset only when Dot is reachable on the phone hotspot (client).
    private var canResetToSetup: Bool {
        api.canBrowseGallery && api.wifi?.mode == "client" && (api.wifi?.ok == true)
    }

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
                            .foregroundStyle(statusIsError ? Color(red: 1, green: 0.45, blue: 0.5) : DotTheme.secondaryText(dark: preferDark))
                    }
                    .listRowBackground(DotTheme.panel(dark: preferDark))
                }
            }
            .scrollContentBackground(.hidden)
            .background(SpaceBlueBackground(dark: preferDark))
            .tint(DotTheme.toolbarTint(dark: preferDark))
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .dotNavigationChrome(dark: preferDark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .preferredColorScheme(preferDark ? .dark : .light)
            .tint(DotTheme.toolbarTint(dark: preferDark))
            .task { await loadBrightness() }
            .sheet(isPresented: $showWifiSetup) {
                WifiSetupView()
                    .environmentObject(api)
                    .preferredColorScheme(preferDark ? .dark : .light)
                    .tint(DotTheme.toolbarTint(dark: preferDark))
            }
            .sheet(isPresented: $showReprovisionConfirm) {
                ReprovisionConfirmSheet(
                    isBusy: $isBusy,
                    canReset: canResetToSetup
                ) {
                    try await reprovision()
                }
                .environmentObject(api)
                .preferredColorScheme(preferDark ? .dark : .light)
                .tint(DotTheme.toolbarTint(dark: preferDark))
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
            .foregroundStyle(DotTheme.primaryText(dark: preferDark))
        }
        .listRowBackground(DotTheme.panel(dark: preferDark))
        .listRowSeparatorTint(DotTheme.ice.opacity(preferDark ? 0.1 : 0.06))
    }

    private var brightnessSection: some View {
        Section {
            if api.canBrowseGallery || api.isConnected {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Яркость экрана Dot", systemImage: "sun.max")
                            .foregroundStyle(DotTheme.primaryText(dark: preferDark))
                        Spacer()
                        Text("\(Int(draftBrightness.rounded()))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
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
                    .tint(DotTheme.ice)
                    .disabled(isSavingBrightness || isBusy)
                    if let brightnessError {
                        Text(brightnessError)
                            .font(.caption)
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.5))
                    }
                }
            } else {
                Text("Подключитесь к Dot, чтобы регулировать яркость.")
                    .font(.footnote)
                    .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
            }
        } header: {
            Text("Дисплей")
                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
        } footer: {
            Text("Программная яркость на круге. Значение сохраняется на Dot.")
                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
        }
        .listRowBackground(DotTheme.panel(dark: preferDark))
        .listRowSeparatorTint(DotTheme.ice.opacity(preferDark ? 0.1 : 0.06))
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
        .foregroundStyle(DotTheme.primaryText(dark: preferDark))
        .listRowBackground(DotTheme.panel(dark: preferDark))
        .listRowSeparatorTint(DotTheme.ice.opacity(preferDark ? 0.1 : 0.06))
    }

    private var wifiSection: some View {
        Section {
            Button {
                showWifiSetup = true
            } label: {
                Label("Мастер настройки Wi‑Fi", systemImage: "wifi")
            }

            Button(role: .destructive) {
                showReprovisionConfirm = true
            } label: {
                Label("Сбросить Wi‑Fi Dot (Dot-Setup)", systemImage: "arrow.counterclockwise")
            }
            .disabled(isBusy || !canResetToSetup)

            if !canResetToSetup {
                Text("Сброс доступен только когда Dot подключён к Режиму модема. Включите модем и нажмите «Найти Dot».")
                    .font(.footnote)
                    .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
            }

            Button(role: .destructive) {
                confirmClearHost = true
            } label: {
                Label("Сбросить сохранённый адрес", systemImage: "trash")
            }
        } header: {
            Text("Wi‑Fi")
                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
        } footer: {
            Text("Сброс в Dot-Setup отключит Dot от модема и откроет сеть настройки. Нужно подтверждение и живое подключение к точке доступа.")
                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
        }
        .listRowBackground(DotTheme.panel(dark: preferDark))
        .listRowSeparatorTint(DotTheme.ice.opacity(preferDark ? 0.1 : 0.06))
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
        .listRowBackground(DotTheme.panel(dark: preferDark))
        .listRowSeparatorTint(DotTheme.ice.opacity(preferDark ? 0.1 : 0.06))
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

    private func reprovision() async throws {
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await api.reprovisionWifi()
            statusMessage = result.message ?? "Dot переходит в Dot-Setup."
            statusIsError = false
            showReprovisionConfirm = false
            showWifiSetup = true
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
            throw error
        }
    }
}

/// Two-step confirm: acknowledge risk + type СБРОС. Requires hotspot link.
private struct ReprovisionConfirmSheet: View {
    @EnvironmentObject private var api: PiAPIClient
    @Environment(\.dismiss) private var dismiss

    @Binding var isBusy: Bool
    let canReset: Bool
    var onConfirm: () async throws -> Void

    @State private var understood = false
    @State private var typedConfirm = ""
    @State private var localError: String?
    @State private var hotspotStillOk = false

    private let confirmWord = "СБРОС"

    private var typedOk: Bool {
        typedConfirm.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(confirmWord) == .orderedSame
    }

    private var canSubmit: Bool {
        canReset && hotspotStillOk && understood && typedOk && !isBusy
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Это отключит Dot от Режима модема", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Dot перестанет сам подключаться к точке доступа, откроет сеть Dot-Setup и потребует заново пройти настройку Wi‑Fi. Случайный сброс прервёт обычную работу.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Условие") {
                    if canReset && hotspotStillOk {
                        Label("Dot на точке доступа (client) — можно продолжить", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if let ssid = api.wifi?.ssid, !ssid.isEmpty {
                            Text("Сеть: \(ssid)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label("Нет связи с Dot на модеме", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("Включите Режим модема, найдите Dot, затем откройте подтверждение снова.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Проверить связь сейчас") {
                        Task { await refreshHotspotLink() }
                    }
                    .disabled(isBusy)
                }

                Section("Подтверждение") {
                    Toggle("Я понимаю последствия и хочу сбросить Wi‑Fi Dot", isOn: $understood)
                        .disabled(!(canReset && hotspotStillOk) || isBusy)
                    TextField("Введите \(confirmWord)", text: $typedConfirm)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .disabled(!(canReset && hotspotStillOk) || isBusy)
                    Text("Чтобы подтвердить, введите слово \(confirmWord) заглавными буквами.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let localError {
                    Section {
                        Text(localError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await submit() }
                    } label: {
                        if isBusy {
                            ProgressView()
                        } else {
                            Text("Сбросить в Dot-Setup")
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .scrollContentBackground(.hidden)
            .background(SpaceBlueBackground(dark: true))
            .navigationTitle("Подтверждение сброса")
            .navigationBarTitleDisplayMode(.inline)
            .dotNavigationChrome(dark: true)
            .tint(DotTheme.ice)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .disabled(isBusy)
                }
            }
            .task { await refreshHotspotLink() }
        }
    }

    private func refreshHotspotLink() async {
        localError = nil
        do {
            let status = try await api.wifiStatus()
            hotspotStillOk = status.mode == "client" && status.ok
            if !hotspotStillOk {
                localError = "Dot не на точке доступа. Сброс заблокирован."
            }
        } catch {
            hotspotStillOk = false
            localError = error.localizedDescription
        }
    }

    private func submit() async {
        localError = nil
        guard canSubmit else { return }
        // Re-check immediately before the destructive call.
        await refreshHotspotLink()
        guard canReset && hotspotStillOk, understood, typedOk else {
            localError = "Сброс заблокирован: нет связи с модемом или подтверждение неполное."
            return
        }
        do {
            try await onConfirm()
            dismiss()
        } catch {
            localError = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(PiAPIClient())
}
