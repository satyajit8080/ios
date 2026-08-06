import SwiftUI

@MainActor
@Observable
final class MealPlanViewModel {
    var plan: MealPlan?
    var isLoading = false
    var isGenerating = false
    var errorMessage: String?
    var paywallMessage: String?
    var preferences = ""
    var exclusions: Set<String> = []

    static let commonExclusions = ["Dairy", "Gluten", "Nuts", "Pork", "Shellfish", "Eggs", "Soy", "Red meat"]

    func loadCurrent() async {
        isLoading = plan == nil
        defer { isLoading = false }
        plan = try? await APIClient.shared.get("meal-plans/current")
    }

    func generate(kind: String) async {
        isGenerating = true
        errorMessage = nil
        paywallMessage = nil
        defer { isGenerating = false }

        let body: [String: AnyEncodable] = [
            "kind": AnyEncodable(kind),
            "preferences": AnyEncodable(preferences),
            "exclusions": AnyEncodable(Array(exclusions))
        ]
        do {
            plan = try await APIClient.shared.post("meal-plans", body: body)
        } catch APIError.paymentRequired(let message) {
            paywallMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MealPlanView: View {
    @Binding var showPaywall: Bool
    @State private var model = MealPlanViewModel()
    @State private var showOptions = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let message = model.paywallMessage {
                    PremiumLock(feature: "Meal planning") { showPaywall = true }
                        .overlay(alignment: .bottom) {
                            Text(message).font(.caption2).foregroundStyle(.secondary).padding(.bottom, 8)
                        }
                } else if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                }

                if model.isGenerating {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Building your plan and grocery list…")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 40)
                } else if let plan = model.plan {
                    planHeader(plan)
                    ForEach(plan.days.days) { day in dayCard(day) }
                    groceryCard(plan)
                } else if !model.isLoading {
                    EmptyStateView(
                        systemImage: "list.clipboard",
                        title: "No plan yet",
                        message: "Generate a week of meals built around your calorie and protein targets.",
                        actionTitle: "Set it up",
                        action: { showOptions = true }
                    )
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Meal plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New plan") { showOptions = true }
            }
        }
        .task { await model.loadCurrent() }
        .sheet(isPresented: $showOptions) {
            planOptions
        }
    }

    private var planOptions: some View {
        NavigationStack {
            Form {
                Section("What should we avoid?") {
                    ForEach(MealPlanViewModel.commonExclusions, id: \.self) { item in
                        Button {
                            if model.exclusions.contains(item) {
                                model.exclusions.remove(item)
                            } else {
                                model.exclusions.insert(item)
                            }
                        } label: {
                            HStack {
                                Text(item).foregroundStyle(.primary)
                                Spacer()
                                if model.exclusions.contains(item) {
                                    Image(systemName: "checkmark").foregroundStyle(Palette.pine)
                                }
                            }
                        }
                    }
                }
                Section("Anything else?") {
                    TextField("e.g. high protein, quick dinners, Mediterranean", text: $model.preferences, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Button("Generate 7-day plan") {
                        showOptions = false
                        Task { await model.generate(kind: "week") }
                    }
                    Button("Just tomorrow") {
                        showOptions = false
                        Task { await model.generate(kind: "day") }
                    }
                }
            }
            .navigationTitle("Plan options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showOptions = false } }
            }
        }
    }

    private func planHeader(_ plan: MealPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(plan.startDate.formatted(.dateTime.day().month())) – \(plan.endDate.formatted(.dateTime.day().month()))")
                .font(.headline)
            Text("Built around \(plan.calorieTarget) kcal a day.")
                .font(.caption).foregroundStyle(.secondary)
            if let notes = plan.days.notes, !notes.isEmpty {
                Text(notes).font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func dayCard(_ day: PlanDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(dayLabel(day.date)).sectionTitle()
                Spacer()
                Text("\(Int(day.totalCalories)) kcal").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            ForEach(day.meals) { meal in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        if let recipe = meal.recipe, !recipe.isEmpty {
                            Text(recipe).font(.footnote)
                        }
                        if !meal.ingredients.isEmpty {
                            Text(meal.ingredients.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button("Log this") {
                            Task {
                                let payload = MealLogCreate(
                                    name: meal.name,
                                    mealType: meal.mealType,
                                    quantityG: 0,
                                    calories: meal.calories,
                                    proteinG: meal.proteinG,
                                    carbsG: meal.carbsG,
                                    fatG: meal.fatG,
                                    foodId: nil,
                                    source: "plan"
                                )
                                _ = try? await APIClient.shared.postVoid("meals", body: payload)
                            }
                        }
                        .font(.footnote.weight(.medium))
                    }
                    .padding(.top, 6)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.name).font(.subheadline)
                            Text(meal.mealType.capitalized).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(meal.calories))").font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                }
            }
        }
        .cardSurface()
    }

    private func groceryCard(_ plan: MealPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grocery list").sectionTitle()
            ForEach(plan.groceryList.keys.sorted(), id: \.self) { category in
                if let items = plan.groceryList[category], !items.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(category.capitalized).font(.subheadline.weight(.semibold))
                        ForEach(items, id: \.self) { item in
                            Label(item, systemImage: "circle")
                                .font(.footnote)
                                .labelStyle(GroceryLabelStyle())
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .cardSurface()
    }

    private func dayLabel(_ raw: String) -> String {
        guard let date = DateFormatter.awlcDay.date(from: raw) else { return raw }
        if Calendar.current.isDateInToday(date) { return "Today" }
        return date.formatted(.dateTime.weekday(.wide).day().month())
    }
}

struct GroceryLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(.secondary)
            configuration.title
        }
    }
}
