import SwiftUI

/// Colour tokens from the design system. The app is dark only.
extension ShapeStyle where Self == Color {
    // Surfaces
    static var appBackground: Color { Color(hex: 0x09090B) }
    /// Onboarding uses a slightly deeper black.
    static var onboardingBackground: Color { Color(hex: 0x050506) }
    /// Cards and grouped lists.
    static var surface: Color { Color(hex: 0x141417) }
    /// Inputs, secondary buttons, icon circles.
    static var surfaceRaised: Color { Color(hex: 0x1F1F23) }
    /// Selected segment in a segmented control.
    static var segmentSelected: Color { Color(hex: 0x3A3A40) }
    /// Selected chips, days and tabs.
    static var fillSelected: Color { .white.opacity(0.13) }
    /// Hairline borders and list separators.
    static var stroke: Color { .white.opacity(0.16) }

    // Text
    static var textPrimary: Color { Color(hex: 0xF5F5F7) }
    static var textSecondary: Color { Color(hex: 0xA1A1A6) }
    static var textTertiary: Color { Color(hex: 0x6E6E73) }

    // Accents
    /// Primary buttons and the active tab.
    static var accentGold: Color { Color(hex: 0xD6AD66) }
    /// Text and icons on `accentGold`.
    static var onAccent: Color { Color(hex: 0x1A1206) }
    /// Data: logged-day dots, charts, text buttons.
    static var dataBlue: Color { Color(hex: 0x7D9CF0) }
    /// "Paid off".
    static var positive: Color { Color(hex: 0x30D158) }
    /// "Unworn 140 d".
    static var warning: Color { Color(hex: 0xFF9F0A) }
    static var destructive: Color { Color(hex: 0xFF453A) }
}

extension Color {
    /// A colour from a 0xRRGGBB literal.
    nonisolated init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// A colour from a "#RRGGBB" string, e.g. an item's stored tint.
    nonisolated init?(hexString: String) {
        let digits = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }
}
