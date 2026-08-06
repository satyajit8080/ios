//
//  DSCards.swift
//  AI Weight Loss Coach — Design System
//
//  Every rectangle in the app is one of these. Nothing should build its
//  own background + corner radius + shadow stack.
//

import SwiftUI

// MARK: - Base card

struct DSCard<Content: View>: View {
    var padding: CGFloat = DS.Space.lg
    var radius: CGFloat = DS.Radius.lg
    var shadow: DS.Shadow = .low
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(DS.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.Colors.separator, lineWidth: 0.5)
            )
            .dsShadow(shadow)
    }
}

// MARK: - Glass panel
//
// FUNCTIONAL LAYER ONLY. Transient overlays that float above content:
// a camera control strip, a HUD, a floating toolbar.
//
// NOT for content. Login forms, dashboard cards, meal cards, chat
// bubbles, analytics and paywall content all use `DSCard`. See the
// header of DSGlass.swift for why this is a rule.

struct DSGlassPanel<Content: View>: View {
    var padding: CGFloat = DS.Space.lg
    var radius: CGFloat = DS.Radius.lg
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .dsShadow(.high)
    }
}

@available(*, deprecated, renamed: "DSGlassPanel", message: "Renamed to make the functional-layer restriction explicit. Content cards must use DSCard.")
typealias DSGlassCard = DSGlassPanel

// MARK: - Section header

struct DSSectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .dsText(DS.Typography.title3)
                if let subtitle {
                    Text(subtitle)
                        .dsText(DS.Typography.footnote, color: DS.Colors.textSecondary)
                }
            }

            Spacer(minLength: DS.Space.sm)

            if let actionTitle, let action {
                Button(actionTitle) {
                    DS.Haptics.tap()
                    action()
                }
                .font(DS.Typography.subheadline.weight(.semibold))
                .foregroundStyle(DS.Colors.brand)
                .dsTapTarget()
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Metric card

struct DSMetricCard: View {
    let metric: DSMetric
    let value: Double
    var goal: Double?
    /// Change vs the comparison period. Nil hides the badge.
    var delta: Double?
    var decimals: Int = 0
    /// True for weight and body fat, where down is good.
    var lowerIsBetter: Bool = false
    /// Optional inline trend line.
    var sparkline: [Double] = []

    private var progress: Double? {
        guard let goal, goal > 0 else { return nil }
        return value / goal
    }

    var body: some View {
        DSCard(padding: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: metric.icon)
                        .font(.system(size: DS.Size.iconSm, weight: .bold))
                        .foregroundStyle(metric.color)
                        .frame(width: 28, height: 28)
                        .background(metric.color.opacity(0.12), in: Circle())

                    Text(metric.label)
                        .dsText(DS.Typography.subheadline, color: DS.Colors.textSecondary)

                    Spacer(minLength: 0)

                    if let delta {
                        DSDeltaBadge(
                            delta: delta,
                            decimals: decimals,
                            lowerIsBetter: lowerIsBetter
                        )
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                    Text(DSFormat.value(value, decimals: decimals))
                        .dsText(DS.Typography.metricLarge)
                    if !metric.unit.isEmpty {
                        Text(metric.unit)
                            .dsText(DS.Typography.footnote, color: DS.Colors.textTertiary)
                    }
                    if let goal {
                        Text("of \(DSFormat.value(goal, decimals: decimals))")
                            .dsText(DS.Typography.footnote, color: DS.Colors.textTertiary)
                            .padding(.leading, DS.Space.xs)
                    }
                }

                if !sparkline.isEmpty {
                    DSSparkline(values: sparkline, color: metric.color)
                        .frame(height: 34)
                } else if let progress {
                    DSProgressBar(progress: progress, color: metric.color)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Delta badge

struct DSDeltaBadge: View {
    let delta: Double
    var decimals: Int = 1
    var lowerIsBetter: Bool = false
    var unit: String = ""

    private var color: Color { DS.Colors.trend(delta, lowerIsBetter: lowerIsBetter) }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))
            Text(DSFormat.delta(delta, decimals: decimals, unit: unit))
                .font(DS.Typography.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .background(color.opacity(0.12), in: Capsule())
        .accessibilityLabel(
            delta >= 0
                ? "Up \(DSFormat.value(abs(delta), decimals: decimals)) \(unit)"
                : "Down \(DSFormat.value(abs(delta), decimals: decimals)) \(unit)"
        )
    }
}

// MARK: - AI coach card
//
// The most important surface in the app. It gets the only gradient fill
// at this level of the hierarchy, so it always reads as "the AI is
// speaking" rather than as one more statistic.

struct DSCoachCard: View {
    let message: String
    var headline: String = "Your coach"
    /// Optional 0–100 score shown as a compact badge.
    var score: Int?
    var actionTitle: String?
    var action: (() -> Void)?
    /// Shows the shimmering "thinking" state instead of the message.
    var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: DS.Size.iconSm, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.22), in: Circle())

                Text(headline)
                    .font(DS.Typography.headline)
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                if let score {
                    HStack(spacing: DS.Space.xs) {
                        Text("\(score)")
                            .font(DS.Typography.metricSmall)
                        Text("/100")
                            .font(DS.Typography.caption)
                            .opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.xs)
                    .background(Color.white.opacity(0.18), in: Capsule())
                }
            }

            if isLoading {
                DSShimmerLines(count: 3)
                    .frame(height: 54)
            } else {
                Text(message)
                    .font(DS.Typography.body)
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let actionTitle, let action, !isLoading {
                Button {
                    DS.Haptics.tap()
                    action()
                } label: {
                    HStack(spacing: DS.Space.xs) {
                        Text(actionTitle)
                            .font(DS.Typography.button)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(DS.Colors.brandDeep)
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.vertical, DS.Space.md)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(DSPressStyle())
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(DS.Colors.aiGradient)
        )
        .overlay(
            // Soft highlight so the gradient does not read as flat.
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .dsShadow(.high)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stat tile
//
// Smaller than a metric card. For grids of three or four supporting
// numbers under a hero.

struct DSStatTile: View {
    let label: String
    let value: String
    var icon: String?
    var tint: Color = DS.Colors.brand

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: DS.Size.iconSm, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(value)
                .dsText(DS.Typography.metricMedium)
            Text(label)
                .dsText(DS.Typography.caption, color: DS.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Colors.surfaceSunken)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview("Cards") {
    ScrollView {
        VStack(spacing: DS.Space.lg) {
            DSCoachCard(
                message: "Based on your last 7 days you're on track to lose 0.4 kg this week. Adding 18 g of protein a day would protect muscle while the deficit does its work.",
                score: 78,
                actionTitle: "See the plan",
                action: {}
            )

            DSMetricCard(
                metric: .calories,
                value: 1840,
                goal: 2100,
                delta: -120,
                lowerIsBetter: true
            )

            DSMetricCard(
                metric: .weight,
                value: 82.4,
                delta: -0.6,
                decimals: 1,
                lowerIsBetter: true,
                sparkline: [84.1, 83.8, 83.9, 83.4, 83.0, 82.7, 82.4]
            )

            HStack(spacing: DS.Space.md) {
                DSStatTile(label: "BMI", value: "24.1", icon: "figure", tint: DS.Colors.brand)
                DSStatTile(label: "Body fat", value: "19%", icon: "percent", tint: DS.Colors.protein)
                DSStatTile(label: "Streak", value: "12d", icon: "flame.fill", tint: DS.Colors.calories)
            }
        }
        .padding(DS.Space.lg)
    }
    .background(DS.Colors.background)
}
