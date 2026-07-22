import MapKit
import SwiftUI

/// In-app last-seen map for Dot (phone GPS when connected — not Apple Find My).
struct LastSeenLocationView: View {
    @ObservedObject var tracker: DotLocationTracker
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dot.appearance.dark") private var preferDark = true

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    var body: some View {
        NavigationStack {
            ZStack {
                SpaceBlueBackground(dark: preferDark)

                Group {
                    if let seen = tracker.lastSeen {
                        VStack(spacing: 0) {
                            Map(coordinateRegion: $region, annotationItems: [seen]) { item in
                                MapMarker(coordinate: item.coordinate, tint: .cyan)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 0))

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Последнее место Dot")
                                    .font(.headline)
                                    .foregroundStyle(DotTheme.primaryText(dark: preferDark))
                                Text(formatted(seen.timestamp))
                                    .font(.subheadline)
                                    .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
                                Text("Точка записана, когда iPhone был на связи с Dot (обычно машина / Режим модема). Это не Локатор Apple Find My.")
                                    .font(.caption)
                                    .foregroundStyle(DotTheme.secondaryText(dark: preferDark))

                                Button {
                                    tracker.openInMaps()
                                } label: {
                                    Label("Открыть в Картах", systemImage: "map")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(DotPrimaryButtonStyle(dark: preferDark, prominent: true))
                            }
                            .padding()
                            .background(DotTheme.deep.opacity(0.92))
                        }
                    } else {
                        ContentUnavailableFallback(
                            denied: tracker.authorizationDenied,
                            message: tracker.statusMessage,
                            dark: preferDark
                        ) {
                            tracker.requestPermissionIfNeeded()
                            tracker.captureLastSeen(host: nil)
                        }
                    }
                }
            }
            .navigationTitle("Где Dot")
            .navigationBarTitleDisplayMode(.inline)
            .dotNavigationChrome(dark: preferDark)
            .tint(DotTheme.toolbarTint(dark: preferDark))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .onAppear {
                tracker.reloadFromDisk()
                tracker.requestPermissionIfNeeded()
                if let seen = tracker.lastSeen {
                    region = MKCoordinateRegion(
                        center: seen.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )
                }
            }
            .onChange(of: tracker.lastSeen) { seen in
                guard let seen else { return }
                region = MKCoordinateRegion(
                    center: seen.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            }
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct ContentUnavailableFallback: View {
    let denied: Bool
    let message: String?
    var dark: Bool = true
    var onRetry: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 48))
                .foregroundStyle(DotTheme.ice.opacity(0.7))
            Text("Пока нет сохранённой точки")
                .font(.title3.bold())
                .foregroundStyle(DotTheme.primaryText(dark: dark))
            Text(
                denied
                    ? "Разрешите геолокацию в Настройках → Dot, затем снова подключитесь к устройству."
                    : "Подключитесь к Dot (Режим модема) — приложение запомнит место iPhone в этот момент."
            )
            .font(.subheadline)
            .foregroundStyle(DotTheme.secondaryText(dark: dark))
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Запросить геолокацию", action: onRetry)
                .buttonStyle(DotPrimaryButtonStyle(dark: dark, prominent: true))
                .padding(.horizontal, 24)
        }
        .padding()
    }
}

#Preview {
    LastSeenLocationView(tracker: DotLocationTracker())
}
