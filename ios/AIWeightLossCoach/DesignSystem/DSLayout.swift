//
//  DSLayout.swift
//  AI Weight Loss Coach — Design System
//
//  Spacing, corner radii, elevation and motion. A 4pt base grid keeps
//  every screen optically aligned without anyone measuring anything.
//

import SwiftUI

extension DS {

    // MARK: - Spacing (4pt grid)

    enum Space {
        /// 2 — hairline gaps between tightly related glyphs.
        static let xxs: CGFloat = 2
        /// 4 — icon to its label.
        static let xs: CGFloat = 4
        /// 8 — within a component.
        static let sm: CGFloat = 8
        /// 12 — between rows in a list.
        static let md: CGFloat = 12
        /// 16 — default card padding and screen gutter.
        static let lg: CGFloat = 16
        /// 24 — between cards.
        static let xl: CGFloat = 24
        /// 32 — between sections.
        static let xxl: CGFloat = 32
        /// 48 — above a screen's primary action.
        static let xxxl: CGFloat = 48

        /// Horizontal screen margin. Everything full-width uses this.
        static let gutter: CGFloat = 16
    }

    // MARK: - Corner radius

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        /// Default card radius.
        static let lg: CGFloat = 20
        /// Hero cards and sheets.
        static let xl: CGFloat = 28
        static let pill: CGFloat = 999
    }

    // MARK: - Elevation
    //
    // Shadows are intentionally soft and low-contrast. Two levels only —
    // more than that and the hierarchy stops meaning anything.

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        /// Resting cards.
        static let low = Shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        /// Sheets, popovers, anything lifted by interaction.
        static let high = Shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
    }

    // MARK: - Motion
    //
    // Springs, not eases. Everything interactive should feel like it has
    // physical weight.

    enum Motion {
        /// Default for state changes, card appearance, layout shifts.
        static let standard = Animation.spring(response: 0.42, dampingFraction: 0.82)
        /// Buttons and taps — fast enough to feel instant.
        static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.75)
        /// Rings filling, numbers counting, celebratory moments.
        static let flourish = Animation.spring(response: 0.85, dampingFraction: 0.7)
        /// Non-interactive fades.
        static let gentle = Animation.easeInOut(duration: 0.25)

        /// Staggered delay for lists that animate in.
        static func stagger(_ index: Int, step: Double = 0.06) -> Animation {
            standard.delay(Double(index) * step)
        }
    }

    // MARK: - Sizes

    enum Size {
        static let iconSm: CGFloat = 16
        static let iconMd: CGFloat = 22
        static let iconLg: CGFloat = 28

        static let buttonHeight: CGFloat = 52
        static let fieldHeight: CGFloat = 50
        static let chipHeight: CGFloat = 34

        /// Minimum tap target. Never ship anything smaller.
        static let minTapTarget: CGFloat = 44
    }
}

// MARK: - Shadow modifier

extension View {
    func dsShadow(_ shadow: DS.Shadow = .low) -> some View {
        self.shadow(
            color: shadow.color,
            radius: shadow.radius,
            x: shadow.x,
            y: shadow.y
        )
    }

    /// Standard horizontal screen padding.
    func dsGutter() -> some View {
        self.padding(.horizontal, DS.Space.gutter)
    }

    /// Guarantees a 44pt tap target without changing visual size.
    func dsTapTarget() -> some View {
        self
            .frame(minWidth: DS.Size.minTapTarget, minHeight: DS.Size.minTapTarget)
            .contentShape(Rectangle())
    }
}

// MARK: - Reduce Motion

extension View {
    /// Applies an animation unless the user has asked for reduced motion,
    /// in which case the change is instant.
    func dsAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(DSAnimationModifier(animation: animation, value: value))
    }
}

private struct DSAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
