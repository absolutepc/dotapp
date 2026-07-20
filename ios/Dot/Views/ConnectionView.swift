import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var api: PiAPIClient
    let errorMessage: String?
    var onSetupWifi: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)

                Text("Нет связи с Dot")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    Text("Первый раз")
                        .font(.subheadline.weight(.semibold))
                    Label("На Pi должна появиться сеть `Dot-Setup-…` (сама после установки)", systemImage: "1.circle.fill")
                    Label("Подключите iPhone к ней (пароль: `dotsetup1`)", systemImage: "2.circle.fill")
                    Label("Нажмите «Настройка Wi‑Fi» и введите Режим модема", systemImage: "3.circle.fill")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Обычная работа")
                        .font(.subheadline.weight(.semibold))
                    Label("Включите Режим модема на iPhone", systemImage: "1.circle.fill")
                    Label("Подождите несколько секунд — Pi подключится сам", systemImage: "2.circle.fill")
                    Label("Нажмите «Найти автоматически»", systemImage: "3.circle.fill")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Адрес Pi (если нужно вручную)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("192.168.4.1 или 172.20.10.x", text: $api.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button("Найти автоматически") {
                    Task { await api.discoverAndConnect() }
                }
                .buttonStyle(.bordered)

                Button("Настройка Wi‑Fi (первый раз)") {
                    api.host = "192.168.4.1"
                    onSetupWifi()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

#Preview {
    ConnectionView(errorMessage: "The Internet connection appears to be offline.")
        .environmentObject(PiAPIClient())
}
