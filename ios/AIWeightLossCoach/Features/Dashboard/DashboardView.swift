import Charts
import SwiftUI

@MainActor
@Observable
final class DashboardViewModel {
    var dashboard: Dashboard?
    var checkIn: CheckInPrompt?
    var prediction: WeightPrediction?
    var isLoading = false
    var errorMessage: String?

    func load() async {
        isLoading = dashboard == nil
        defer { isLoading = false }
        do {
            dashboard = try await APIClient.shared.get("dashboard")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        // Secondary cards must never block the dashboard, so they fail quietly.
        checkIn = try? await APIClient.shared.get("checkin/today")
        prediction = try? await APIClient.shared.get("weight/prediction")
    }
}

struct DashboardView: View {
    @Binding var showPaywall: Bool
    @Environment(SessionStore.self) private var session
    @Environment(HealthKitManager.self) private var health
    @State private var model = DashboardViewModel()
    @State private var showLogWeight = false
    @State private var showLogWater = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let message = model.errorMessage {
                        ErrorBanner(message: message) { model.errorMessage = nil }
                    }

                    if let data = model.dashboard {
                        headline(data)
                        if let prompt = model.checkIn, !prompt.completed { checkInCard(prompt) }
                        quickActions
                        tiles(data)
                        calorieCard(data)
                        if let prediction = model.prediction, prediction.hasEnoughData {
                            predictionCard(prediction)
                        }
                        weightChart(data)
                        stepChart(data)
                        if data.habitsTotal > 0 { habitCard(data) }
                    } else if model.isLoading {
                        ProgressView().padding(.top, 60)
                    } else {
                        EmptyStateView(
                            systemImage: "arrow.clockwise",
                            title: "Nothing loaded yet",
                            message: "Pull to refresh, or check your connection.",
                            actionTitle: "Try again",
                            action: { Task { await model.load() } }
                        )
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(greeting)
            .refreshable {
                await health.syncAll()
                await model.load()
                await session.refreshUser()
            }
            .task { await model.load() }
            .sheet(isPresented: $showLogWeight) {
                LogWeightSheet { await model.load() }
            }
            .sheet(isPresented: $showLogWater) {
                LogWaterSheet { await model.load() }
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = session.user?.fullName?.split(separator: " ").first.map(String.init)
        let part = switch hour {
        case 0..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        return name.map { "\(part), \($0)" } ?? part
    }

    private func headline(_ data: Dashboard) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 20) {
                ZStack {
                    RingGauge(progress: data.goalProgressPct / 100, lineWidth: 10, tint: Palette.pine)
                        .frame(width: 96, height: 96)
                    VStack(spacing: 0) {
                        Text("\(Int(data.goalProgressPct))%")
                            .font(.title3.weight(.bold)).monospacedDigit()
                        Text("to goal").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(Units.kg(data.weightKg))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if data.weightChange7dKg != 0 {
                        Label(
                            String(format: "%+.1f kg this week", data.weightChange7dKg),
                            systemImage: data.weightChange7dKg < 0 ? "arrow.down.right" : "arrow.up.right"
                        )
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(data.weightChange7dKg < 0 ? Palette.pine : Palette.coral)
                    }
                    if let bmi = data.bmi, let category = data.bmiCategory {
                        Text("BMI \(String(format: "%.1f", bmi)) · \(category)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let goal = data.goalWeightKg, let current = data.weightKg, current > goal {
                Text("\(String(format: "%.1f", current - goal)) kg to go.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardSurface()
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            actionButton("Weigh in", "scalemass") { showLogWeight = true }
            actionButton("Water", "drop.fill") { showLogWater = true }
            NavigationLink {
                ScanMealView(showPaywall: $showPaywall)
            } label: {
                actionLabel("Scan meal", "camera.viewfinder")
            }
            .buttonStyle(.plain)
        }
    }

    private func actionButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, icon) }.buttonStyle(.plain)
    }

    private func actionLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Palette.pine.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(Palette.pine)
    }

    private func tiles(_ data: Dashboard) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(
                title: "Steps",
                value: Units.count(data.steps),
                caption: "of \(Units.count(data.stepTarget)) · \(data.stepStreak) day streak",
                systemImage: "shoeprints.fill",
                tint: Palette.plum
            )
            StatTile(
                title: "Water",
                value: Units.litres(data.waterMl),
                caption: "of \(Units.litres(data.waterTargetMl))",
                systemImage: "drop.fill",
                tint: Palette.water
            )
            StatTile(
                title: "Calories left",
                value: "\(Int(data.caloriesRemaining))",
                caption: "\(Int(data.caloriesConsumed)) of \(data.calorieTarget) eaten",
                systemImage: "flame.fill",
                tint: Palette.amber
            )
            StatTile(
                title: "Level \(data.level)",
                value: "\(Units.count(data.xp)) XP",
                caption: "\(data.habitsDone)/\(max(data.habitsTotal, 0)) habits today",
                systemImage: "rosette",
                tint: Palette.pine
            )
        }
    }

    private func calorieCard(_ data: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's intake").sectionTitle()
            ProgressBar(value: data.caloriesConsumed / Double(max(data.calorieTarget, 1)), tint: Palette.amber, height: 10)
            HStack {
                Text("\(Int(data.caloriesConsumed)) kcal").font(.headline).monospacedDigit()
                Spacer()
                Text("Target \(data.calorieTarget)").font(.caption).foregroundStyle(.secondary)
            }
            MacroChips(protein: data.proteinG, carbs: data.carbsG, fat: data.fatG)
        }
        .cardSurface()
    }

    private func weightChart(_ data: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weight · 30 days").sectionTitle()
            if data.weightSeries.count > 1 {
                Chart(data.weightSeries) { point in
                    AreaMark(x: .value("Day", point.day), y: .value("Weight", point.value))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Palette.pine.opacity(0.28), Palette.pine.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    LineMark(x: .value("Day", point.day), y: .value("Weight", point.value))
                        .foregroundStyle(Palette.pine)
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
            } else {
                Text("Log a few weigh-ins and the trend line shows up here.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(height: 60)
            }
        }
        .cardSurface()
    }

    private func stepChart(_ data: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Steps · 30 days").sectionTitle()
            if data.stepSeries.isEmpty {
                Text("Connect Health in the You tab to fill this in automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(height: 60)
            } else {
                Chart {
                    ForEach(data.stepSeries) { point in
                        BarMark(x: .value("Day", point.day, unit: .day), y: .value("Steps", point.value))
                            .foregroundStyle(point.value >= Double(data.stepTarget) ? Palette.plum : Palette.plum.opacity(0.35))
                            .cornerRadius(3)
                    }
                    RuleMark(y: .value("Goal", data.stepTarget))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .frame(height: 150)
            }
        }
        .cardSurface()
    }

    private func checkInCard(_ prompt: CheckInPrompt) -> some View {
        NavigationLink {
            CheckInView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Palette.amber.opacity(0.16)).frame(width: 44, height: 44)
                    Image(systemName: "checklist")
                        .foregroundStyle(Palette.amber)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily check-in").font(.subheadline.weight(.semibold))
                    Text(prompt.streak > 0
                         ? "Keep your \(prompt.streak)-day streak going"
                         : "Two minutes, and the coach reads your numbers back")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    private func predictionCard(_ prediction: WeightPrediction) -> some View {
        NavigationLink {
            PredictionView()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Projection").sectionTitle()
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
                if prediction.goalReachable, let day = prediction.goalDay {
                    Text(day.formatted(.dateTime.month(.wide).day().year()))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(prediction.weeksToGoal.map { "On track to hit your goal in about \($0) week\($0 == 1 ? "" : "s")." }
                         ?? "On track to hit your goal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(prediction.plateauDetected ? "Holding steady" : "No date yet")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Your current trend doesn't project to your goal. Tap for the detail.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    private func habitCard(_ data: Dashboard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Habits").sectionTitle()
            HStack {
                Text("\(data.habitsDone) of \(data.habitsTotal) done")
                    .font(.headline)
                Spacer()
                Text("Level \(data.level)").font(.caption).foregroundStyle(.secondary)
            }
            ProgressBar(
                value: Double(data.habitsDone) / Double(max(data.habitsTotal, 1)),
                tint: Palette.pine
            )
        }
        .cardSurface()
    }
}
