import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var api: PiAPIClient
    @EnvironmentObject private var locationTracker: DotLocationTracker
    @AppStorage("dot.appearance.dark") private var preferDark = true

    let errorMessage: String?
    var onSetupWifi: () -> Void = {}
    var onShowLocation: () -> Void = {}
    var onShowOnboarding: () -> Void = {}

    @State private var iconPulse = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(DotTheme.cobalt.opacity(0.35))
                        .frame(width: 120, height: 120)
                        .blur(radius: 18)
                        .scaleEffect(iconPulse ? 1.08 : 0.95)

                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DotTheme.ice, DotTheme.horizon],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .padding(.top, 8)

                Text("Dot")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(DotTheme.primaryText(dark: preferDark))

                Text("Нет связи с устройством")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DotTheme.secondaryText(dark: preferDark))

                if let seen = locationTracker.lastSeen {
                    Button(action: onShowLocation) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Последнее место Dot", systemImage: "mappin.and.ellipse")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DotTheme.primaryText(dark: preferDark))
                            Text(Self.format(seen.timestamp))
                                .font(.caption)
                                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
                            Text("Открыть карту")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(DotTheme.ice)
                        }
                        .dotPanel(dark: preferDark)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Первый раз — по шагам")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DotTheme.primaryText(dark: preferDark))
                    stepRow(1, "Зайдите в Wi‑Fi `Dot-Setup-…` (пароль `dotsetup1`)")
                    stepRow(2, "В приложении введите имя и пароль модема — модем ещё не включайте")
                    stepRow(3, "Выйдите из Dot-Setup, включите Режим модема, найдите Dot")
                }
                .font(.subheadline)
                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
                .dotPanel(dark: preferDark)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Обычная работа")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DotTheme.primaryText(dark: preferDark))
                    stepRow(1, "Включите Режим модема на iPhone")
                    stepRow(2, "Подождите несколько секунд — Dot подключится сам")
                    stepRow(3, "Нажмите «Найти автоматически»")
                }
                .font(.subheadline)
                .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
                .dotPanel(dark: preferDark)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Адрес Dot (если нужно вручную)")
                        .font(.caption)
                        .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
                    TextField("192.168.4.1 или 172.20.10.x", text: $api.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .padding(14)
                        .foregroundStyle(DotTheme.primaryText(dark: preferDark))
                        .background(DotTheme.panel(dark: preferDark), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(DotTheme.panelStroke(dark: preferDark), lineWidth: 1)
                        }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                        .multilineTextAlignment(.center)
                }

                Button("Найти автоматически") {
                    Task { await api.discoverAndConnect() }
                }
                .buttonStyle(DotPrimaryButtonStyle(dark: preferDark, prominent: true))

                Button("Настройка Wi‑Fi (по шагам)") {
                    onSetupWifi()
                }
                .buttonStyle(DotPrimaryButtonStyle(dark: preferDark, prominent: false))

                Button("Показать введение") {
                    onShowOnboarding()
                }
                .buttonStyle(DotPrimaryButtonStyle(dark: preferDark, prominent: false))
            }
            .padding(20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                iconPulse = true
            }
        }
    }

    private func stepRow(_ n: Int, _ text: String) -> some View {
        Label(text, systemImage: "\(n).circle.fill")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(DotTheme.ice, DotTheme.secondaryText(dark: preferDark))
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
    ZStack {
        SpaceBlueBackground(dark: true)
        ConnectionView(errorMessage: "The Internet connection appears to be offline.")
    }
    .environmentObject(PiAPIClient())
    .environmentObject(DotLocationTracker())
}
