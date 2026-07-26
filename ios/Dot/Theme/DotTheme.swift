import SwiftUI

/// Dot visual identity: space-black dark theme + plain white light theme.
enum DotTheme {
    // Dark space-black (near-OLED blacks + graphite depth)
    static let void = Color(red: 0.02, green: 0.02, blue: 0.025) // ~#050506
    static let deep = Color(red: 0.04, green: 0.04, blue: 0.045) // ~#0A0A0B
    static let navy = Color(red: 0.07, green: 0.07, blue: 0.08) // ~#121214 graphite
    static let cobalt = Color(red: 0.12, green: 0.12, blue: 0.14) // ~#1F1F24 soft lift
    static let horizon = Color(red: 0.22, green: 0.23, blue: 0.26) // ~#383A42 cool metal
    static let ice = Color(red: 0.78, green: 0.80, blue: 0.84) // silver accent
    static let mist = Color(red: 0.72, green: 0.73, blue: 0.76)

    // Light theme neutrals
    static let paper = Color.white
    static let paperSoft = Color(red: 0.96, green: 0.96, blue: 0.97) // #F5F5F7
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.10)
    static let inkSecondary = Color(red: 0.35, green: 0.36, blue: 0.40)
    static let hairline = Color.black.opacity(0.08)

    static var accent: Color { ice }

    static func backgroundColors(dark: Bool) -> [Color] {
        if dark {
            return [
                void,
                deep,
                Color(red: 0.05, green: 0.05, blue: 0.055),
                navy,
            ]
        }
        // Plain white light theme — no wash.
        return [paper, paper, paperSoft]
    }

    static func panel(dark: Bool) -> Color {
        // Raised graphite panel on black — no system gray chrome.
        dark
            ? Color(red: 0.10, green: 0.10, blue: 0.11)
            : Color(red: 0.94, green: 0.94, blue: 0.96)
    }

    static func panelStroke(dark: Bool) -> Color {
        .clear
    }

    static func primaryText(dark: Bool) -> Color {
        dark ? Color(red: 0.96, green: 0.96, blue: 0.97) : ink
    }

    static func secondaryText(dark: Bool) -> Color {
        dark ? mist.opacity(0.72) : inkSecondary
    }

    /// Light theme uses ink (black), not system blue.
    static func toolbarTint(dark: Bool) -> Color {
        dark ? ice : ink
    }

    /// Pending setup step circle (number). Completed steps use `success`.
    static func stepPending(dark: Bool) -> Color {
        dark ? ice : ink
    }

    static let success = Color(red: 0.20, green: 0.72, blue: 0.38)

    static func listRow(dark: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(panel(dark: dark))
    }
}

/// Dark: space-black gradient. Light: plain white.
struct SpaceBlueBackground: View {
    var dark: Bool = true
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: DotTheme.backgroundColors(dark: dark),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if dark {
                // Quiet depth — soft graphite, not blue nebula.
                Circle()
                    .fill(DotTheme.cobalt.opacity(0.45))
                    .frame(width: 300, height: 300)
                    .blur(radius: 70)
                    .offset(x: glowPulse ? 80 : 60, y: glowPulse ? -220 : -200)
                    .allowsHitTesting(false)

                Circle()
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 240, height: 240)
                    .blur(radius: 55)
                    .offset(x: glowPulse ? -90 : -70, y: glowPulse ? 250 : 230)
                    .allowsHitTesting(false)

                Circle()
                    .fill(DotTheme.horizon.opacity(0.18))
                    .frame(width: 160, height: 160)
                    .blur(radius: 45)
                    .offset(x: 30, y: glowPulse ? 50 : 30)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard dark else { return }
            withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
    }
}

struct DotPrimaryButtonStyle: ButtonStyle {
    var dark: Bool = true
    var prominent: Bool = true
    var expand: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: expand ? .infinity : nil)
            .padding(.horizontal, expand ? 0 : 16)
            .padding(.vertical, 14)
            .foregroundStyle(prominent ? (dark ? DotTheme.void : .white) : DotTheme.primaryText(dark: dark))
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            dark
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.88, green: 0.89, blue: 0.92),
                                            DotTheme.horizon,
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(DotTheme.ink)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DotTheme.panel(dark: dark))
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct DotPanelModifier: ViewModifier {
    var dark: Bool

    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DotTheme.panel(dark: dark), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func dotPanel(dark: Bool) -> some View {
        modifier(DotPanelModifier(dark: dark))
    }

    /// Soft Form/List rows (fill only, no gray frames).
    func dotListChrome(dark: Bool) -> some View {
        self
            .scrollContentBackground(.hidden)
            .listRowBackground(DotTheme.panel(dark: dark))
            .listRowSeparatorTint(DotTheme.ice.opacity(dark ? 0.14 : 0.08))
    }

    func dotNavigationChrome(dark: Bool) -> some View {
        self
            .toolbarBackground(
                dark ? DotTheme.deep.opacity(0.96) : Color.white.opacity(0.96),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(dark ? .dark : .light, for: .navigationBar)
            .tint(DotTheme.toolbarTint(dark: dark))
    }
}
