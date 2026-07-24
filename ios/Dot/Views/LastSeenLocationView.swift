import MapKit
import SwiftUI

/// In-app last-seen map for Dot (phone GPS when connected — not Apple Find My).
struct LastSeenLocationView: View {
    @ObservedObject var tracker: DotLocationTracker
    @EnvironmentObject private var api: PiAPIClient
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
                                if seen.accuracy > 0 {
                                    Text("Точность ±\(Int(seen.accuracy.rounded())) м")
                                        .font(.caption)
                                        .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
                                }
                                Text("Точка записана, когда iPhone был на связи с Dot (обычно машина / Режим модема). Это не Локатор Apple Find My.")
                                    .font(.caption)
                                    .foregroundStyle(DotTheme.secondaryText(dark: preferDark))

                                if tracker.isCapturing {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text(tracker.statusMessage ?? "Обновляем…")
                                            .font(.caption)
                                            .foregroundStyle(DotTheme.secondaryText(dark: preferDark))
                                    }
                                } else if let message = tracker.statusMessage {
                                    Text(message)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }

                                Button {
                                    tracker.captureLastSeen(host: api.host.isEmpty ? seen.host : api.host)
                                } label: {
                                    Label("Обновить точку", systemImage: "location.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(DotPrimaryButtonStyle(dark: preferDark, prominent: false))
                                .disabled(tracker.isCapturing)

                                Button {
                                    tracker.openInMaps()
                                } label: {
                                    Label("Открыть в Картах", systemImage: "map")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(DotPrimaryButtonStyle(dark: preferDark, prominent: true))
                            }
                            .padding()
                            .background(preferDark ? DotTheme.deep.opacity(0.96) : Color.white)
                        }
                    } else {
                        ContentUnavailableFallback(
                            denied: tracker.authorizationDenied,
                            isCapturing: tracker.isCapturing,
                            message: tracker.statusMessage,
                            dark: preferDark,
                            onRetry: {
                                tracker.requestPermissionIfNeeded()
                                tracker.captureLastSeen(host: api.host.isEmpty ? nil : api.host)
                            },
                            onOpenSettings: {
                                tracker.openAppSettings()
                            }
                        )
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
                } else if api.canBrowseGallery, !tracker.isCapturing {
                    // Device is online but no pin yet — capture immediately.
                    tracker.captureLastSeen(host: api.host.isEmpty ? nil : api.host)
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
    var isCapturing: Bool = false
    let message: String?
    var dark: Bool = true
    var onRetry: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            if isCapturing {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(DotTheme.ice)
            } else {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(DotTheme.ice.opacity(0.7))
            }
            Text(isCapturing ? "Определяем место…" : "Пока нет сохранённой точки")
                .font(.title3.bold())
                .foregroundStyle(DotTheme.primaryText(dark: dark))
            Text(
                denied
                    ? "Разрешите геолокацию в Настройках → Dot, затем нажмите кнопку ниже."
                    : "Подключитесь к Dot (Режим модема) — приложение запомнит место iPhone. Можно запросить точку вручную."
            )
            .font(.subheadline)
            .foregroundStyle(DotTheme.secondaryText(dark: dark))
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            if denied {
                Button("Открыть Настройки", action: onOpenSettings)
                    .buttonStyle(DotPrimaryButtonStyle(dark: dark, prominent: true))
                    .padding(.horizontal, 24)
            }
            Button(isCapturing ? "Ждём GPS…" : "Запросить геолокацию", action: onRetry)
                .buttonStyle(DotPrimaryButtonStyle(dark: dark, prominent: !denied))
                .disabled(isCapturing)
                .padding(.horizontal, 24)
        }
        .padding()
    }
}

#Preview {
    LastSeenLocationView(tracker: DotLocationTracker())
        .environmentObject(PiAPIClient())
}
