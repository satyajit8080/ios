import SwiftUI

@MainActor
@Observable
final class FoodLogViewModel {
    var summary: DaySummary?
    var day = Date()
    var isLoading = false
    var errorMessage: String?

    private let api = APIClient.shared

    func load() async {
        isLoading = summary == nil
        defer { isLoading = false }
        do {
            summary = try await api.get("meals", query: ["day": DateFormatter.awlcDay.string(from: day)])
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func shift(days: Int) async {
        day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day
        summary = nil
        await load()
    }

    func delete(_ meal: MealLog) async {
        _ = try? await api.delete("meals/\(meal.id.uuidString)")
        await load()
    }
}

struct FoodLogView: View {
    @Binding var showPaywall: Bool
    @Environment(HealthKitManager.self) private var health
    @State private var model = FoodLogViewModel()
    @State private var showSearch = false
    @State private var showScan = false

    private let mealOrder = ["breakfast", "lunch", "dinner", "snack"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dayBar
                    if let message = model.errorMessage {
                        ErrorBanner(message: message) { model.errorMessage = nil }
                    }
                    if let summary = model.summary {
                        totals(summary)
                        ForEach(mealOrder, id: \.self) { type in
                            mealSection(type, meals: summary.meals.filter { $0.mealType == type })
                        }
                    } else if model.isLoading {
                        ProgressView().padding(.top, 40)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { MealPlanView(showPaywall: $showPaywall) } label: {
                        Image(systemName: "list.clipboard")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    Button { showSearch = true } label: {
                        Label("Add food", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button { showScan = true } label: {
                        Label("Scan", systemImage: "camera.viewfinder").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Palette.pine)
                }
                .padding(16)
                .background(.bar)
            }
            .task { await model.load() }
            .sheet(isPresented: $showSearch) {
                FoodSearchView { await model.load() }
            }
            .sheet(isPresented: $showScan) {
                NavigationStack { ScanMealView(showPaywall: $showPaywall) }
            }
        }
    }

    private var dayBar: some View {
        HStack {
            Button { Task { await model.shift(days: -1) } } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(dayLabel).font(.headline)
            Spacer()
            Button { Task { await model.shift(days: 1) } } label: { Image(systemName: "chevron.right") }
                .disabled(Calendar.current.isDateInToday(model.day))
        }
        .padding(.horizontal, 4)
    }

    private var dayLabel: String {
        if Calendar.current.isDateInToday(model.day) { return "Today" }
        if Calendar.current.isDateInYesterday(model.day) { return "Yesterday" }
        return model.day.formatted(.dateTime.weekday(.wide).day().month())
    }

    private func totals(_ summary: DaySummary) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(summary.calories))")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("of \(summary.calorieTarget) kcal").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(max(summary.remainingCalories, 0)))")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(summary.remainingCalories >= 0 ? Palette.pine : Palette.coral)
                    Text(summary.remainingCalories >= 0 ? "left" : "over").font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressBar(value: summary.calories / Double(max(summary.calorieTarget, 1)), tint: Palette.amber, height: 10)
            MacroChips(protein: summary.proteinG, carbs: summary.carbsG, fat: summary.fatG)
        }
        .cardSurface()
    }

    private func mealSection(_ type: String, meals: [MealLog]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(type.capitalized).sectionTitle()
                Spacer()
                Text(Units.kcal(meals.reduce(0) { $0 + $1.calories }))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if meals.isEmpty {
                Text("Nothing logged.").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(meals) { meal in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.name).font(.subheadline)
                            Text("\(Int(meal.quantityG)) g · P \(Int(meal.proteinG)) · C \(Int(meal.carbsG)) · F \(Int(meal.fatG))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(meal.calories))")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                        Button {
                            Task { await model.delete(meal) }
                        } label: {
                            Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .cardSurface()
    }
}
