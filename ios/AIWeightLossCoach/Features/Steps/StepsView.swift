import Charts
import SwiftUI

@MainActor
@Observable
final class StepsViewModel {
    var stats: StepStats?
    var isLoading = false
    var errorMessage: String?

    func load() async {
        isLoading = stats == nil
        defer { isLoading = false }
        do {
            stats = try await APIClient.shared.get("steps/stats")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct StepsView: View {
    @Environment(HealthKitManager.self) private var health
    @State private var model = StepsViewModel()
    @State private var isSyncing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                }
                if health.status != .authorized {
                    healthPrompt
                }

                if let stats = model.stats {
                    todayCard(stats)
                    streakCard(stats)
                    chart(stats)
                    weekTable(stats)
                } else if model.isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    EmptyStateView(
                        systemImage: "shoeprints.fill",
                        title: "No step data yet",
                        message: "Connect Apple Health and your steps fill in automatically.",
                        actionTitle: "Connect Health",
                        action: { Task { await health.requestAuthorization(); await sync() } }
                    )
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await sync() }
        .task {
            await model.load()
            await sync()
        }
    }

    private var healthPrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.text.square").font(.title2).foregroundStyle(Palette.coral)
            VStack(alignment: .leading, spacing: 2) {
                Text("Health isn't connected").font(.subheadline.weight(.semibold))
                Text("Steps won't update on their own until you allow access.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Allow") { Task { await health.requestAuthorization(); await sync() } }
                .buttonStyle(.bordered)
        }
        .cardSurface()
    }

    private func todayCard(_ stats: StepStats) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RingGauge(
                    progress: Double(stats.today) / Double(max(stats.goal, 1)),
                    lineWidth: 14,
                    tint: Palette.plum
                )
                .frame(width: 150, height: 150)
                VStack(spacing: 2) {
                    Text(Units.count(stats.today))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("of \(Units.count(stats.goal))").font(.caption).foregroundStyle(.secondary)
                }
            }
            if isSyncing {
                Label("Syncing with Health…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let last = health.lastSync {
                Text("Last synced \(last.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private func streakCard(_ stats: StepStats) -> some View {
        HStack(spacing: 12) {
            statBox("Streak", "\(stats.currentStreak)", "days at goal", Palette.amber)
            statBox("Best run", "\(stats.longestStreak)", "days", Palette.pine)
            statBox("Week avg", Units.count(stats.weekAverage), "steps/day", Palette.plum)
        }
    }

    private func statBox(_ title: String, _ value: String, _ caption: String, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(tint)
            Text(title).font(.caption.weight(.medium))
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private func chart(_ stats: StepStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 30 days").sectionTitle()
            Chart {
                ForEach(stats.series) { day in
                    BarMark(x: .value("Day", day.recordedOn, unit: .day), y: .value("Steps", day.steps))
                        .foregroundStyle(day.steps >= stats.goal ? Palette.plum : Palette.plum.opacity(0.35))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Goal", stats.goal))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .frame(height: 180)
        }
        .cardSurface()
    }

    private func weekTable(_ stats: StepStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This week").sectionTitle()
            ForEach(stats.series.suffix(7).reversed()) { day in
                HStack {
                    Text(day.recordedOn.formatted(.dateTime.weekday(.wide)))
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1f km", day.distanceM / 1000))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(Units.count(day.steps))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .frame(width: 74, alignment: .trailing)
                    Image(systemName: day.steps >= stats.goal ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(day.steps >= stats.goal ? Palette.pine : Color(.systemGray4))
                }
                .padding(.vertical, 5)
                Divider()
            }
        }
        .cardSurface()
    }

    private func sync() async {
        isSyncing = true
        defer { isSyncing = false }
        if let fresh = await health.syncSteps(days: 30) {
            model.stats = fresh
        } else {
            await model.load()
        }
    }
}
