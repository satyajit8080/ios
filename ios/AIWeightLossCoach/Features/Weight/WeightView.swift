import Charts
import SwiftUI

@MainActor
@Observable
final class WeightViewModel {
    var stats: WeightStats?
    var isLoading = false
    var errorMessage: String?
    var range = 90

    func load() async {
        isLoading = stats == nil
        defer { isLoading = false }
        do {
            stats = try await APIClient.shared.get("weight/stats", query: ["days": String(range)])
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ entry: WeightEntry) async {
        _ = try? await APIClient.shared.delete("weight/\(entry.id.uuidString)")
        await load()
    }
}

struct WeightView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = WeightViewModel()
    @State private var showLog = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                }

                if let stats = model.stats {
                    summary(stats)
                    rangePicker
                    chart(stats)
                    history(stats)
                } else if model.isLoading {
                    ProgressView().padding(.top, 40)
                } else {
                    EmptyStateView(
                        systemImage: "scalemass",
                        title: "No weigh-ins yet",
                        message: "Log your first weight to start the trend line.",
                        actionTitle: "Log weight",
                        action: { showLog = true }
                    )
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button {
                showLog = true
            } label: {
                Label("Log weight", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Palette.pine)
            .padding(16)
            .background(.bar)
        }
        .task { await model.load() }
        .sheet(isPresented: $showLog) {
            LogWeightSheet {
                await model.load()
                await session.refreshUser()
            }
        }
    }

    private func summary(_ stats: WeightStats) -> some View {
        VStack(spacing: 14) {
            HStack {
                metric("Now", Units.kg(stats.currentKg))
                Divider().frame(height: 34)
                metric("Start", Units.kg(stats.startKg))
                Divider().frame(height: 34)
                metric("Goal", Units.kg(stats.goalKg))
            }

            ProgressBar(value: stats.goalProgressPct / 100, tint: Palette.pine, height: 10)

            HStack(spacing: 12) {
                delta("7 days", stats.change7dKg)
                delta("30 days", stats.change30dKg)
                delta("Overall", stats.changeKg)
            }

            if stats.trendKgPerWeek != 0 {
                Text(String(format: "Trend: %+.2f kg per week", stats.trendKgPerWeek))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardSurface()
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func delta(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 3) {
            Text(String(format: "%+.1f", value))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(value <= 0 ? Palette.pine : Palette.coral)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var rangePicker: some View {
        Picker("Range", selection: Binding(
            get: { model.range },
            set: { model.range = $0; Task { await model.load() } }
        )) {
            Text("30d").tag(30)
            Text("90d").tag(90)
            Text("6m").tag(180)
            Text("1y").tag(365)
        }
        .pickerStyle(.segmented)
    }

    private func chart(_ stats: WeightStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trend").sectionTitle()
            if stats.series.count > 1 {
                Chart {
                    ForEach(stats.series) { entry in
                        LineMark(x: .value("Day", entry.recordedOn), y: .value("Weight", entry.weightKg))
                            .foregroundStyle(Palette.pine)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Day", entry.recordedOn), y: .value("Weight", entry.weightKg))
                            .foregroundStyle(Palette.pine)
                            .symbolSize(18)
                    }
                    if let goal = stats.goalKg {
                        RuleMark(y: .value("Goal", goal))
                            .foregroundStyle(Palette.amber)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Goal").font(.caption2).foregroundStyle(Palette.amber)
                            }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 220)
            } else {
                Text("One more weigh-in and the chart fills in.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .cardSurface()
    }

    private func history(_ stats: WeightStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History").sectionTitle()
            ForEach(stats.series.reversed()) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.recordedOn.formatted(.dateTime.weekday(.abbreviated).day().month()))
                            .font(.subheadline)
                        if let note = entry.note, !note.isEmpty {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(Units.kg(entry.weightKg)).font(.headline).monospacedDigit()
                    Button {
                        Task { await model.delete(entry) }
                    } label: {
                        Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
        .cardSurface()
    }
}

struct LogWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitManager.self) private var health

    let onSaved: () async -> Void

    @State private var weight: Double = 75
    @State private var note = ""
    @State private var day = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Weight")
                        Spacer()
                        Text(String(format: "%.1f kg", weight))
                            .font(.title3.weight(.semibold)).monospacedDigit()
                    }
                    Slider(value: $weight, in: 35...250, step: 0.1).tint(Palette.pine)
                    DatePicker("Date", selection: $day, in: ...Date(), displayedComponents: .date)
                }
                Section("Note") {
                    TextField("Anything worth remembering?", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
                if let errorMessage {
                    Section { ErrorBanner(message: errorMessage) }
                }
            }
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(isSaving)
                }
            }
            .task {
                if let latest = await health.latestBodyMassKg() { weight = latest }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let body: [String: AnyEncodable] = [
                "weight_kg": AnyEncodable(weight),
                "note": AnyEncodable(note),
                "recorded_on": AnyEncodable(DateFormatter.awlcDay.string(from: day))
            ]
            _ = try await APIClient.shared.postVoid("weight", body: body)
            health.writeWeight(weight, on: day)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
