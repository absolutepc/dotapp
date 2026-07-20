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
                    Label("Обычная работа: включите Режим модема на iPhone", systemImage: "1.circle.fill")
                    Label("Pi подключится сам (после первой настройки)", systemImage: "2.circle.fill")
                    Label("Введите IP Pi ниже и нажмите Refresh", systemImage: "3.circle.fill")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Адрес Pi")
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

                Button("Настройка Wi‑Fi (первый раз)") {
                    // Setup portal expects setup AP address
                    if api.host != "192.168.4.1" {
                        api.host = "192.168.4.1"
                    }
                    onSetupWifi()
                }
                .buttonStyle(.borderedProminent)

                Text("Перед настройкой подключите iPhone к Wi‑Fi `Dot-Setup-…` на Pi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

#Preview {
    ConnectionView(errorMessage: "The Internet connection appears to be offline.")
        .environmentObject(PiAPIClient())
}
