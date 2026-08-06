//
//  DSColors.swift
//  AI Weight Loss Coach — Design System
//
//  Single source of truth for colour. Never write a literal colour in a
//  view; if a shade is missing, add it here.
//
//  Every token is dynamic: it resolves differently in light and dark mode,
//  so dark mode is free for any view built from these tokens.
//

import SwiftUI
import UIKit

/// Root namespace for the design system.
enum DS {}

// MARK: - Hex helper

extension Color {
    /// `Color(hex: 0x1B4332)`
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

private func dynamic(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
        let hex = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    })
}

// MARK: - Palette

extension DS {

    enum Colors {

        // MARK: Brand

        /// Primary brand green. Used for the main CTA and the weight ring.
        static let brand = dynamic(light: 0x1B7A5A, dark: 0x2FD09A)
        static let brandDeep = dynamic(light: 0x0F4C3A, dark: 0x1B7A5A)
        static let brandSoft = dynamic(light: 0xE3F5EE, dark: 0x123328)

        /// Secondary accent, used for AI/intelligence surfaces.
        static let ai = dynamic(light: 0x6C4DF6, dark: 0x9B85FF)
        static let aiSoft = dynamic(light: 0xEFEBFF, dark: 0x1E1A38)

        // MARK: Backgrounds

        /// The furthest-back surface. Screens sit on this.
        static let background = dynamic(light: 0xF6F7F9, dark: 0x0A0B0D)
        /// Cards and sheets.
        static let surface = dynamic(light: 0xFFFFFF, dark: 0x15171A)
        /// A card sitting on top of another card.
        static let surfaceRaised = dynamic(light: 0xFFFFFF, dark: 0x1E2126)
        /// Inset wells — chart backgrounds, input fields.
        static let surfaceSunken = dynamic(light: 0xEFF1F4, dark: 0x101215)

        // MARK: Text

        static let textPrimary = dynamic(light: 0x0B0D0F, dark: 0xF7F8FA)
        static let textSecondary = dynamic(light: 0x5C6470, dark: 0xA0A8B4)
        static let textTertiary = dynamic(light: 0x8B94A1, dark: 0x6B7381)
        /// Text placed on top of a brand-coloured fill.
        static let textOnBrand = Color.white

        // MARK: Structure

        static let separator = dynamic(light: 0xE4E7EC, dark: 0x262A31)
        static let border = dynamic(light: 0xD8DCE3, dark: 0x2F343C)

        // MARK: Status

        static let success = dynamic(light: 0x11895E, dark: 0x35D69C)
        static let warning = dynamic(light: 0xC77A0A, dark: 0xFFB443)
        static let danger = dynamic(light: 0xD03A48, dark: 0xFF6B7A)
        static let info = dynamic(light: 0x1F6FEB, dark: 0x5AA9FF)

        // MARK: Metric accents
        //
        // Deliberately spaced around the wheel so five rings stay legible
        // at a glance, and colour-blind users can still tell them apart by
        // radius and icon.

        static let calories = dynamic(light: 0xE8590C, dark: 0xFF8A47)
        static let protein = dynamic(light: 0x7C3AED, dark: 0xA78BFA)
        static let water = dynamic(light: 0x0891B2, dark: 0x38D3F0)
        static let steps = dynamic(light: 0x15803D, dark: 0x4ADE80)
        static let weight = dynamic(light: 0x1B7A5A, dark: 0x2FD09A)
        static let sleep = dynamic(light: 0x4F46E5, dark: 0x818CF8)

        // MARK: Gradients

        static var brandGradient: LinearGradient {
            LinearGradient(
                colors: [brand, brandDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        static var aiGradient: LinearGradient {
            LinearGradient(
                colors: [ai, brand],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// Subtle page-level wash behind the whole app.
        static var backgroundGradient: LinearGradient {
            LinearGradient(
                colors: [background, surfaceSunken],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        /// Ring gradients read better as angular sweeps.
        static func ringGradient(_ color: Color) -> AngularGradient {
            AngularGradient(
                colors: [color.opacity(0.65), color, color.opacity(0.65)],
                center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(360)
            )
        }

        // MARK: Semantic helpers

        /// Colour for a 0–100 health score.
        static func score(_ value: Int) -> Color {
            switch value {
            case ..<40: return danger
            case 40..<65: return warning
            case 65..<85: return brand
            default: return success
            }
        }

        /// Green when moving toward goal, red when away, grey when flat.
        /// `lowerIsBetter` is true for weight and body fat.
        static func trend(_ delta: Double, lowerIsBetter: Bool = false) -> Color {
            if abs(delta) < 0.0001 { return textTertiary }
            let improving = lowerIsBetter ? delta < 0 : delta > 0
            return improving ? success : danger
        }
    }
}

// MARK: - Metric identity
//
// One definition per tracked metric, so a ring, a card and a chart all
// agree on colour, icon and label without anyone passing them around.

enum DSMetric: String, CaseIterable, Identifiable {
    case calories, protein, water, steps, weight, sleep

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .calories: return DS.Colors.calories
        case .protein: return DS.Colors.protein
        case .water: return DS.Colors.water
        case .steps: return DS.Colors.steps
        case .weight: return DS.Colors.weight
        case .sleep: return DS.Colors.sleep
        }
    }

    var icon: String {
        switch self {
        case .calories: return "flame.fill"
        case .protein: return "fork.knife"
        case .water: return "drop.fill"
        case .steps: return "figure.walk"
        case .weight: return "scalemass.fill"
        case .sleep: return "moon.stars.fill"
        }
    }

    var label: String {
        switch self {
        case .calories: return "Calories"
        case .protein: return "Protein"
        case .water: return "Water"
        case .steps: return "Steps"
        case .weight: return "Weight"
        case .sleep: return "Sleep"
        }
    }

    /// Unit suffix shown next to the value. Kept short — cards are narrow.
    var unit: String {
        switch self {
        case .calories: return "kcal"
        case .protein: return "g"
        case .water: return "ml"
        case .steps: return ""
        case .weight: return "kg"
        case .sleep: return "h"
        }
    }
}
