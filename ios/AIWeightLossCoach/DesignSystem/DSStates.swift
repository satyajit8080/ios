//
//  DSStates.swift
//  AI Weight Loss Coach — Design System
//
//  Loading, empty and error states. Every screen that fetches anything
//  must render all three — a spinner alone is not a loading state.
//

import SwiftUI

// MARK: - Shimmer

/// Sweeping highlight used on skeleton placeholders.
struct DSShimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.35),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                        .blendMode(.overlay)
                    }
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func dsShimmer() -> some View { modifier(DSShimmer()) }
}

// MARK: - Skeletons

struct DSSkeletonBlock: View {
    var height: CGFloat = 16
    var width: CGFloat?
    var radius: CGFloat = DS.Radius.sm

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(DS.Colors.surfaceSunken)
            .frame(width: width, height: height)
            .dsShimmer()
    }
}

/// Placeholder paragraph. The last line is short, like real text.
struct DSShimmerLines: View {
    var count: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 11)
                    .frame(maxWidth: index == count - 1 ? 140 : .infinity, alignment: .leading)
                    .dsShimmer()
            }
        }
        .accessibilityLabel("Loading")
    }
}

struct DSSkeletonCard: View {
    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                HStack(spacing: DS.Space.sm) {
                    Circle()
                        .fill(DS.Colors.surfaceSunken)
                        .frame(width: 28, height: 28)
                        .dsShimmer()
                    DSSkeletonBlock(height: 12, width: 90)
                }
                DSSkeletonBlock(height: 30, width: 120)
                DSSkeletonBlock(height: 8)
            }
        }
        .accessibilityLabel("Loading")
    }
}

// MARK: - Empty state

struct DSEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            ZStack {
                Circle()
                    .fill(DS.Colors.brandSoft)
                    .frame(width: 84, height: 84)
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(DS.Colors.brand)
            }

            VStack(spacing: DS.Space.sm) {
                Text(title)
                    .dsText(DS.Typography.title3)
                    .multilineTextAlignment(.center)
                Text(message)
                    .dsText(DS.Typography.subheadline, color: DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action {
                DSPrimaryButton(title: actionTitle, fullWidth: false, action: action)
                    .padding(.top, DS.Space.xs)
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Error state

struct DSErrorState: View {
    var title: String = "Something went wrong"
    var message: String
    var retryTitle: String = "Try again"
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            ZStack {
                Circle()
                    .fill(DS.Colors.danger.opacity(0.12))
                    .frame(width: 84, height: 84)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(DS.Colors.danger)
            }

            VStack(spacing: DS.Space.sm) {
                Text(title)
                    .dsText(DS.Typography.title3)
                    .multilineTextAlignment(.center)
                Text(message)
                    .dsText(DS.Typography.subheadline, color: DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onRetry {
                DSSecondaryButton(title: retryTitle, icon: "arrow.clockwise", fullWidth: false) {
                    onRetry()
                }
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Inline banner

enum DSBannerKind {
    case info, success, warning, error

    var color: Color {
        switch self {
        case .info: return DS.Colors.info
        case .success: return DS.Colors.success
        case .warning: return DS.Colors.warning
        case .error: return DS.Colors.danger
        }
    }

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

struct DSBanner: View {
    let kind: DSBannerKind
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: kind.icon)
                .font(.system(size: DS.Size.iconSm, weight: .semibold))
                .foregroundStyle(kind.color)

            Text(message)
                .dsText(DS.Typography.footnote, color: DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let actionTitle, let action {
                DSTextButton(title: actionTitle, tint: kind.color, action: action)
            }
        }
        .padding(DS.Space.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(kind.color.opacity(0.10))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Async content wrapper
//
// Wrap any loaded data in this and the three states come for free.

enum DSLoadState<Value> {
    case loading
    case loaded(Value)
    case failed(String)
    case empty
}

struct DSAsyncContent<Value, Content: View, Placeholder: View>: View {
    let state: DSLoadState<Value>
    var emptyIcon: String = "tray"
    var emptyTitle: String = "Nothing here yet"
    var emptyMessage: String = "Once you start logging, this fills in."
    var onRetry: (() -> Void)?
    @ViewBuilder var content: (Value) -> Content
    @ViewBuilder var placeholder: () -> Placeholder

    var body: some View {
        switch state {
        case .loading:
            placeholder()
                .transition(.opacity)
        case .loaded(let value):
            content(value)
                .transition(.opacity)
        case .empty:
            DSEmptyState(icon: emptyIcon, title: emptyTitle, message: emptyMessage)
        case .failed(let message):
            DSErrorState(message: message, onRetry: onRetry)
        }
    }
}

#Preview("States") {
    ScrollView {
        VStack(spacing: DS.Space.xl) {
            DSSkeletonCard()

            DSBanner(
                kind: .warning,
                message: "Health access is off, so steps aren't syncing.",
                actionTitle: "Fix",
                action: {}
            )

            DSCard {
                DSEmptyState(
                    icon: "camera.viewfinder",
                    title: "No meals scanned",
                    message: "Point your camera at a plate and the coach will estimate the macros.",
                    actionTitle: "Scan a meal",
                    action: {}
                )
            }

            DSCard {
                DSErrorState(
                    message: "We couldn't reach the coach. Check your connection.",
                    onRetry: {}
                )
            }
        }
        .padding(DS.Space.lg)
    }
    .background(DS.Colors.background)
}
