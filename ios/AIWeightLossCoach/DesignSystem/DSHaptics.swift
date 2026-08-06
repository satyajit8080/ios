//
//  DSHaptics.swift
//  AI Weight Loss Coach — Design System
//
//  Every haptic in the app goes through here, so a single settings toggle
//  can silence them all and the vocabulary stays consistent: a tap always
//  feels like a tap, a milestone always feels like a milestone.
//

import SwiftUI
import UIKit

extension DS {

    @MainActor
    enum Haptics {

        /// Mirrored from the user's settings. Set this once at launch and
        /// whenever the toggle changes.
        static var isEnabled = true

        // MARK: Vocabulary

        /// A button was pressed. The most common haptic in the app.
        static func tap() {
            impact(.light)
        }

        /// A value changed in a picker, segmented control or stepper.
        static func selection() {
            guard isEnabled else { return }
            UISelectionFeedbackGenerator().selectionChanged()
        }

        /// Something was logged, saved or completed.
        static func success() {
            notify(.success)
        }

        /// The action worked but something needs attention.
        static func warning() {
            notify(.warning)
        }

        /// The action failed.
        static func error() {
            notify(.error)
        }

        /// A ring closed, a streak extended, a badge unlocked.
        /// Deliberately heavier and doubled — it should feel like an event.
        static func milestone() {
            guard isEnabled else { return }
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }

        // MARK: Primitives

        static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
            guard isEnabled else { return }
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }

        static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
            guard isEnabled else { return }
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(type)
        }

        /// Call before a haptic you know is coming (e.g. as a drag starts)
        /// to remove the Taptic Engine's warm-up latency.
        static func prepare() {
            guard isEnabled else { return }
            UIImpactFeedbackGenerator(style: .light).prepare()
        }
    }
}

// MARK: - Declarative trigger

extension View {
    /// Fires a haptic whenever `value` changes.
    ///
    ///     .dsHaptic(.success, on: didLogMeal)
    func dsHaptic<V: Equatable>(_ kind: DSHapticKind, on value: V) -> some View {
        onChange(of: value) { _, _ in
            kind.fire()
        }
    }
}

enum DSHapticKind {
    case tap, selection, success, warning, error, milestone

    @MainActor
    func fire() {
        switch self {
        case .tap: DS.Haptics.tap()
        case .selection: DS.Haptics.selection()
        case .success: DS.Haptics.success()
        case .warning: DS.Haptics.warning()
        case .error: DS.Haptics.error()
        case .milestone: DS.Haptics.milestone()
        }
    }
}
