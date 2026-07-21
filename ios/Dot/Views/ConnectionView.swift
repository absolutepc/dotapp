import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var api: PiAPIClient
    @EnvironmentObject private var locationTracker: DotLocationTracker
    let errorMessage: String?
    var onSetupWifi: () -> Void = {}
    var onShowLocation: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)

                Text("Нет связи с Dot")
                    .font(.title2.bold())

                if let seen = locationTracker.lastSeen {
                    Button(action: onShowLocation) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Последнее место Dot", systemImage: "mappin.and.ellipse")
                                .font(.subheadline.weight(.semibold))
                            Text(Self.format(seen.timestamp))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Открыть карту")
                                .font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Первый раз — по шагам")
                        .font(.subheadline.weight(.semibold))
                    Label("Зайдите в Wi‑Fi `Dot-Setup-…` (пароль `dotsetup1`)", systemImage: "1.circle.fill")
                    Label("В приложении введите имя и пароль модема — модем ещё не включайте", systemImage: "2.circle.fill")
                    Label("Выйдите из Dot-Setup, включите Режим модема, найдите Dot", systemImage: "3.circle.fill")
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
                    Label("Подождите несколько секунд — Dot подключится сам", systemImage: "2.circle.fill")
                    Label("Нажмите «Найти автоматически»", systemImage: "3.circle.fill")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Адрес Dot (если нужно вручную)")
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

                Button("Настройка Wi‑Fi (по шагам)") {
                    onSetupWifi()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    ConnectionView(errorMessage: "The Internet connection appears to be offline.")
        .environmentObject(PiAPIClient())
        .environmentObject(DotLocationTracker())
}
