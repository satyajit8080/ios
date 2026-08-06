import PhotosUI
import SwiftUI
import UIKit

/// A vision result the user can edit before it's committed to their diary.
///
/// The AI returns estimates from a photo, and estimates are wrong often enough that
/// saving them unedited would quietly corrupt the calorie history the coach later
/// reasons over. Every field here is mutable for that reason.
struct EditableFoodItem: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var quantityG: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var confidence: Double
    var include: Bool = true

    /// Original AI values, kept so the user can revert an edit.
    let original: VisionItem

    init(from item: VisionItem) {
        name = item.name
        quantityG = item.quantityG
        calories = item.calories
        proteinG = item.proteinG
        carbsG = item.carbsG
        fatG = item.fatG
        confidence = item.confidence
        original = item
    }

    var isEdited: Bool {
        abs(calories - original.calories) > 0.5
            || abs(quantityG - original.quantityG) > 0.5
            || name != original.name
            || abs(proteinG - original.proteinG) > 0.5
            || abs(carbsG - original.carbsG) > 0.5
            || abs(fatG - original.fatG) > 0.5
    }

    mutating func revert() {
        name = original.name
        quantityG = original.quantityG
        calories = original.calories
        proteinG = original.proteinG
        carbsG = original.carbsG
        fatG = original.fatG
    }

    /// Rescale nutrition proportionally when the portion size changes.
    mutating func scaleTo(grams: Double) {
        guard quantityG > 0, grams > 0 else {
            quantityG = grams
            return
        }
        let factor = grams / quantityG
        quantityG = grams
        calories *= factor
        proteinG *= factor
        carbsG *= factor
        fatG *= factor
    }
}

@MainActor
@Observable
final class ScanMealViewModel {
    var image: UIImage?
    var items: [EditableFoodItem] = []
    var notes = ""
    var hasResult = false
    var isAnalyzing = false
    var isSaving = false
    var errorMessage: String?
    var paywallMessage: String?
    var mealType = ScanMealViewModel.defaultMealType()
    var hint = ""

    var includedItems: [EditableFoodItem] { items.filter(\.include) }

    var totalCalories: Double { includedItems.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { includedItems.reduce(0) { $0 + $1.proteinG } }
    var totalCarbs: Double { includedItems.reduce(0) { $0 + $1.carbsG } }
    var totalFat: Double { includedItems.reduce(0) { $0 + $1.fatG } }

    func analyze() async {
        guard let image, let data = image.jpegData(compressionQuality: 0.72) else { return }
        isAnalyzing = true
        errorMessage = nil
        paywallMessage = nil
        defer { isAnalyzing = false }

        do {
            let result: VisionResult = try await APIClient.shared.upload(
                "vision/analyze",
                imageData: data,
                query: hint.isEmpty ? [:] : ["hint": hint]
            )
            items = result.items.map(EditableFoodItem.init)
            notes = result.notes
            hasResult = true
        } catch APIError.paymentRequired(let message) {
            paywallMessage = message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addManualItem() {
        items.append(
            EditableFoodItem(
                from: VisionItem(
                    name: "", quantityG: 100, calories: 0,
                    proteinG: 0, carbsG: 0, fatG: 0, confidence: 1
                )
            )
        )
    }

    func save() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            for item in includedItems where !item.name.trimmingCharacters(in: .whitespaces).isEmpty {
                let payload = MealLogCreate(
                    name: item.name,
                    mealType: mealType,
                    quantityG: item.quantityG,
                    calories: item.calories,
                    proteinG: item.proteinG,
                    carbsG: item.carbsG,
                    fatG: item.fatG,
                    foodId: nil,
                    source: item.isEdited ? "vision_edited" : "vision"
                )
                _ = try await APIClient.shared.postVoid("meals", body: payload)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reset() {
        image = nil
        items = []
        notes = ""
        hasResult = false
        hint = ""
    }

    static func defaultMealType() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<11: "breakfast"
        case 11..<15: "lunch"
        case 15..<21: "dinner"
        default: "snack"
        }
    }
}

/// Identifies which row the editor sheet is open on.
private struct EditTarget: Identifiable {
    let id: Int
}

struct ScanMealView: View {
    @Binding var showPaywall: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitManager.self) private var health

    @State private var model = ScanMealViewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var editTarget: EditTarget?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                photoArea

                if let message = model.paywallMessage {
                    VStack(spacing: 10) {
                        Text(message).font(.footnote).multilineTextAlignment(.center)
                        Button("See Premium") { showPaywall = true }
                            .buttonStyle(.borderedProminent).tint(Palette.pine)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Palette.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                }

                if model.isAnalyzing {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Reading the plate…").font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 24)
                }

                if model.hasResult {
                    resultsHeader
                    ForEach(model.items.indices, id: \.self) { index in
                        itemRow(index)
                    }
                    addItemButton
                    totalsCard
                    mealPicker
                    saveButton
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Scan a meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            if model.hasResult {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Retake") { model.reset() }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                model.image = image
                model.hasResult = false
                Task { await model.analyze() }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $editTarget) { target in
            if model.items.indices.contains(target.id) {
                EditFoodItemSheet(item: $model.items[target.id])
            }
        }
        .onChange(of: photoItem) {
            Task {
                guard let data = try? await photoItem?.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                model.image = image
                model.hasResult = false
                await model.analyze()
            }
        }
    }

    // MARK: - Photo

    private var photoArea: some View {
        VStack(spacing: 14) {
            if let image = model.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .frame(height: 190)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(Palette.pine)
                            Text("Photograph your plate from above")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            if !model.hasResult {
                HStack(spacing: 10) {
                    Button { showCamera = true } label: {
                        Label("Camera", systemImage: "camera").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.pine)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Library", systemImage: "photo").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)

                TextField("Optional hint, e.g. chicken thigh not breast", text: $model.hint)
                    .font(.footnote)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: - Results

    private var resultsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.items.isEmpty ? "Nothing recognised" : "Check these before saving").sectionTitle()
            Text(model.items.isEmpty
                 ? (model.notes.isEmpty ? "Try a closer, brighter shot, or add the items yourself." : model.notes)
                 : "Photo estimates are rough. Adjust the portion or tap Edit details to correct anything.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemRow(_ index: Int) -> some View {
        let item = model.items[index]

        return VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    model.items[index].include.toggle()
                } label: {
                    Image(systemName: item.include ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.include ? Palette.pine : Color(.systemGray3))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name.isEmpty ? "Untitled item" : item.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(item.name.isEmpty ? .secondary : .primary)

                    Text("\(Int(item.quantityG)) g · P \(Int(item.proteinG)) · C \(Int(item.carbsG)) · F \(Int(item.fatG))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if item.isEdited {
                        tag("Edited", Palette.pine)
                    } else if item.confidence < 0.6 {
                        tag("Low confidence", Palette.amber)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(item.calories))")
                        .font(.headline)
                        .monospacedDigit()
                    Text("kcal").font(.caption2).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Text("Portion").font(.caption).foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { model.items[index].quantityG },
                        set: { model.items[index].scaleTo(grams: $0) }
                    ),
                    in: 10...800,
                    step: 5
                )
                .tint(Palette.pine)
                Text("\(Int(item.quantityG)) g")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 50, alignment: .trailing)
            }

            HStack {
                Button("Edit details") { editTarget = EditTarget(id: index) }
                    .font(.caption.weight(.medium))
                if item.isEdited {
                    Button("Revert") { model.items[index].revert() }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    model.items.remove(at: index)
                } label: {
                    Image(systemName: "trash").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .opacity(item.include ? 1 : 0.5)
        .cardSurface()
    }

    private func tag(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private var addItemButton: some View {
        Button {
            model.addManualItem()
        } label: {
            Label("Add an item the photo missed", systemImage: "plus.circle")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.pine)
        .background(Palette.pine.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var totalsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Total").sectionTitle()
                Spacer()
                Text("\(Int(model.totalCalories)) kcal")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
            }
            MacroChips(
                protein: model.totalProtein,
                carbs: model.totalCarbs,
                fat: model.totalFat
            )
        }
        .cardSurface()
    }

    private var mealPicker: some View {
        Picker("Meal", selection: $model.mealType) {
            Text("Breakfast").tag("breakfast")
            Text("Lunch").tag("lunch")
            Text("Dinner").tag("dinner")
            Text("Snack").tag("snack")
        }
        .pickerStyle(.segmented)
    }

    private var saveButton: some View {
        Button {
            Task {
                let calories = model.totalCalories
                if await model.save() {
                    health.writeCalories(calories)
                    dismiss()
                }
            }
        } label: {
            if model.isSaving {
                ProgressView().tint(.white).frame(maxWidth: .infinity)
            } else {
                Text(model.includedItems.isEmpty
                     ? "Select at least one item"
                     : "Log \(Int(model.totalCalories)) kcal")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Palette.pine)
        .disabled(model.includedItems.isEmpty || model.isSaving)
    }
}

// MARK: - Full editor

struct EditFoodItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var item: EditableFoodItem

    private var caloriesFromMacros: Double {
        item.proteinG * 4 + item.carbsG * 4 + item.fatG * 9
    }

    private var macrosDisagree: Bool {
        item.calories > 0 && abs(caloriesFromMacros - item.calories) > max(item.calories * 0.2, 40)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $item.name)
                }

                Section("Portion") {
                    numberRow("Weight", value: $item.quantityG, suffix: "g")
                }

                Section {
                    numberRow("Calories", value: $item.calories, suffix: "kcal")
                    numberRow("Protein", value: $item.proteinG, suffix: "g")
                    numberRow("Carbs", value: $item.carbsG, suffix: "g")
                    numberRow("Fat", value: $item.fatG, suffix: "g")
                } header: {
                    Text("Nutrition")
                } footer: {
                    if macrosDisagree {
                        Text("Your macros work out to about \(Int(caloriesFromMacros)) kcal, which doesn't match the calorie figure. Worth a second look.")
                            .foregroundStyle(Palette.coral)
                    } else {
                        Text("Protein and carbs are 4 kcal per gram, fat is 9.")
                    }
                }

                if item.isEdited {
                    Section {
                        Button("Revert to the AI's estimate") { item.revert() }
                    } footer: {
                        Text("Original: \(Int(item.original.calories)) kcal, \(Int(item.original.quantityG)) g")
                    }
                }
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
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
            Text(suffix).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Camera

struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
