//
//  DSRings.swift
//  AI Weight Loss Coach — Design System
//
//  Progress rings, single and clustered.
//
//  Rings over-fill rather than cap at 100%: going past the goal draws a
//  brighter second lap, which is the reward for overshooting.
//

import SwiftUI

// MARK: - Single ring

struct DSProgressRing: View {
    /// 0...n — values above 1 draw a second lap.
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 12
    var size: CGFloat = 120
    /// Optional SF Symbol drawn in the centre.
    var icon: String?
    /// Set false when the ring is decorative and a label sits beside it.
    var animateOnAppear: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    private var firstLap: Double { min(animatedProgress, 1) }
    private var secondLap: Double { max(0, min(animatedProgress - 1, 1)) }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)

            // First lap
            Circle()
                .trim(from: 0, to: firstLap)
                .stroke(
                    DS.Colors.ringGradient(color),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Overshoot lap, drawn brighter and slightly inset so the
            // overlap stays readable.
            if secondLap > 0 {
                Circle()
                    .trim(from: 0, to: secondLap)
                    .stroke(
                        Color.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: lineWidth * 0.4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .blendMode(.overlay)
            }

            if let icon {
                Image(systemName: icon)
                    .font(.system(size: lineWidth * 1.1, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animateOnAppear, !reduceMotion else {
                animatedProgress = progress
                return
            }
            withAnimation(DS.Motion.flourish) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(reduceMotion ? nil : DS.Motion.flourish) {
                animatedProgress = newValue
            }
        }
        .accessibilityElement()
        .accessibilityValue(DSFormat.percent(progress))
    }
}

// MARK: - Ring cluster
//
// Concentric rings, Apple Fitness style. Cap this at five — beyond that
// the inner rings get too small to read or tap.

struct DSRingEntry: Identifiable {
    let id = UUID()
    let metric: DSMetric
    let value: Double
    let goal: Double

    var progress: Double { goal > 0 ? value / goal : 0 }

    init(_ metric: DSMetric, value: Double, goal: Double) {
        self.metric = metric
        self.value = value
        self.goal = goal
    }
}

struct DSRingCluster: View {
    let entries: [DSRingEntry]
    var size: CGFloat = 180
    var lineWidth: CGFloat = 14
    var spacing: CGFloat = 5

    private var capped: [DSRingEntry] { Array(entries.prefix(5)) }

    var body: some View {
        ZStack {
            ForEach(Array(capped.enumerated()), id: \.element.id) { index, entry in
                let inset = CGFloat(index) * (lineWidth + spacing) * 2
                DSProgressRing(
                    progress: entry.progress,
                    color: entry.metric.color,
                    lineWidth: lineWidth,
                    size: size - inset,
                    icon: nil
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily progress")
        .accessibilityValue(
            capped
                .map { "\($0.metric.label) \(DSFormat.percent($0.progress))" }
                .joined(separator: ", ")
        )
    }
}

// MARK: - Ring with legend

struct DSRingSummary: View {
    let entries: [DSRingEntry]
    var size: CGFloat = 170

    var body: some View {
        HStack(spacing: DS.Space.xl) {
            DSRingCluster(entries: entries, size: size)

            VStack(alignment: .leading, spacing: DS.Space.md) {
                ForEach(entries.prefix(5)) { entry in
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: entry.metric.icon)
                            .font(.system(size: DS.Size.iconSm, weight: .semibold))
                            .foregroundStyle(entry.metric.color)
                            .frame(width: DS.Size.iconMd)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.metric.label)
                                .dsText(DS.Typography.caption, color: DS.Colors.textTertiary)
                            Text("\(DSFormat.value(entry.value)) / \(DSFormat.value(entry.goal))")
                                .dsText(DS.Typography.metricSmall)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Compact linear progress
//
// For places a ring is too heavy: habit rows, macro breakdowns.

struct DSProgressBar: View {
    let progress: Double
    let color: Color
    var height: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(color.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * min(max(animated, 0), 1))
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(reduceMotion ? nil : DS.Motion.flourish) {
                animated = progress
            }
        }
        .onChange(of: progress) { _, new in
            withAnimation(reduceMotion ? nil : DS.Motion.standard) {
                animated = new
            }
        }
        .accessibilityElement()
        .accessibilityValue(DSFormat.percent(progress))
    }
}

// MARK: - Health score dial

struct DSScoreDial: View {
    /// 0...100
    let score: Int
    var size: CGFloat = 120

    var body: some View {
        ZStack {
            DSProgressRing(
                progress: Double(score) / 100,
                color: DS.Colors.score(score),
                lineWidth: 12,
                size: size
            )
            VStack(spacing: 0) {
                Text("\(score)")
                    .dsHeroNumber()
                Text("Health score")
                    .dsText(DS.Typography.caption, color: DS.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DS.Space.sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health score")
        .accessibilityValue("\(score) out of 100")
    }
}

#Preview("Rings") {
    ScrollView {
        VStack(spacing: DS.Space.xxl) {
            DSRingSummary(entries: [
                DSRingEntry(.calories, value: 1840, goal: 2100),
                DSRingEntry(.protein, value: 132, goal: 150),
                DSRingEntry(.water, value: 2400, goal: 2500),
                DSRingEntry(.steps, value: 11200, goal: 10000)
            ])

            DSScoreDial(score: 78)

            DSProgressBar(progress: 0.62, color: DS.Colors.protein)
                .frame(height: 8)
        }
        .padding(DS.Space.lg)
    }
    .background(DS.Colors.background)
}
