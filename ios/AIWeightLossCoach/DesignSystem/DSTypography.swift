//
//  DSTypography.swift
//  AI Weight Loss Coach — Design System
//
//  Text styles are built on SwiftUI's semantic text styles rather than
//  fixed point sizes, so everything scales with Dynamic Type for free.
//  Hero numbers are the one exception and use @ScaledMetric instead.
//
//  Rounded (SF Rounded) is used for numerals and display text — it reads
//  as friendly and modern next to Apple Fitness. Body copy stays in the
//  default face, which is more legible at small sizes.
//

import SwiftUI

extension DS {

    enum Typography {

        // MARK: Display & titles

        static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let title1 = Font.system(.title, design: .rounded, weight: .bold)
        static let title2 = Font.system(.title2, design: .rounded, weight: .semibold)
        static let title3 = Font.system(.title3, design: .rounded, weight: .semibold)

        // MARK: Body

        static let headline = Font.system(.headline, weight: .semibold)
        static let body = Font.system(.body)
        static let bodyEmphasis = Font.system(.body, weight: .medium)
        static let callout = Font.system(.callout)
        static let subheadline = Font.system(.subheadline)
        static let footnote = Font.system(.footnote)
        static let caption = Font.system(.caption)

        // MARK: Numerals
        //
        // Monospaced digits stop values jittering as they animate or tick.

        static let metricLarge = Font.system(.largeTitle, design: .rounded, weight: .bold)
            .monospacedDigit()
        static let metricMedium = Font.system(.title2, design: .rounded, weight: .semibold)
            .monospacedDigit()
        static let metricSmall = Font.system(.headline, design: .rounded, weight: .semibold)
            .monospacedDigit()

        // MARK: Utility

        /// Small all-caps label for section eyebrows.
        static let overline = Font.system(.caption2, design: .rounded, weight: .bold)

        static let button = Font.system(.headline, design: .rounded, weight: .semibold)
    }
}

// MARK: - Text style modifiers

extension View {

    /// Applies a design-system font plus its matching colour in one call.
    func dsText(_ font: Font, color: Color = DS.Colors.textPrimary) -> some View {
        self.font(font).foregroundStyle(color)
    }

    /// Section eyebrow: uppercase, tracked out, tertiary colour.
    func dsOverline() -> some View {
        self
            .font(DS.Typography.overline)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(DS.Colors.textTertiary)
    }

    /// Hero number that still respects Dynamic Type via a scaled size.
    func dsHeroNumber() -> some View {
        modifier(DSHeroNumberModifier())
    }
}

private struct DSHeroNumberModifier: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 44

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(DS.Colors.textPrimary)
            // Hero numbers get long ("2,450") on small phones at large
            // text sizes. Shrink rather than truncate.
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

// MARK: - Number formatting
//
// Formatting lives with typography because it is a presentation concern.
// Views should never call String(format:) directly.

enum DSFormat {

    static func value(_ value: Double, decimals: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func int(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// Signed delta, e.g. "−0.4 kg" or "+120 kcal".
    /// Uses a true minus sign, not a hyphen — it aligns with digits.
    static func delta(_ value: Double, decimals: Int = 1, unit: String = "") -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "\u{2212}" : "")
        let magnitude = self.value(abs(value), decimals: decimals)
        return unit.isEmpty ? "\(sign)\(magnitude)" : "\(sign)\(magnitude) \(unit)"
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}
