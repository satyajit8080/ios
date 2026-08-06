import Charts
import SwiftUI

@MainActor
@Observable
final class AnalyticsViewModel {
    var summary: AnalyticsSummary?
    var range = 30
    var isLoading = false
    var errorMessage: String?

    func load() async {
        isLoading = summary == nil
        defer { isLoading = false }
        do {
            summary = try await APIClient.shared.get("analytics", query: ["days": String(range)])
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AnalyticsView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = AnalyticsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                }

                rangePicker

                if let summary = model.summary {
                    if !summary.insights.isEmpty { insights(summary) }
                    trendCard(
                        title: "Weight",
                        unit: "kg",
                        points: summary.weight,
                        tint: Palette.pine,
                        style: .line
                    )
                    trendCard(
                        title: "Calories eaten",
                        unit: "kcal",
                        points: summary.calories,
                        tint: Palette.amber,
                        style: .bar,
                        reference: session.user.map { Double($0.dailyCalorieTarget) }
                    )
                    trendCard(
                        title: "Steps",
                        unit: "steps",
                        points: summary.steps,
                        tint: Palette.plum,
                        style: .bar,
                        reference: session.user.map { Double($0.dailyStepTarget) }
                    )
                    trendCard(
                        title: "Water",
                        unit: "ml",
                        points: summary.water,
                        tint: Palette.water,
                        style: .bar,
                        reference: session.user.map { Double($0.dailyWaterMlTarget) }
                    )
                    trendCard(
                        title: "Habits completed",
                        unit: "per day",
                        points: summary.habitCompletion,
                        tint: Palette.coral,
                        style: .bar
                    )
                    consistencyCard(summary)
                } else if model.isLoading {
                    ProgressView().padding(.top, 40)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private var rangePicker: some View {
        Picker("Range", selection: Binding(
            get: { model.range },
            set: { model.range = $0; Task { await model.load() } }
        )) {
            Text("7 days").tag(7)
            Text("30 days").tag(30)
            Text("90 days").tag(90)
        }
        .pickerStyle(.segmented)
    }

    private func insights(_ summary: AnalyticsSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What stands out").sectionTitle()
            ForEach(Array(summary.insights.enumerated()), id: \.offset) { _, insight in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Palette.pine).frame(width: 6, height: 6).padding(.top, 6)
                    Text(insight).font(.footnote)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    enum TrendStyle { case line, bar }

    private func trendCard(
        title: String,
        unit: String,
        points: [TrendPoint],
        tint: Color,
        style: TrendStyle,
        reference: Double? = nil
    ) -> some View {
        let values = points.map(\.value).filter { $0 > 0 }
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).sectionTitle()
                Spacer()
                if average > 0 {
                    Text("avg \(format(average, unit: unit))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }

            if values.isEmpty {
                Text("Nothing recorded in this range.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(height: 50)
            } else {
                Chart {
                    ForEach(points) { point in
                        switch style {
                        case .line:
                            if point.value > 0 {
                                LineMark(x: .value("Day", point.day, unit: .day), y: .value(title, point.value))
                                    .foregroundStyle(tint)
                                    .interpolationMethod(.catmullRom)
                            }
                        case .bar:
                            BarMark(x: .value("Day", point.day, unit: .day), y: .value(title, point.value))
                                .foregroundStyle(tint.opacity(0.75))
                                .cornerRadius(2)
                        }
                    }
                    if let reference, reference > 0 {
                        RuleMark(y: .value("Target", reference))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartYScale(domain: style == .line ? .automatic(includesZero: false) : .automatic)
                .frame(height: 150)
            }
        }
        .cardSurface()
    }

    private func consistencyCard(_ summary: AnalyticsSummary) -> some View {
        let logged = summary.calories.filter { $0.value > 0 }.count
        let weighed = summary.weight.filter { $0.value > 0 }.count
        let stepped = summary.steps.filter { value in
            value.value >= Double(session.user?.dailyStepTarget ?? 10000)
        }.count

        return VStack(alignment: .leading, spacing: 12) {
            Text("Consistency").sectionTitle()
            HStack(spacing: 12) {
                consistencyBox("Logged meals", logged, summary.rangeDays)
                consistencyBox("Weighed in", weighed, summary.rangeDays)
                consistencyBox("Hit steps", stepped, summary.rangeDays)
            }
            Text("Consistency beats intensity — the days you show up matter more than any single perfect day.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private func consistencyBox(_ label: String, _ value: Int, _ total: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)/\(total)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func format(_ value: Double, unit: String) -> String {
        switch unit {
        case "kg": String(format: "%.1f kg", value)
        case "ml": Units.litres(Int(value))
        case "per day": String(format: "%.1f", value)
        default: "\(Int(value)) \(unit)"
        }
    }
}
