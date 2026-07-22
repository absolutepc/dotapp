import SwiftUI

/// Dot visual identity: deep space-blue dark theme + plain white light theme.
enum DotTheme {
    // Dark space-blue (deeper / darker navy)
    static let void = Color(red: 0.015, green: 0.02, blue: 0.06) // ~#04060F
    static let deep = Color(red: 0.03, green: 0.05, blue: 0.12) // ~#080D1F
    static let navy = Color(red: 0.045, green: 0.08, blue: 0.18) // ~#0B142E
    static let cobalt = Color(red: 0.07, green: 0.14, blue: 0.32) // ~#122452
    static let horizon = Color(red: 0.14, green: 0.28, blue: 0.52) // ~#244785
    static let ice = Color(red: 0.48, green: 0.70, blue: 0.95) // slightly muted ice
    static let mist = Color(red: 0.72, green: 0.82, blue: 0.94)

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
                navy,
                Color(red: 0.035, green: 0.06, blue: 0.14),
            ]
        }
        // Plain white light theme — no blue wash.
        return [paper, paper, paperSoft]
    }

    static func panel(dark: Bool) -> Color {
        // Soft navy fill — no system gray “card chrome”.
        dark
            ? Color(red: 0.055, green: 0.085, blue: 0.155)
            : Color(red: 0.94, green: 0.94, blue: 0.96)
    }

    static func panelStroke(dark: Bool) -> Color {
        // No harsh frames; sections are defined by fill only.
        .clear
    }

    static func primaryText(dark: Bool) -> Color {
        dark ? .white : ink
    }

    static func secondaryText(dark: Bool) -> Color {
        dark ? mist.opacity(0.65) : inkSecondary
    }

    static func toolbarTint(dark: Bool) -> Color {
        dark ? ice : Color(red: 0.12, green: 0.28, blue: 0.55)
    }

    static func listRow(dark: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(panel(dark: dark))
    }
}

/// Dark: deep space-blue gradient. Light: plain white (no blue tint).
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
                // Soft nebula only in dark theme.
                Circle()
                    .fill(DotTheme.cobalt.opacity(0.28))
                    .frame(width: 280, height: 280)
                    .blur(radius: 55)
                    .offset(x: glowPulse ? 90 : 70, y: glowPulse ? -210 : -190)
                    .allowsHitTesting(false)

                Circle()
                    .fill(DotTheme.ice.opacity(0.07))
                    .frame(width: 220, height: 220)
                    .blur(radius: 50)
                    .offset(x: glowPulse ? -100 : -80, y: glowPulse ? 260 : 240)
                    .allowsHitTesting(false)

                Circle()
                    .fill(DotTheme.horizon.opacity(0.12))
                    .frame(width: 160, height: 160)
                    .blur(radius: 40)
                    .offset(x: 40, y: glowPulse ? 40 : 20)
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
                                        colors: [DotTheme.ice, DotTheme.horizon],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(Color(red: 0.12, green: 0.28, blue: 0.55))
                        )
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DotTheme.panel(dark: dark))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(DotTheme.panelStroke(dark: dark), lineWidth: 1)
                        }
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

    /// Soft Form/List rows like the connection screen (fill only, no gray frames).
    func dotListChrome(dark: Bool) -> some View {
        self
            .scrollContentBackground(.hidden)
            .listRowBackground(DotTheme.panel(dark: dark))
            .listRowSeparatorTint(DotTheme.ice.opacity(dark ? 0.12 : 0.08))
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
