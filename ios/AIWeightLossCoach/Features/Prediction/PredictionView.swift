import Charts
import SwiftUI

@MainActor
@Observable
final class PredictionViewModel {
    var prediction: WeightPrediction?
    var history: [WeightEntry] = []
    var horizon: Horizon = .weekly
    var isLoading = false
    var errorMessage: String?

    enum Horizon: String, CaseIterable, Identifiable {
        case weekly = "12 weeks"
        case monthly = "6 months"
        var id: String { rawValue }
    }

    var projection: [ProjectionPoint] {
        guard let prediction else { return [] }
        return horizon == .weekly ? prediction.weeklyProjection : prediction.monthlyProjection
    }

    func load() async {
        isLoading = prediction == nil
        defer { isLoading = false }
        do {
            async let forecast: WeightPrediction = APIClient.shared.get("weight/prediction")
            async let stats: WeightStats = APIClient.shared.get("weight/stats", query: ["days": "120"])
            prediction = try await forecast
            history = try await stats.series
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PredictionView: View {
    @State private var model = PredictionViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                }

                if let prediction = model.prediction {
                    if prediction.hasEnoughData {
                        goalCard(prediction)
                        chart(prediction)
                        horizonPicker
                        breakdown(prediction)
                        if !prediction.notes.isEmpty { notes(prediction) }
                        confidenceCard(prediction)
                    } else {
                        notEnoughData(prediction)
                    }
                } else if model.isLoading {
                    ProgressView().padding(.top, 60)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Projection")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    // MARK: - Empty state

    private func notEnoughData(_ prediction: WeightPrediction) -> some View {
        VStack(spacing: 16) {
            EmptyStateView(
                systemImage: "chart.line.uptrend.xyaxis",
                title: "Not enough data yet",
                message: prediction.reason ?? "Log a few more weigh-ins and a projection appears here.",
                actionTitle: nil,
                action: nil
            )
            if let current = prediction.currentKg, let goal = prediction.goalKg {
                HStack(spacing: 12) {
                    metricBox("Now", Units.kg(current), Palette.pine)
                    metricBox("Goal", Units.kg(goal), Palette.amber)
                    metricBox("To go", String(format: "%.1f kg", max(current - goal, 0)), Palette.plum)
                }
            }
            Text("A projection built on two or three readings mostly measures water weight. We'd rather show nothing than something misleading.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .cardSurface()
    }

    // MARK: - Goal headline

    private func goalCard(_ prediction: WeightPrediction) -> some View {
        VStack(spacing: 16) {
            if let goalDay = prediction.goalDay, prediction.goalReachable {
                VStack(spacing: 6) {
                    Text("Expected to reach goal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(goalDay.formatted(.dateTime.month(.wide).day().year()))
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    if let weeks = prediction.weeksToGoal {
                        Text(weeks == 0 ? "You're there" : "about \(weeks) week\(weeks == 1 ? "" : "s") away")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .font(.title)
                        .foregroundStyle(Palette.amber)
                    Text("No reliable date yet")
                        .font(.headline)
                    Text(prediction.plateauDetected
                         ? "Your weight has been holding steady, so there's no downward trend to project from."
                         : "Your current trend isn't heading toward your goal.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Divider()

            HStack(spacing: 12) {
                metricBox("Lost", String(format: "%.1f kg", prediction.lostKg), Palette.pine)
                metricBox("To go", String(format: "%.1f kg", prediction.remainingKg), Palette.amber)
                metricBox(
                    "Per week",
                    String(format: "%+.2f", prediction.trendKgPerWeek),
                    prediction.trendKgPerWeek < 0 ? Palette.pine : Palette.coral
                )
            }
        }
        .cardSurface()
    }

    private func metricBox(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Chart

    private func chart(_ prediction: WeightPrediction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logged and projected").sectionTitle()

            Chart {
                ForEach(model.history) { entry in
                    LineMark(
                        x: .value("Day", entry.recordedOn),
                        y: .value("Weight", entry.weightKg),
                        series: .value("Series", "Logged")
                    )
                    .foregroundStyle(Palette.pine)
                    .interpolationMethod(.catmullRom)
                }

                ForEach(model.projection) { point in
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Weight", point.weightKg),
                        series: .value("Series", "Projected")
                    )
                    .foregroundStyle(Palette.amber)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .interpolationMethod(.catmullRom)
                }

                if let goal = prediction.goalKg {
                    RuleMark(y: .value("Goal", goal))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Goal \(Units.kg(goal))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartForegroundStyleScale([
                "Logged": Palette.pine,
                "Projected": Palette.amber
            ])
            .chartLegend(position: .bottom, spacing: 8)
            .frame(height: 240)

            Text("The dashed line is a projection, not a promise. It assumes your recent habits hold steady.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private var horizonPicker: some View {
        Picker("Horizon", selection: Binding(
            get: { model.horizon },
            set: { model.horizon = $0 }
        )) {
            ForEach(PredictionViewModel.Horizon.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Table

    private func breakdown(_ prediction: WeightPrediction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.horizon == .weekly ? "Weekly projection" : "Monthly projection").sectionTitle()

            ForEach(model.projection) { point in
                HStack {
                    Text(point.day.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.subheadline)
                    Spacer()
                    if let current = prediction.smoothedKg {
                        Text(String(format: "%+.1f", point.weightKg - current))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    Text(Units.kg(point.weightKg))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                }
                .padding(.vertical, 5)
                Divider()
            }
        }
        .cardSurface()
    }

    private func notes(_ prediction: WeightPrediction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Worth knowing").sectionTitle()
            ForEach(Array(prediction.notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Palette.amber)
                        .padding(.top, 2)
                    Text(note).font(.footnote)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func confidenceCard(_ prediction: WeightPrediction) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(confidenceTint(prediction.confidence).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: confidenceIcon(prediction.confidence))
                    .foregroundStyle(confidenceTint(prediction.confidence))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(prediction.confidence.capitalized) confidence")
                    .font(.subheadline.weight(.semibold))
                Text(confidenceBlurb(prediction))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .cardSurface()
    }

    private func confidenceBlurb(_ prediction: WeightPrediction) -> String {
        switch prediction.confidence {
        case "high": "Your weigh-ins are frequent and consistent, so this trend is well supported."
        case "moderate": "A reasonable trend, but more frequent weigh-ins would tighten it up."
        default: "Your readings vary a lot day to day. Weigh in at the same time each morning for a clearer signal."
        }
    }

    private func confidenceTint(_ level: String) -> Color {
        switch level {
        case "high": Palette.pine
        case "moderate": Palette.amber
        default: Palette.coral
        }
    }

    private func confidenceIcon(_ level: String) -> String {
        switch level {
        case "high": "checkmark.seal.fill"
        case "moderate": "chart.bar.fill"
        default: "exclamationmark.triangle.fill"
        }
    }
}
