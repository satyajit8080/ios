import SwiftUI
import UIKit

/// Palette tuned for both appearances.
///
/// The light-mode pine and plum are too dark to read against a dark background, so
/// every brand colour resolves through `UIColor` with a lighter dark-mode variant.
/// Structural colours use system semantics, which adapt on their own.
enum Palette {
    static let pine = adaptive(
        light: (0.11, 0.42, 0.35),
        dark: (0.29, 0.73, 0.57)
    )
    static let pineDeep = adaptive(
        light: (0.06, 0.25, 0.21),
        dark: (0.16, 0.44, 0.36)
    )
    static let amber = adaptive(
        light: (0.93, 0.68, 0.24),
        dark: (0.98, 0.78, 0.40)
    )
    static let water = adaptive(
        light: (0.27, 0.58, 0.83),
        dark: (0.42, 0.71, 0.94)
    )
    static let coral = adaptive(
        light: (0.90, 0.42, 0.35),
        dark: (0.98, 0.55, 0.48)
    )
    static let plum = adaptive(
        light: (0.52, 0.31, 0.55),
        dark: (0.71, 0.52, 0.76)
    )
    static let ink = adaptive(
        light: (0.07, 0.11, 0.10),
        dark: (0.92, 0.94, 0.93)
    )

    static let protein = adaptive(
        light: (0.85, 0.36, 0.42),
        dark: (0.95, 0.52, 0.57)
    )
    static let carbs = adaptive(
        light: (0.35, 0.60, 0.82),
        dark: (0.50, 0.73, 0.94)
    )
    static let fat = adaptive(
        light: (0.93, 0.68, 0.24),
        dark: (0.98, 0.78, 0.40)
    )

    static func macro(_ name: String) -> Color {
        switch name.lowercased() {
        case "protein": protein
        case "carbs": carbs
        default: fat
        }
    }

    private static func adaptive(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(
            UIColor { traits in
                let components = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: components.0,
                    green: components.1,
                    blue: components.2,
                    alpha: 1
                )
            }
        )
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Hex colour that stays legible in both appearances.
    /// Habit colours are stored as hex strings server-side, so they can't be
    /// pre-tuned per mode the way the fixed palette is.
    init(adaptiveHex hex: String) {
        self = Color(hex: hex).legibleOnAnyBackground()
    }

    /// Lightens a stored hex colour enough to stay legible on a dark background.
    /// Habit colours are user-chosen hex strings, so they can't be pre-tuned per mode.
    func legibleOnAnyBackground() -> Color {
        Color(
            UIColor { traits in
                let base = UIColor(self)
                guard traits.userInterfaceStyle == .dark else { return base }

                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                guard base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
                    return base
                }
                return UIColor(
                    hue: hue,
                    saturation: max(saturation * 0.85, 0.25),
                    brightness: min(max(brightness, 0.62), 1.0),
                    alpha: alpha
                )
            }
        )
    }
}

extension View {
    func cardSurface() -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }

    func sectionTitle() -> some View {
        self
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.8)
            .foregroundStyle(.secondary)
    }
}

enum Units {
    static func kg(_ value: Double?, decimals: Int = 1) -> String {
        guard let value else { return "—" }
        return String(format: "%.\(decimals)f kg", value)
    }

    static func kcal(_ value: Double) -> String {
        "\(Int(value.rounded())) kcal"
    }

    static func grams(_ value: Double) -> String {
        "\(Int(value.rounded())) g"
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func litres(_ ml: Int) -> String {
        ml >= 1000 ? String(format: "%.1f L", Double(ml) / 1000) : "\(ml) ml"
    }
}
