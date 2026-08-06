//
//  DSGallery.swift
//  AI Weight Loss Coach — Design System
//
//  A living catalogue of every component. Wire this behind a hidden
//  gesture in Settings during development: it is the fastest way to spot
//  a broken component in dark mode or at accessibility text sizes.
//

import SwiftUI

struct DSGallery: View {
    @State private var segment = 0
    @State private var toggle = true
    @State private var selectedChip = "protein"
    @State private var tab = "today"

    private let sample: [DSChartPoint] = {
        let now = Date()
        return (0..<14).map { i in
            DSChartPoint(
                date: Calendar.current.date(byAdding: .day, value: -13 + i, to: now) ?? now,
                value: 84.5 - Double(i) * 0.15
            )
        }
    }()

    var body: some View {
        ZStack(alignment: .bottom) {
            DSScreen(title: "Design system", subtitle: "Every component, one screen") {
                VStack(alignment: .leading, spacing: DS.Space.xxl) {
                    colorSection
                    typeSection
                    coachSection
                    ringSection
                    metricSection
                    chartSection
                    controlSection
                    glassSection
                    stateSection
                }
            }

            DSTabBar(
                tabs: [.today, .progress, .scan, .coach, .profile],
                selection: $tab,
                centerIndex: 2
            )
            .padding(.bottom, DS.Space.sm)
        }
    }

    // MARK: Sections

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Colour").dsOverline()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.sm), count: 4), spacing: DS.Space.sm) {
                swatch("brand", DS.Colors.brand)
                swatch("ai", DS.Colors.ai)
                swatch("success", DS.Colors.success)
                swatch("danger", DS.Colors.danger)
                ForEach(DSMetric.allCases) { metric in
                    swatch(metric.rawValue, metric.color)
                }
            }
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: DS.Space.xs) {
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .fill(color)
                .frame(height: 44)
            Text(name)
                .dsText(DS.Typography.caption, color: DS.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Typography").dsOverline()
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text("Display").dsText(DS.Typography.display)
                    Text("Title 1").dsText(DS.Typography.title1)
                    Text("Title 3").dsText(DS.Typography.title3)
                    Text("Headline").dsText(DS.Typography.headline)
                    Text("Body — the quick brown fox jumps over the lazy dog.")
                        .dsText(DS.Typography.body, color: DS.Colors.textSecondary)
                    Text("Footnote").dsText(DS.Typography.footnote, color: DS.Colors.textTertiary)
                    Text("2,450").dsHeroNumber()
                }
            }
        }
    }

    private var coachSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("AI coach").dsOverline()
            DSCoachCard(
                message: "Your average deficit was 420 kcal this week, which puts you on track for roughly 0.4 kg. Protein is the one gap — you're 18 g/day under, and closing it protects muscle while the deficit does its work.",
                score: 78,
                actionTitle: "Adjust my targets",
                action: {}
            )
            DSCoachCard(message: "", isLoading: true)
        }
    }

    private var ringSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Rings").dsOverline()
            DSCard {
                DSRingSummary(entries: [
                    DSRingEntry(.calories, value: 1840, goal: 2100),
                    DSRingEntry(.protein, value: 132, goal: 150),
                    DSRingEntry(.water, value: 2400, goal: 2500),
                    DSRingEntry(.steps, value: 11200, goal: 10000)
                ])
            }
            DSCard {
                HStack {
                    DSScoreDial(score: 78)
                    Spacer()
                    DSScoreDial(score: 42, size: 100)
                }
            }
        }
    }

    private var metricSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Metric cards").dsOverline()
            DSMetricCard(
                metric: .weight,
                value: 82.4,
                delta: -0.6,
                decimals: 1,
                lowerIsBetter: true,
                sparkline: [84.1, 83.8, 83.9, 83.4, 83.0, 82.7, 82.4]
            )
            HStack(spacing: DS.Space.md) {
                DSStatTile(label: "BMI", value: "24.1", icon: "figure")
                DSStatTile(label: "Body fat", value: "19%", icon: "percent", tint: DS.Colors.protein)
                DSStatTile(label: "Streak", value: "12d", icon: "flame.fill", tint: DS.Colors.calories)
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Charts").dsOverline()
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    DSSectionHeader(title: "Weight", subtitle: "Drag to scrub")
                    DSTrendChart(points: sample, color: DS.Colors.weight, showsAverage: true)
                }
            }
            DSCard {
                DSMacroBar(protein: 132, carbs: 210, fat: 64)
            }
        }
    }

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Controls").dsOverline()
            VStack(spacing: DS.Space.md) {
                DSPrimaryButton(title: "Continue", icon: "arrow.right") {}
                DSSecondaryButton(title: "Scan a meal", icon: "camera.fill") {}
                DSSegmentedControl(
                    options: [(0, "Week"), (1, "Month"), (2, "Year")],
                    selection: $segment
                )
                HStack(spacing: DS.Space.sm) {
                    DSChip(title: "High protein", icon: "bolt.fill", isSelected: selectedChip == "protein") {
                        selectedChip = "protein"
                    }
                    DSChip(title: "Low carb", isSelected: selectedChip == "carb") {
                        selectedChip = "carb"
                    }
                    Spacer()
                }
                DSCard {
                    DSToggleRow(
                        title: "Daily reminders",
                        subtitle: "A nudge at 9am if you haven't logged",
                        icon: "bell.fill",
                        isOn: $toggle
                    )
                }
            }
        }
    }

    // Glass belongs to the functional layer only. This section exists to
    // verify it renders — and, more importantly, to check that it goes
    // fully opaque under Reduce Transparency.
    private var glassSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Liquid glass — functional layer").dsOverline()

            Text("Toggle Settings → Accessibility → Display & Text Size → Reduce Transparency. Everything below must become fully opaque.")
                .dsText(DS.Typography.footnote, color: DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, DS.Space.xs)

            // Something to refract. Glass over a flat fill reads as grey
            // plastic, on device as much as in a preview.
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(DS.Colors.aiGradient)

                DSGlassContainer(spacing: DS.Space.lg) {
                    HStack(spacing: DS.Space.lg) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(DS.Colors.textPrimary)
                            .frame(width: 52, height: 52)
                            .dsGlass(in: Circle(), interactive: true)

                        Text("Floating control")
                            .dsText(DS.Typography.subheadline)
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.vertical, DS.Space.md)
                            .dsGlass(in: Capsule())
                    }
                }
            }
            .frame(height: 150)

            DSBanner(
                kind: .info,
                message: "Content cards stay solid. Glass is only for the tab bar, floating actions, toolbars and sheet chrome."
            )
        }
    }

    private var stateSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("States").dsOverline()
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
                    message: "Point your camera at a plate and the coach estimates the macros.",
                    actionTitle: "Scan a meal",
                    action: {}
                )
            }
        }
    }
}

#Preview("Gallery — Light") {
    DSGallery()
}

#Preview("Gallery — Dark") {
    DSGallery()
        .preferredColorScheme(.dark)
}

#Preview("Gallery — Large text") {
    DSGallery()
        .environment(\.sizeCategory, .accessibilityLarge)
}
