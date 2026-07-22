import SwiftUI

/// Space-blue visual identity for Dot (deep navy gradients + ice accent).
enum DotTheme {
    // Core palette
    static let void = Color(red: 0.03, green: 0.05, blue: 0.12) // #080D1F
    static let deep = Color(red: 0.05, green: 0.10, blue: 0.22) // #0D1A38
    static let navy = Color(red: 0.08, green: 0.16, blue: 0.34) // #142956
    static let cobalt = Color(red: 0.12, green: 0.28, blue: 0.55) // #1F478C
    static let horizon = Color(red: 0.22, green: 0.42, blue: 0.72) // #386BB8
    static let ice = Color(red: 0.55, green: 0.78, blue: 1.0) // #8CC7FF
    static let mist = Color(red: 0.78, green: 0.88, blue: 1.0) // #C7E0FF
    static let ink = Color(red: 0.06, green: 0.10, blue: 0.20)

    static var accent: Color { ice }

    static func backgroundColors(dark: Bool) -> [Color] {
        if dark {
            return [void, deep, navy, Color(red: 0.06, green: 0.12, blue: 0.28)]
        }
        return [
            Color(red: 0.82, green: 0.90, blue: 0.98),
            Color(red: 0.70, green: 0.82, blue: 0.95),
            Color(red: 0.55, green: 0.70, blue: 0.90),
            Color(red: 0.42, green: 0.58, blue: 0.82),
        ]
    }

    static func panel(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.08) : Color.white.opacity(0.45)
    }

    static func panelStroke(dark: Bool) -> Color {
        dark ? ice.opacity(0.22) : cobalt.opacity(0.25)
    }

    static func primaryText(dark: Bool) -> Color {
        dark ? .white : ink
    }

    static func secondaryText(dark: Bool) -> Color {
        dark ? mist.opacity(0.72) : navy.opacity(0.72)
    }

    static func toolbarTint(dark: Bool) -> Color {
        dark ? ice : cobalt
    }
}

/// Full-bleed space-blue gradient with soft nebula highlights.
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

            // Soft nebula orbs — intentional motion for presence.
            Circle()
                .fill(DotTheme.cobalt.opacity(dark ? 0.35 : 0.28))
                .frame(width: 280, height: 280)
                .blur(radius: 50)
                .offset(x: glowPulse ? 90 : 70, y: glowPulse ? -210 : -190)
                .allowsHitTesting(false)

            Circle()
                .fill(DotTheme.ice.opacity(dark ? 0.12 : 0.22))
                .frame(width: 220, height: 220)
                .blur(radius: 45)
                .offset(x: glowPulse ? -100 : -80, y: glowPulse ? 260 : 240)
                .allowsHitTesting(false)

            Circle()
                .fill(DotTheme.horizon.opacity(dark ? 0.18 : 0.2))
                .frame(width: 160, height: 160)
                .blur(radius: 36)
                .offset(x: 40, y: glowPulse ? 40 : 20)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .onAppear {
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
            .foregroundStyle(prominent ? DotTheme.void : DotTheme.primaryText(dark: dark))
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [DotTheme.ice, DotTheme.horizon],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
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
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(DotTheme.panelStroke(dark: dark), lineWidth: 1)
            }
    }
}

extension View {
    func dotPanel(dark: Bool) -> some View {
        modifier(DotPanelModifier(dark: dark))
    }

    func dotNavigationChrome(dark: Bool) -> some View {
        self
            .toolbarBackground(dark ? DotTheme.deep.opacity(0.92) : DotTheme.mist.opacity(0.88), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(dark ? .dark : .light, for: .navigationBar)
            .tint(DotTheme.toolbarTint(dark: dark))
    }
}
