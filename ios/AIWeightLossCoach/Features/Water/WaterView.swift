import Charts
import SwiftUI

@MainActor
@Observable
final class WaterViewModel {
    var stats: WaterStats?
    var isLoading = false
    var errorMessage: String?

    func load() async {
        isLoading = stats == nil
        defer { isLoading = false }
        do {
            stats = try await APIClient.shared.get("water/stats")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func add(_ ml: Int) async {
        do {
            _ = try await APIClient.shared.postVoid("water", body: ["amount_ml": ml])
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct WaterView: View {
    @Environment(HealthKitManager.self) private var health
    @State private var model = WaterViewModel()
    @State private var showCustom = false

    private let presets = [200, 330, 500, 750]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                }

                if let stats = model.stats {
                    ring(stats)
                    quickAdd
                    weekChart(stats)
                    streakRow(stats)
                } else if model.isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    EmptyStateView(
                        systemImage: "drop",
                        title: "Nothing logged today",
                        message: "Tap a glass size below to start.",
                        actionTitle: nil,
                        action: nil
                    )
                    quickAdd
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .task { await model.load() }
        .sheet(isPresented: $showCustom) {
            LogWaterSheet { await model.load() }
        }
    }

    private func ring(_ stats: WaterStats) -> some View {
        VStack(spacing: 12) {
            ZStack {
                RingGauge(progress: stats.progressPct / 100, lineWidth: 14, tint: Palette.water)
                    .frame(width: 150, height: 150)
                VStack(spacing: 2) {
                    Text(Units.litres(stats.todayMl))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("of \(Units.litres(stats.goalMl))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if stats.todayMl >= stats.goalMl {
                Label("Goal hit for today", systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.water)
            }
        }
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a drink").sectionTitle()
            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { amount in
                    Button {
                        Task {
                            await model.add(amount)
                            health.writeWater(millilitres: amount)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "drop.fill").font(.subheadline)
                            Text("\(amount)").font(.subheadline.weight(.semibold)).monospacedDigit()
                            Text("ml").font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Palette.water.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(Palette.water)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Custom amount") { showCustom = true }
                .font(.subheadline)
        }
        .cardSurface()
    }

    private func weekChart(_ stats: WaterStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily total").sectionTitle()
            Chart {
                ForEach(stats.series) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("ml", day.ml))
                        .foregroundStyle(day.ml >= stats.goalMl ? Palette.water : Palette.water.opacity(0.4))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Goal", stats.goalMl))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .frame(height: 160)
        }
        .cardSurface()
    }

    private func streakRow(_ stats: WaterStats) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(stats.currentStreak) day streak").font(.headline)
                Text("Days you hit the goal in a row").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Units.litres(stats.weekAverageMl)).font(.headline).monospacedDigit()
                Text("Week average").font(.caption).foregroundStyle(.secondary)
            }
        }
        .cardSurface()
    }
}

struct LogWaterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitManager.self) private var health

    let onSaved: () async -> Void

    @State private var amount: Double = 250
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text("\(Int(amount)) ml").font(.title3.weight(.semibold)).monospacedDigit()
                    }
                    Slider(value: $amount, in: 50...1500, step: 10).tint(Palette.water)
                }
                if let errorMessage {
                    Section { ErrorBanner(message: errorMessage) }
                }
            }
            .navigationTitle("Log water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                }
            }
        }
    }

    private func save() async {
        do {
            _ = try await APIClient.shared.postVoid("water", body: ["amount_ml": Int(amount)])
            health.writeWater(millilitres: Int(amount))
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
