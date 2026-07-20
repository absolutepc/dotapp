import SwiftUI

/// First-time setup: while on Dot-Setup Wi-Fi, send Personal Hotspot credentials to the Pi.
struct WifiSetupView: View {
    @EnvironmentObject private var api: PiAPIClient
    @Environment(\.dismiss) private var dismiss

    @State private var hotspotSSID = ""
    @State private var hotspotPassword = ""
    @State private var isSubmitting = false
    @State private var statusText: String?
    @State private var statusIsError = false
    @State private var didSucceed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Подключитесь к сети настройки Pi (`Dot-Setup-…`), затем введите имя и пароль **Режима модема** iPhone. Safari не нужен.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Режим модема iPhone") {
                    TextField("Имя точки (SSID)", text: $hotspotSSID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Пароль (мин. 8 символов)", text: $hotspotPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Адрес Pi сейчас") {
                    TextField("Напр. 192.168.4.1", text: $api.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                    Text("В режиме настройки обычно `192.168.4.1`. После успеха Pi получит другой IP в сети модема.")
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
                    .disabled(isSubmitting || didSucceed || hotspotSSID.trimmingCharacters(in: .whitespaces).isEmpty || hotspotPassword.count < 8)

                    if let statusText {
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(statusIsError ? .red : .secondary)
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
        statusText = "Отправляю на Pi…"
        defer { isSubmitting = false }

        do {
            let response = try await api.configureWifi(ssid: ssid, password: hotspotPassword)
            didSucceed = true
            statusText = response.message
                ?? "Pi переключается на точку iPhone. Включите Режим модема, подождите несколько секунд, затем укажите новый IP Pi и нажмите Refresh."
            // Poll briefly while still on setup network; connection will drop — that's OK.
            await pollAfterSwitch()
        } catch {
            statusIsError = true
            statusText = error.localizedDescription
                + " Убедитесь, что телефон в сети Dot-Setup и адрес Pi = 192.168.4.1"
        }
    }

    private func pollAfterSwitch() async {
        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if let status = try? await api.wifiStatus() {
                if status.mode == "client", status.ok, let ip = status.ip, !ip.isEmpty {
                    api.host = ip
                    statusIsError = false
                    statusText = "Подключено к «\(status.ssid ?? hotspotSSID)». IP Pi: \(ip). Включите Режим модема и закройте этот экран."
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
                // Expected when Pi leaves setup AP
                statusIsError = false
                statusText = "Связь с сетью настройки пропала — так и должно быть. Включите Режим модема на iPhone, найдите IP Pi и введите его на экране подключения."
                return
            }
        }
    }
}

#Preview {
    WifiSetupView()
        .environmentObject(PiAPIClient())
}
