//
//  DSCharts.swift
//  AI Weight Loss Coach — Design System
//
//  Thin wrappers over Swift Charts so every chart in the app shares axis
//  styling, gradients and interaction. Screens pass data, never config.
//

import Charts
import SwiftUI

// MARK: - Data point

struct DSChartPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let value: Double

    init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

// MARK: - Trend line
//
// The workhorse: weight, calories, water over time, with a gradient area
// fill and an optional scrubbable selection.

struct DSTrendChart: View {
    let points: [DSChartPoint]
    var color: Color = DS.Colors.brand
    var showsArea: Bool = true
    var showsAverage: Bool = false
    /// Nil lets Swift Charts pick. Supply a range to stop small changes
    /// looking dramatic — important for weight.
    var yDomain: ClosedRange<Double>?
    var height: CGFloat = 200

    @State private var selectedPoint: DSChartPoint?

    private var average: Double {
        guard !points.isEmpty else { return 0 }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }

    var body: some View {
        Chart {
            if showsArea {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.28), color.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                .foregroundStyle(color)
            }

            if showsAverage {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(DS.Colors.textTertiary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("avg \(DSFormat.value(average, decimals: 1))")
                            .dsText(DS.Typography.caption, color: DS.Colors.textTertiary)
                    }
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected", selectedPoint.date))
                    .foregroundStyle(DS.Colors.separator)

                PointMark(
                    x: .value("Date", selectedPoint.date),
                    y: .value("Value", selectedPoint.value)
                )
                .foregroundStyle(color)
                .symbolSize(120)
                .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                    VStack(spacing: 0) {
                        Text(DSFormat.value(selectedPoint.value, decimals: 1))
                            .dsText(DS.Typography.metricSmall)
                        Text(selectedPoint.date, format: .dateTime.day().month(.abbreviated))
                            .dsText(DS.Typography.caption, color: DS.Colors.textTertiary)
                    }
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xs)
                    .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .dsShadow(.low)
                }
            }
        }
        .chartYScale(domain: yDomain ?? autoDomain())
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(DS.Colors.separator)
                AxisValueLabel()
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.textTertiary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let origin = geo[proxy.plotFrame!].origin
                                let x = drag.location.x - origin.x
                                guard let date: Date = proxy.value(atX: x) else { return }
                                let nearest = points.min {
                                    abs($0.date.timeIntervalSince(date))
                                        < abs($1.date.timeIntervalSince(date))
                                }
                                if nearest != selectedPoint {
                                    DS.Haptics.selection()
                                    selectedPoint = nearest
                                }
                            }
                            .onEnded { _ in selectedPoint = nil }
                    )
            }
        }
        .frame(height: height)
        .accessibilityLabel("Trend chart")
    }

    /// Pads the domain by 8% so the line never touches the frame edges.
    private func autoDomain() -> ClosedRange<Double> {
        let values = points.map(\.value)
        guard let min = values.min(), let max = values.max(), min != max else {
            return 0...1
        }
        let padding = (max - min) * 0.08
        return (min - padding)...(max + padding)
    }
}

// MARK: - Forecast chart
//
// Actuals as a solid line, the projection dashed inside a confidence
// band. The band matters: a single predicted line implies a certainty
// the model does not have.

struct DSForecastChart: View {
    let actual: [DSChartPoint]
    let forecast: [DSChartPoint]
    /// Half-width of the confidence band, in the same unit as the values.
    var confidence: Double = 0.5
    var color: Color = DS.Colors.weight
    var goal: Double?
    var height: CGFloat = 220

    var body: some View {
        Chart {
            ForEach(forecast) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Low", point.value - confidence),
                    yEnd: .value("High", point.value + confidence)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color.opacity(0.14))
            }

            ForEach(actual) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value),
                    series: .value("Series", "Actual")
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                .foregroundStyle(color)
            }

            ForEach(forecast) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value),
                    series: .value("Series", "Forecast")
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 5]))
                .foregroundStyle(color.opacity(0.75))
            }

            if let goal {
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .foregroundStyle(DS.Colors.success)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal")
                            .dsText(DS.Typography.caption, color: DS.Colors.success)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(DS.Colors.separator)
                AxisValueLabel()
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.textTertiary)
            }
        }
        .frame(height: height)
        .accessibilityLabel("Weight forecast chart")
    }
}

// MARK: - Bar chart

struct DSBarChart: View {
    let points: [DSChartPoint]
    var color: Color = DS.Colors.brand
    /// Draws a dashed target line across the bars.
    var target: Double?
    var height: CGFloat = 180

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(DS.Radius.sm)
            }

            if let target {
                RuleMark(y: .value("Target", target))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(DS.Colors.separator)
                AxisValueLabel()
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.textTertiary)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Sparkline
//
// No axes, no labels. Sits inside metric cards.

struct DSSparkline: View {
    let values: [Double]
    var color: Color = DS.Colors.brand

    private var normalized: [(index: Int, value: Double)] {
        Array(values.enumerated()).map { ($0.offset, $0.element) }
    }

    var body: some View {
        Chart {
            ForEach(normalized, id: \.index) { item in
                AreaMark(
                    x: .value("Index", item.index),
                    y: .value("Value", item.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.25), color.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Index", item.index),
                    y: .value("Value", item.value)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .foregroundStyle(color)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: sparkDomain())
        .accessibilityHidden(true)
    }

    private func sparkDomain() -> ClosedRange<Double> {
        guard let min = values.min(), let max = values.max(), min != max else {
            return 0...1
        }
        let padding = (max - min) * 0.15
        return (min - padding)...(max + padding)
    }
}

// MARK: - Macro breakdown

struct DSMacroBar: View {
    let protein: Double
    let carbs: Double
    let fat: Double

    private var total: Double { max(protein + carbs + fat, 0.0001) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    segment(width: geo.size.width * (protein / total), color: DS.Colors.protein)
                    segment(width: geo.size.width * (carbs / total), color: DS.Colors.calories)
                    segment(width: geo.size.width * (fat / total), color: DS.Colors.water)
                }
            }
            .frame(height: 10)

            HStack(spacing: DS.Space.lg) {
                legend("Protein", DSFormat.value(protein) + "g", DS.Colors.protein)
                legend("Carbs", DSFormat.value(carbs) + "g", DS.Colors.calories)
                legend("Fat", DSFormat.value(fat) + "g", DS.Colors.water)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        Capsule().fill(color).frame(width: max(width, 0))
    }

    private func legend(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: DS.Space.xs) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).dsText(DS.Typography.caption, color: DS.Colors.textTertiary)
            Text(value).dsText(DS.Typography.caption.weight(.semibold))
        }
    }
}

#Preview("Charts") {
    let now = Date()
    let actual = (0..<14).map { i in
        DSChartPoint(
            date: Calendar.current.date(byAdding: .day, value: -13 + i, to: now)!,
            value: 84.5 - Double(i) * 0.16 + Double.random(in: -0.2...0.2)
        )
    }
    let forecast = (1...21).map { i in
        DSChartPoint(
            date: Calendar.current.date(byAdding: .day, value: i, to: now)!,
            value: 82.3 - Double(i) * 0.09
        )
    }

    return ScrollView {
        VStack(spacing: DS.Space.xl) {
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    DSSectionHeader(title: "Weight", subtitle: "Last 14 days")
                    DSTrendChart(points: actual, color: DS.Colors.weight, showsAverage: true)
                }
            }

            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    DSSectionHeader(title: "Forecast", subtitle: "Next 3 weeks")
                    DSForecastChart(actual: actual, forecast: forecast, goal: 78)
                }
            }

            DSCard {
                DSMacroBar(protein: 132, carbs: 210, fat: 64)
            }
        }
        .padding(DS.Space.lg)
    }
    .background(DS.Colors.background)
}
