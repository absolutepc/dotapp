import SwiftUI

/// First-time setup as strict steps: Dot-Setup → save modem name/password → leave Wi‑Fi → enable hotspot → find Dot.
/// iPhone cannot stay on Dot-Setup Wi‑Fi and run Personal Hotspot at the same time — never ask for both at once.
struct WifiSetupView: View {
    @EnvironmentObject private var api: PiAPIClient
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dot.appearance.dark") private var preferDark = true

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
    @State private var inSetupMode = false
    @State private var setupSsidShown: String?
    @State private var credentialsSaved = false
    @State private var hotspotJoinOrdered = false

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBlueBackground(dark: preferDark)

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
                                    .foregroundStyle(statusIsError ? Color(red: 1, green: 0.55, blue: 0.55) : DotTheme.secondaryText(dark: preferDark))
                            }
                            .listRowBackground(DotTheme.panel(dark: preferDark))
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .tint(DotTheme.toolbarTint(dark: preferDark))

                    bottomBar
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(DotTheme.deep.opacity(preferDark ? 0.96 : 0))
                        .background(preferDark ? Color.clear : Color.white)
                }
            }
            .navigationTitle("Настройка Wi‑Fi")
            .navigationBarTitleDisplayMode(.inline)
            .dotNavigationChrome(dark: preferDark)
            .tint(DotTheme.toolbarTint(dark: preferDark))
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
                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
            ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count))
                .tint(DotTheme.toolbarTint(dark: preferDark))
            Text(stepTitle)
                .font(.title3.bold())
                .foregroundStyle(DotTheme.primaryText(dark: preferDark))
            Text(stepSubtitle)
                .font(.subheadline)
                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
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
            return "Пока оставайтесь в Wi‑Fi Dot-Setup. Нажмите кнопку — Dot запомнит команду на выход. Сразу после этого выйдите из Dot-Setup и включите модем."
        case .findDot:
            return "Модем включён, экран разблокирован. Подождите 10–20 секунд — Dot подключается один раз, без повторных обрывов."
        }
    }

    // MARK: - Step 1

    @ViewBuilder
    private var joinSetupSections: some View {
        Section {
            setupStepRow(1, "На iPhone: Настройки → Wi‑Fi", done: joinMicroDone(1))
            setupStepRow(2, "Выберите сеть `Dot-Setup-…`", done: joinMicroDone(2))
            setupStepRow(3, "Пароль: `dotsetup1`", done: joinMicroDone(3))
            setupStepRow(4, "Вернитесь в приложение Dot", done: joinMicroDone(4))
        } footer: {
            Text("Режим модема на этом шаге не нужен и мешает — iPhone не может одновременно быть в чужом Wi‑Fi и раздавать модем.")
                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
        }
        .listRowBackground(DotTheme.panel(dark: preferDark))
        .listRowSeparatorTint(DotTheme.ice.opacity(preferDark ? 0.1 : 0.06))

        Section("Связь с Dot") {
            HStack {
                Circle()
                    .fill(inSetupMode ? DotTheme.success : (deviceReachable ? Color.orange : Color.red))
                    .frame(width: 8, height: 8)
                Text(setupLinkLabel)
                    .font(.subheadline)
                    .foregroundStyle(DotTheme.primaryText(dark: preferDark))
                Spacer()
                if isBusy {
                    ProgressView()
                }
            }
            if let setupSsidShown, !setupSsidShown.isEmpty {
                Text("Сеть настройки: \(setupSsidShown)")
                    .font(.caption)
                    .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
            }
            Button("Проверить связь") {
                Task { await checkSetupLink() }
            }
            .disabled(isBusy)
        }
        .listRowBackground(DotTheme.panel(dark: preferDark))
        .listRowSeparatorTint(DotTheme.ice.opacity(preferDark ? 0.1 : 0.06))
    }

    private var setupLinkLabel: String {
        if inSetupMode {
            return "Dot в режиме настройки (\(api.host))"
        }
        if deviceReachable {
            return "Dot отвечает, но не в Dot-Setup"
        }
        return "Пока нет связи — зайдите в Dot-Setup"
    }

    /// Micro-steps on the Dot-Setup join screen turn green as the link comes up.
    private func joinMicroDone(_ n: Int) -> Bool {
        switch n {
        case 1:
            return deviceReachable || inSetupMode
        case 2, 3, 4:
            return inSetupMode
        default:
            return false
        }
    }

    private func setupStepRow(
        _ number: Int,
        _ text: String,
        done: Bool,
        pendingSymbol: String? = nil
    ) -> some View {
        Label {
            Text(text)
                .foregroundStyle(DotTheme.primaryText(dark: preferDark))
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : (pendingSymbol ?? "\(number).circle.fill"))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(done ? DotTheme.success : DotTheme.stepPending(dark: preferDark))
                .accessibilityLabel(done ? "Шаг \(number) выполнен" : "Шаг \(number)")
        }
        .animation(.easeInOut(duration: 0.28), value: done)
    }

    // MARK: - Step 2

    @ViewBuilder
    private var credentialsSections: some View {
        Section {
            Text("Откройте Настройки → Режим модема. Запомните имя точки и пароль. Переключатель «Режим модема» пока не включайте.")
                .font(.subheadline)
                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
        }
        .listRowBackground(DotTheme.panel(dark: preferDark))

        Section("Данные точки") {
            TextField("Имя точки (SSID)", text: $hotspotSSID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Пароль (мин. 8 символов)", text: $hotspotPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .listRowBackground(DotTheme.panel(dark: preferDark))
        .listRowSeparatorTint(DotTheme.ice.opacity(preferDark ? 0.1 : 0.06))

        Section {
            Button {
                Task { await saveCredentials() }
            } label: {
                if isBusy {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(credentialsSaved ? "Сохранено на Dot" : "Сохранить на Dot")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(
                isBusy
                    || credentialsSaved
                    || hotspotSSID.trimmingCharacters(in: .whitespaces).isEmpty
                    || hotspotPassword.count < 8
                    || !inSetupMode
            )
        } footer: {
            Text("Пока вы в Dot-Setup, Dot только запомнит имя и пароль. К модему он подключится на следующем шаге — после включения модема.")
                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
        }
        .listRowBackground(DotTheme.panel(dark: preferDark))
    }

    @ViewBuilder
    private var enableHotspotSections: some View {
        Section {
            setupStepRow(1, "Останьтесь в Wi‑Fi `Dot-Setup-…`", done: true)
            setupStepRow(2, "Нажмите «Подключить Dot» ниже", done: hotspotJoinOrdered)
            setupStepRow(3, "Сразу после этого выйдите из Dot-Setup", done: hotspotJoinOrdered)
            setupStepRow(4, "Включите Режим модема + «Максимальная совместимость»", done: hotspotJoinOrdered)
        } footer: {
            Text("Важно: команду «подключить» нужно отправить ещё из Dot-Setup. Иначе Dot не узнает, что пора выходить. Подключение к модему будет одно — без цикла обрывов.")
                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
        }
        .listRowBackground(DotTheme.panel(dark: preferDark))
        .listRowSeparatorTint(DotTheme.ice.opacity(preferDark ? 0.1 : 0.06))
    }

    @ViewBuilder
    private var findDotSections: some View {
        Section {
            setupStepRow(1, "Режим модема включён", done: true, pendingSymbol: "checkmark.circle")
            setupStepRow(
                2,
                "Подождите несколько секунд — Dot сам заходит в модем",
                done: api.canBrowseGallery,
                pendingSymbol: "antenna.radiowaves.left.and.right"
            )
            setupStepRow(
                3,
                "Нажмите «Найти Dot» ниже",
                done: api.canBrowseGallery,
                pendingSymbol: "magnifyingglass"
            )
        }
        .listRowBackground(DotTheme.panel(dark: preferDark))
        .listRowSeparatorTint(DotTheme.ice.opacity(preferDark ? 0.1 : 0.06))

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
        .listRowBackground(DotTheme.panel(dark: preferDark))
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step != .joinSetup {
                Button("Назад") {
                    goBack()
                }
                .buttonStyle(DotPrimaryButtonStyle(dark: preferDark, prominent: false, expand: false))
                .disabled(isBusy)
            }

            Spacer(minLength: 0)

            Button(primaryButtonTitle) {
                Task { await primaryAction() }
            }
            .buttonStyle(DotPrimaryButtonStyle(dark: preferDark, prominent: true, expand: true))
            .disabled(!canPrimary || isBusy)
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .joinSetup: return "Далее"
        case .enterCredentials: return credentialsSaved ? "Далее" : "Сначала сохраните на Dot"
        case .enableHotspot: return "Модем включён — подключить Dot"
        case .findDot: return api.canBrowseGallery ? "Готово" : "Найти Dot"
        }
    }

    private var canPrimary: Bool {
        switch step {
        case .joinSetup: return inSetupMode
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
            hotspotJoinOrdered = false
            step = .enterCredentials
        case .findDot:
            step = .enableHotspot
        }
    }

    private func primaryAction() async {
        switch step {
        case .joinSetup:
            await checkSetupLink()
            guard inSetupMode else { return }
            statusText = nil
            step = .enterCredentials
        case .enterCredentials:
            guard credentialsSaved else { return }
            statusText = nil
            step = .enableHotspot
        case .enableHotspot:
            await startHotspotJoin()
        case .findDot:
            if api.canBrowseGallery {
                dismiss()
            } else {
                await findOnHotspot()
            }
        }
    }

    private func startHotspotJoin() async {
        isBusy = true
        defer { isBusy = false }
        statusIsError = false
        statusText = "Отправляю команду подключения (ещё из Dot-Setup)…"

        do {
            api.host = "192.168.4.1"
            let response = try await api.connectHotspot()
            withAnimation {
                hotspotJoinOrdered = true
            }
            statusText = (response.message ?? "Команда принята.")
                + " Теперь выйдите из Dot-Setup и включите Режим модема."
            inSetupMode = false
            deviceReachable = false
            step = .findDot
        } catch {
            statusIsError = true
            statusText =
                "Нет связи с Dot-Setup. Вернитесь в Wi‑Fi Dot-Setup-… (пароль dotsetup1), затем снова нажмите кнопку."
        }
    }

    // MARK: - Actions

    private func checkSetupLink() async {
        isBusy = true
        defer { isBusy = false }
        statusText = "Ищу Dot в сети настройки…"
        statusIsError = false
        inSetupMode = false
        api.host = "192.168.4.1"

        do {
            try await api.ensureReachableForSetup()
            let status = try await api.wifiStatus()
            setupSsidShown = status.setupSsid
            let setupReady = status.mode == "setup_ap" || (status.setupSsid?.isEmpty == false)
            withAnimation(.easeInOut(duration: 0.28)) {
                deviceReachable = true
                inSetupMode = setupReady
            }
            if setupReady {
                statusIsError = false
                if let setup = status.setupSsid, !setup.isEmpty {
                    statusText = "Сеть \(setup) — можно нажать «Далее»."
                } else {
                    statusText = "Dot в режиме настройки. Можно нажать «Далее»."
                }
            } else {
                statusIsError = true
                statusText =
                    "Dot отвечает (\(status.mode)), но не в Dot-Setup. На Pi выполните: sudo dot-enter-setup-ap — затем снова «Проверить связь»."
            }
        } catch {
            withAnimation(.easeInOut(duration: 0.28)) {
                deviceReachable = false
                inSetupMode = false
            }
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
        statusText = "Сохраняю имя и пароль на Dot (без подключения)…"

        do {
            // applyNow: false — stay on Setup AP; join happens after modem is on.
            let response = try await api.configureWifi(ssid: ssid, password: hotspotPassword, applyNow: false)
            credentialsSaved = true
            statusText = response.message
                ?? "Сохранено. Дальше выйдите из Dot-Setup и включите Режим модема."
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
