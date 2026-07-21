import SwiftUI

/// First-time setup: while on Dot-Setup Wi-Fi, send Personal Hotspot credentials to Dot.
struct WifiSetupView: View {
    @EnvironmentObject private var api: PiAPIClient
    @Environment(\.dismiss) private var dismiss

    @State private var hotspotSSID = ""
    @State private var hotspotPassword = ""
    @State private var isSubmitting = false
    @State private var isChecking = false
    @State private var statusText: String?
    @State private var statusIsError = false
    @State private var didSucceed = false
    @State private var deviceReachable = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Первое подключение (без терминала)")
                            .font(.headline)
                        Label("На iPhone откройте Wi‑Fi и зайдите в `Dot-Setup-…`", systemImage: "1.circle.fill")
                        Label("Пароль сети настройки: `dotsetup1`", systemImage: "2.circle.fill")
                        Label("Ниже введите имя и пароль Режима модема iPhone", systemImage: "3.circle.fill")
                        Label("После успеха включите Режим модема — Dot подключится сам", systemImage: "4.circle.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Section("Связь с Dot") {
                    HStack {
                        Circle()
                            .fill(deviceReachable ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(deviceReachable ? "Dot на связи (\(api.host))" : "Dot не найден — зайдите в Dot-Setup")
                            .font(.subheadline)
                        Spacer()
                        if isChecking {
                            ProgressView()
                        }
                    }
                    Button("Проверить связь") {
                        Task { await checkLink() }
                    }
                    .disabled(isChecking || isSubmitting)
                }

                Section("Режим модема iPhone") {
                    TextField("Имя точки (SSID)", text: $hotspotSSID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Пароль (мин. 8 символов)", text: $hotspotPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Настройки → Режим модема. Имя часто вида «iPhone …».")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(didSucceed ? "Готово" : "Сохранить и подключить")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(
                        isSubmitting
                            || didSucceed
                            || hotspotSSID.trimmingCharacters(in: .whitespaces).isEmpty
                            || hotspotPassword.count < 8
                    )

                    if let statusText {
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(statusIsError ? .red : .secondary)
                    }
                }

                if didSucceed {
                    Section("Дальше") {
                        Text("1. Выйдите из Dot-Setup и включите Режим модема.\n2. Подождите 5–15 секунд.\n3. Закройте этот экран — приложение само найдёт адрес Dot.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Найти Dot в сети модема") {
                            Task {
                                await api.discoverAndConnect()
                                if api.isConnected, api.wifi?.mode == "client" {
                                    statusIsError = false
                                    statusText = "Найден Dot: \(api.host)"
                                    dismiss()
                                } else {
                                    statusIsError = true
                                    statusText = "Пока не найден. Убедитесь, что Режим модема включён, и повторите."
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Настройка Wi‑Fi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task { await checkLink() }
        }
    }

    private func checkLink() async {
        isChecking = true
        defer { isChecking = false }
        api.host = "192.168.4.1"
        do {
            let status = try await api.wifiStatus()
            deviceReachable = true
            statusIsError = false
            if let setup = status.setupSsid, !setup.isEmpty {
                statusText = "Сеть настройки: \(setup). Можно вводить Режим модема."
            } else if status.isSetupAP {
                statusText = "Dot в режиме настройки. Можно вводить Режим модема."
            } else {
                statusText = "Dot отвечает (\(status.mode)). Для смены точки снова откройте Dot-Setup на устройстве."
            }
        } catch {
            deviceReachable = false
            statusIsError = true
            statusText = "Нет связи с 192.168.4.1. Подключите iPhone к Wi‑Fi Dot-Setup-… (пароль dotsetup1)."
        }
    }

    private func submit() async {
        let ssid = hotspotSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ssid.isEmpty == false, hotspotPassword.count >= 8 else {
            statusIsError = true
            statusText = "Укажите SSID и пароль не короче 8 символов"
            return
        }

        isSubmitting = true
        statusIsError = false
        statusText = "Проверяю связь и отправляю на Dot…"
        defer { isSubmitting = false }

        do {
            let response = try await api.configureWifi(ssid: ssid, password: hotspotPassword)
            didSucceed = true
            deviceReachable = false
            statusText = response.message
                ?? "Dot переключается на точку iPhone. Включите Режим модема и нажмите «Найти Dot»."
            await pollAfterSwitch()
        } catch {
            statusIsError = true
            statusText = error.localizedDescription
            didSucceed = false
        }
    }

    private func pollAfterSwitch() async {
        for _ in 0..<6 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if let status = try? await api.wifiStatus() {
                if status.mode == "client", status.ok, let ip = status.ip, !ip.isEmpty {
                    api.host = ip
                    statusIsError = false
                    statusText = "Подключено к «\(status.ssid ?? hotspotSSID)». Адрес Dot: \(ip)."
                    return
                }
                if status.mode == "error" {
                    statusIsError = true
                    statusText = status.message ?? "Ошибка подключения"
                    didSucceed = false
                    return
                }
                if let message = status.message {
                    statusText = message
                }
            } else {
                // Expected when Dot leaves setup AP — phone must enable Personal Hotspot next.
                statusIsError = false
                statusText = "Сеть настройки пропала — так и должно быть. Включите Режим модема и нажмите «Найти Dot в сети модема»."
                return
            }
        }
    }
}

#Preview {
    WifiSetupView()
        .environmentObject(PiAPIClient())
}
