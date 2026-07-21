import SwiftUI

/// First-time setup as strict steps: Dot-Setup → save modem name/password → leave Wi‑Fi → enable hotspot → find Dot.
/// iPhone cannot stay on Dot-Setup Wi‑Fi and run Personal Hotspot at the same time — never ask for both at once.
struct WifiSetupView: View {
    @EnvironmentObject private var api: PiAPIClient
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable {
        case joinSetup = 1
        case enterCredentials = 2
        case enableHotspot = 3
        case findDot = 4
    }

    @State private var step: Step = .joinSetup
    @State private var hotspotSSID = ""
    @State private var hotspotPassword = ""
    @State private var isBusy = false
    @State private var statusText: String?
    @State private var statusIsError = false
    @State private var deviceReachable = false
    @State private var setupSsidShown: String?
    @State private var credentialsSaved = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Form {
                    switch step {
                    case .joinSetup:
                        joinSetupSections
                    case .enterCredentials:
                        credentialsSections
                    case .enableHotspot:
                        enableHotspotSections
                    case .findDot:
                        findDotSections
                    }

                    if let statusText {
                        Section {
                            Text(statusText)
                                .font(.footnote)
                                .foregroundStyle(statusIsError ? .red : .secondary)
                        }
                    }
                }

                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(.bar)
            }
            .navigationTitle("Настройка Wi‑Fi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task {
                if step == .joinSetup {
                    await checkSetupLink()
                }
            }
        }
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Шаг \(step.rawValue) из \(Step.allCases.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count))
                .tint(.accentColor)
            Text(stepTitle)
                .font(.title3.bold())
            Text(stepSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepTitle: String {
        switch step {
        case .joinSetup: return "Подключитесь к Dot"
        case .enterCredentials: return "Имя и пароль модема"
        case .enableHotspot: return "Включите Режим модема"
        case .findDot: return "Найдите Dot"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .joinSetup:
            return "Сейчас нужен только Wi‑Fi Dot-Setup. Режим модема пока не включайте."
        case .enterCredentials:
            return "Посмотрите имя и пароль в Настройки → Режим модема — но переключатель модема оставьте выключенным. Вы всё ещё в Dot-Setup."
        case .enableHotspot:
            return "Данные уже на Dot. Теперь выйдите из Dot-Setup и только после этого включите Режим модема."
        case .findDot:
            return "Модем должен быть включён. Dot подключится к нему сам — найдём его в сети."
        }
    }

    // MARK: - Step 1

    @ViewBuilder
    private var joinSetupSections: some View {
        Section {
            Label("На iPhone: Настройки → Wi‑Fi", systemImage: "1.circle.fill")
            Label("Выберите сеть `Dot-Setup-…`", systemImage: "2.circle.fill")
            Label("Пароль: `dotsetup1`", systemImage: "3.circle.fill")
            Label("Вернитесь в приложение Dot", systemImage: "4.circle.fill")
        } footer: {
            Text("Режим модема на этом шаге не нужен и мешает — iPhone не может одновременно быть в чужом Wi‑Fi и раздавать модем.")
        }

        Section("Связь с Dot") {
            HStack {
                Circle()
                    .fill(deviceReachable ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(
                    deviceReachable
                        ? "Dot на связи (\(api.host))"
                        : "Пока нет связи — зайдите в Dot-Setup"
                )
                .font(.subheadline)
                Spacer()
                if isBusy {
                    ProgressView()
                }
            }
            if let setupSsidShown, !setupSsidShown.isEmpty {
                Text("Сеть настройки: \(setupSsidShown)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Проверить связь") {
                Task { await checkSetupLink() }
            }
            .disabled(isBusy)
        }
    }

    // MARK: - Step 2

    @ViewBuilder
    private var credentialsSections: some View {
        Section {
            Text("Откройте Настройки → Режим модема. Запомните имя точки и пароль. Переключатель «Режим модема» пока не включайте.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        Section("Данные точки") {
            TextField("Имя точки (SSID)", text: $hotspotSSID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Пароль (мин. 8 символов)", text: $hotspotPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }

        Section {
            Button {
                Task { await saveCredentials() }
            } label: {
                if isBusy {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(credentialsSaved ? "Сохранено на Dot" : "Отправить на Dot")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(
                isBusy
                    || credentialsSaved
                    || hotspotSSID.trimmingCharacters(in: .whitespaces).isEmpty
                    || hotspotPassword.count < 8
                    || !deviceReachable
            )
        } footer: {
            Text("Пока вы в Dot-Setup, Dot получит имя и пароль. Подключение к модему будет на следующем шаге.")
        }
    }

    // MARK: - Step 3

    @ViewBuilder
    private var enableHotspotSections: some View {
        Section {
            Label("Откройте Настройки → Wi‑Fi", systemImage: "1.circle.fill")
            Label("Отключитесь от `Dot-Setup-…` (или выберите другую сеть / выключите Wi‑Fi)", systemImage: "2.circle.fill")
            Label("Настройки → Режим модема → включите переключатель", systemImage: "3.circle.fill")
            Label("Держите экран разблокированным 10–15 секунд", systemImage: "4.circle.fill")
        } footer: {
            Text("Сначала выйдите из Dot-Setup, потом включите модем. Иначе iPhone не даст раздавать интернет.")
        }
    }

    // MARK: - Step 4

    @ViewBuilder
    private var findDotSections: some View {
        Section {
            Label("Режим модема включён", systemImage: "checkmark.circle")
            Label("Подождите несколько секунд — Dot сам заходит в модем", systemImage: "antenna.radiowaves.left.and.right")
            Label("Нажмите «Найти Dot» ниже", systemImage: "magnifyingglass")
        }

        Section {
            Button {
                Task { await findOnHotspot() }
            } label: {
                if isBusy {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Найти Dot")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isBusy)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step != .joinSetup {
                Button("Назад") {
                    goBack()
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }

            Spacer(minLength: 0)

            Button(primaryButtonTitle) {
                Task { await primaryAction() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canPrimary || isBusy)
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .joinSetup: return "Далее"
        case .enterCredentials: return credentialsSaved ? "Далее" : "Сначала отправьте на Dot"
        case .enableHotspot: return "Модем включён — далее"
        case .findDot: return api.canBrowseGallery ? "Готово" : "Найти Dot"
        }
    }

    private var canPrimary: Bool {
        switch step {
        case .joinSetup: return deviceReachable
        case .enterCredentials: return credentialsSaved
        case .enableHotspot: return true
        case .findDot: return true
        }
    }

    private func goBack() {
        statusText = nil
        statusIsError = false
        switch step {
        case .joinSetup:
            break
        case .enterCredentials:
            step = .joinSetup
        case .enableHotspot:
            // Credentials already on Dot; going back allows re-send if needed.
            credentialsSaved = false
            step = .enterCredentials
        case .findDot:
            step = .enableHotspot
        }
    }

    private func primaryAction() async {
        switch step {
        case .joinSetup:
            await checkSetupLink()
            guard deviceReachable else { return }
            statusText = nil
            step = .enterCredentials
        case .enterCredentials:
            guard credentialsSaved else { return }
            statusText = nil
            step = .enableHotspot
        case .enableHotspot:
            statusText = nil
            step = .findDot
        case .findDot:
            if api.canBrowseGallery {
                dismiss()
            } else {
                await findOnHotspot()
            }
        }
    }

    // MARK: - Actions

    private func checkSetupLink() async {
        isBusy = true
        defer { isBusy = false }
        statusText = "Ищу Dot в сети настройки…"
        statusIsError = false
        api.host = "192.168.4.1"

        do {
            try await api.ensureReachableForSetup()
            let status = try await api.wifiStatus()
            deviceReachable = true
            setupSsidShown = status.setupSsid
            if let setup = status.setupSsid, !setup.isEmpty {
                statusText = "Сеть \(setup) — можно переходить к данным модема."
            } else if status.isSetupAP || status.mode == "setup_ap" {
                statusText = "Dot в режиме настройки. Можно далее."
            } else {
                statusText = "Dot отвечает (\(status.mode)). Для первой настройки нужен режим Dot-Setup."
            }
        } catch {
            deviceReachable = false
            statusIsError = true
            statusText = "Нет связи. Подключите iPhone к Wi‑Fi Dot-Setup-… (пароль dotsetup1) и нажмите «Проверить связь»."
        }
    }

    private func saveCredentials() async {
        let ssid = hotspotSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ssid.isEmpty, hotspotPassword.count >= 8 else {
            statusIsError = true
            statusText = "Укажите имя точки и пароль не короче 8 символов."
            return
        }

        isBusy = true
        defer { isBusy = false }
        statusIsError = false
        statusText = "Отправляю имя и пароль на Dot…"

        do {
            let response = try await api.configureWifi(ssid: ssid, password: hotspotPassword)
            credentialsSaved = true
            deviceReachable = false
            statusText = response.message
                ?? "Данные сохранены. Дальше выйдите из Dot-Setup и включите Режим модема."
            // Brief wait: setup AP will drop — that is expected.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        } catch {
            credentialsSaved = false
            statusIsError = true
            statusText = error.localizedDescription
        }
    }

    private func findOnHotspot() async {
        isBusy = true
        defer { isBusy = false }
        statusIsError = false
        statusText = "Ищу Dot в сети модема…"

        await api.discoverAndConnect()

        if api.canBrowseGallery {
            statusIsError = false
            statusText = "Готово. Dot найден: \(api.host)."
            dismiss()
            return
        }

        statusIsError = true
        statusText = api.errorMessage
            ?? "Пока не найден. Проверьте, что Режим модема включён, экран не заблокирован, и повторите."
    }
}

#Preview {
    WifiSetupView()
        .environmentObject(PiAPIClient())
}
