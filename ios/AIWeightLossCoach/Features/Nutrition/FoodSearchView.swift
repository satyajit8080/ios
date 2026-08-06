import SwiftUI

@MainActor
@Observable
final class FoodSearchViewModel {
    var query = ""
    var results: [Food] = []
    var favorites: [Food] = []
    var isSearching = false
    var errorMessage: String?

    private let api = APIClient.shared
    private var searchTask: Task<Void, Never>?

    func loadFavorites() async {
        favorites = (try? await api.get("foods/favorites")) ?? []
    }

    func search() {
        searchTask?.cancel()
        let term = query.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                results = try await api.get("foods/search", query: ["q": term])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleFavorite(_ food: Food) async {
        if favorites.contains(where: { $0.id == food.id }) {
            _ = try? await api.delete("foods/\(food.id.uuidString)/favorite")
        } else {
            _ = try? await api.postVoid("foods/\(food.id.uuidString)/favorite")
        }
        await loadFavorites()
    }
}

struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let onLogged: () async -> Void

    @State private var model = FoodSearchViewModel()
    @State private var selected: Food?

    var body: some View {
        NavigationStack {
            List {
                if model.query.isEmpty && !model.favorites.isEmpty {
                    Section("Favourites") {
                        ForEach(model.favorites) { food in row(food) }
                    }
                }
                if !model.results.isEmpty {
                    Section("Results") {
                        ForEach(model.results) { food in row(food) }
                    }
                }
                if model.query.count >= 2 && model.results.isEmpty && !model.isSearching {
                    Section {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: "No matches",
                            message: "Try a simpler term, or add it as a custom food.",
                            actionTitle: "Add custom food",
                            action: { selected = customPlaceholder }
                        )
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .searchable(text: $model.query, prompt: "Search foods")
            .onChange(of: model.query) { model.search() }
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Custom") { selected = customPlaceholder }
                }
            }
            .task { await model.loadFavorites() }
            .sheet(item: $selected) { food in
                LogFoodSheet(food: food) {
                    await onLogged()
                    dismiss()
                }
            }
        }
    }

    private var customPlaceholder: Food {
        Food(
            id: UUID(), name: model.query.isEmpty ? "" : model.query, brand: nil,
            servingLabel: "100 g", servingGrams: 100, calories: 0,
            proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, sugarG: 0
        )
    }

    private func row(_ food: Food) -> some View {
        Button { selected = food } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name).font(.subheadline)
                    Text("\(food.servingLabel) · \(Int(food.calories)) kcal · P \(Int(food.proteinG))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.toggleFavorite(food) }
                } label: {
                    Image(systemName: model.favorites.contains(where: { $0.id == food.id }) ? "star.fill" : "star")
                        .foregroundStyle(Palette.amber)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
    }
}

struct LogFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitManager.self) private var health

    let food: Food
    let onLogged: () async -> Void

    @State private var name: String
    @State private var servings: Double = 1
    @State private var mealType = defaultMealType()
    @State private var caloriesPerServing: Double
    @State private var proteinPerServing: Double
    @State private var carbsPerServing: Double
    @State private var fatPerServing: Double
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var isCustom: Bool { food.calories == 0 }

    init(food: Food, onLogged: @escaping () async -> Void) {
        self.food = food
        self.onLogged = onLogged
        _name = State(initialValue: food.name)
        _caloriesPerServing = State(initialValue: food.calories)
        _proteinPerServing = State(initialValue: food.proteinG)
        _carbsPerServing = State(initialValue: food.carbsG)
        _fatPerServing = State(initialValue: food.fatG)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Meal", selection: $mealType) {
                        Text("Breakfast").tag("breakfast")
                        Text("Lunch").tag("lunch")
                        Text("Dinner").tag("dinner")
                        Text("Snack").tag("snack")
                    }
                    HStack {
                        Text("Servings")
                        Spacer()
                        Text(String(format: "%.2g", servings)).monospacedDigit()
                    }
                    Slider(value: $servings, in: 0.25...6, step: 0.25).tint(Palette.pine)
                    if !isCustom {
                        Text("One serving is \(food.servingLabel).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Per serving") {
                    numberRow("Calories", value: $caloriesPerServing, suffix: "kcal")
                    numberRow("Protein", value: $proteinPerServing, suffix: "g")
                    numberRow("Carbs", value: $carbsPerServing, suffix: "g")
                    numberRow("Fat", value: $fatPerServing, suffix: "g")
                }

                Section("Total") {
                    HStack {
                        Text("\(Int(caloriesPerServing * servings)) kcal")
                            .font(.headline).monospacedDigit()
                        Spacer()
                        Text("P \(Int(proteinPerServing * servings)) · C \(Int(carbsPerServing * servings)) · F \(Int(fatPerServing * servings))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section { ErrorBanner(message: errorMessage) }
                }
            }
            .navigationTitle(isCustom ? "Custom food" : "Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { Task { await save() } }
                        .disabled(name.isEmpty || caloriesPerServing <= 0 || isSaving)
                }
            }
        }
    }

    private func numberRow(_ label: String, value: Binding<Double>, suffix: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(suffix).foregroundStyle(.secondary).font(.caption)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let payload = MealLogCreate(
            name: name,
            mealType: mealType,
            quantityG: food.servingGrams * servings,
            calories: caloriesPerServing * servings,
            proteinG: proteinPerServing * servings,
            carbsG: carbsPerServing * servings,
            fatG: fatPerServing * servings,
            foodId: isCustom ? nil : food.id,
            source: isCustom ? "manual" : "search"
        )
        do {
            _ = try await APIClient.shared.postVoid("meals", body: payload)
            health.writeCalories(payload.calories)
            await onLogged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func defaultMealType() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<11: "breakfast"
        case 11..<15: "lunch"
        case 15..<21: "dinner"
        default: "snack"
        }
    }
}
