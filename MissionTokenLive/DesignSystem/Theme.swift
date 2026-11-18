import SwiftUI

/// Tokens du design system — repris à l'identique de la maquette FigCraft
/// (`token-town.figcraft`, page « 00 · Design system »).
enum Theme {
    // Surfaces
    static let bg = Color(hex: 0x0A0C0F)
    static let surface = Color(hex: 0x11151A)
    static let raised = Color(hex: 0x171C23)
    static let field = Color(hex: 0x1F252E)
    static let border = Color(hex: 0x262E38)
    static let borderSoft = Color(hex: 0x1B2129)
    static let sidebar = Color(hex: 0x0D1014)

    // Texte
    static let textPrimary = Color(hex: 0xF2F5F9)
    static let textSecondary = Color(hex: 0xA7B2C0)
    static let textTertiary = Color(hex: 0x6B7686)

    // Signal
    static let accent = Color(hex: 0x4C8DFF)
    static let accentDeep = Color(hex: 0x2B5FD9)
    static let ok = Color(hex: 0x34C88A)
    static let warn = Color(hex: 0xF0A23C)
    static let error = Color(hex: 0xEF5A4E)
    static let violet = Color(hex: 0x8E7CF0)
    static let cyan = Color(hex: 0x39C0E8)

    // Géométrie
    static let radiusBadge: CGFloat = 6
    static let radiusField: CGFloat = 10
    static let radiusCard: CGFloat = 14
    static let radiusFeature: CGFloat = 18
    static let sidebarWidth: CGFloat = 232

    // Typographie
    static func display(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .semibold) }
    static func title(_ size: CGFloat = 26) -> Font { .system(size: size, weight: .semibold) }
    static func section(_ size: CGFloat = 17) -> Font { .system(size: size, weight: .semibold) }
    static func body(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static func caption(_ size: CGFloat = 11.5) -> Font { .system(size: size) }
    static func micro() -> Font { .system(size: 10.5, weight: .medium) }

    // Dégradé d'accent utilisé par les graphes
    static let accentGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .top, endPoint: .bottom
    )
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
