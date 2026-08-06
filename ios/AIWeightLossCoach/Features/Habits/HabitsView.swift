import SwiftUI

@MainActor
@Observable
final class HabitsViewModel {
    var habits: [HabitWithStats] = []
    var gamification: Gamification?
    var isLoading = false
    var errorMessage: String?

    private let api = APIClient.shared

    func load() async {
        isLoading = habits.isEmpty
        defer { isLoading = false }
        do {
            async let list: [HabitWithStats] = api.get("habits")
            async let game: Gamification = api.get("gamification")
            habits = try await list
            gamification = try await game
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ item: HabitWithStats) async {
        let next = item.doneToday >= item.habit.targetPerDay ? 0 : item.doneToday + 1
        do {
            let updated: HabitWithStats = try await api.post(
                "habits/\(item.habit.id.uuidString)/log", body: ["count": next]
            )
            if let index = habits.firstIndex(where: { $0.id == updated.id }) {
                habits[index] = updated
            }
            gamification = try? await api.get("gamification")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(name: String, icon: String, target: Int) async {
        let body: [String: AnyEncodable] = [
            "name": AnyEncodable(name),
            "icon": AnyEncodable(icon),
            "target_per_day": AnyEncodable(target)
        ]
        _ = try? await api.postVoid("habits", body: body)
        await load()
    }

    func archive(_ item: HabitWithStats) async {
        _ = try? await api.delete("habits/\(item.habit.id.uuidString)")
        await load()
    }
}

struct HabitsView: View {
    @State private var model = HabitsViewModel()
    @State private var showNew = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                }
                if let game = model.gamification {
                    levelCard(game)
                }
                if model.habits.isEmpty && !model.isLoading {
                    EmptyStateView(
                        systemImage: "checkmark.seal",
                        title: "No habits yet",
                        message: "Pick one or two small things you can do most days. Streaks build from there.",
                        actionTitle: "Add a habit",
                        action: { showNew = true }
                    )
                } else {
                    ForEach(model.habits) { item in habitRow(item) }
                }
                if let game = model.gamification, !game.badges.isEmpty || !game.lockedBadges.isEmpty {
                    badgeCard(game)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button { showNew = true } label: {
                Label("New habit", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(16)
            .background(.bar)
        }
        .task { await model.load() }
        .sheet(isPresented: $showNew) {
            NewHabitSheet { name, icon, target in
                await model.create(name: name, icon: icon, target: target)
            }
        }
    }

    private func levelCard(_ game: Gamification) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Level \(game.level)").font(.title3.weight(.bold))
                    Text("\(Units.count(game.xp)) XP earned").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(game.xpForNextLevel - game.xpIntoLevel) XP to level \(game.level + 1)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            ProgressBar(
                value: Double(game.xpIntoLevel) / Double(max(game.xpForNextLevel, 1)),
                tint: Palette.amber
            )
        }
        .cardSurface()
    }

    private func habitRow(_ item: HabitWithStats) -> some View {
        HStack(spacing: 14) {
            Button {
                Task { await model.toggle(item) }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(adaptiveHex: item.habit.color).opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: item.doneToday >= item.habit.targetPerDay ? "checkmark" : item.habit.icon)
                        .font(.headline)
                        .foregroundStyle(Color(adaptiveHex: item.habit.color))
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.habit.name).font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    if item.currentStreak > 0 {
                        Label("\(item.currentStreak)", systemImage: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(Palette.amber)
                    }
                    Text("Best \(item.longestStreak)").font(.caption2).foregroundStyle(.secondary)
                    if item.habit.targetPerDay > 1 {
                        Text("\(item.doneToday)/\(item.habit.targetPerDay) today")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            weekDots(item)
        }
        .cardSurface()
        .contextMenu {
            Button("Archive", role: .destructive) { Task { await model.archive(item) } }
        }
    }

    private func weekDots(_ item: HabitWithStats) -> some View {
        let days = (0..<7).compactMap {
            Calendar.current.date(byAdding: .day, value: -$0, to: Date())
        }.reversed()
        return HStack(spacing: 4) {
            ForEach(Array(days), id: \.self) { day in
                Circle()
                    .fill(
                        item.last30Days.contains(where: { Calendar.current.isDate($0, inSameDayAs: day) })
                        ? Color(adaptiveHex: item.habit.color)
                        : Color(.systemGray5)
                    )
                    .frame(width: 7, height: 7)
            }
        }
    }

    private func badgeCard(_ game: Gamification) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Badges").sectionTitle()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                ForEach(game.badges) { earned in
                    badge(earned.badge, unlocked: true)
                }
                ForEach(game.lockedBadges) { locked in
                    badge(locked, unlocked: false)
                }
            }
        }
        .cardSurface()
    }

    private func badge(_ badge: Badge, unlocked: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: badge.icon)
                .font(.title3)
                .foregroundStyle(unlocked ? Palette.amber : Color(.systemGray3))
                .frame(width: 46, height: 46)
                .background(
                    Circle().fill(unlocked ? Palette.amber.opacity(0.14) : Color(.tertiarySystemGroupedBackground))
                )
            Text(badge.name)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(unlocked ? .primary : .secondary)
                .lineLimit(2)
        }
    }
}

struct NewHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, String, Int) async -> Void

    @State private var name = ""
    @State private var icon = "checkmark.seal"
    @State private var target = 1

    private let icons = [
        "checkmark.seal", "drop.fill", "figure.walk", "fork.knife", "bed.double.fill",
        "leaf.fill", "dumbbell.fill", "moon.stars.fill", "nosign", "book.fill"
    ]

    private let suggestions = [
        "No added sugar", "10 minute walk after dinner", "Protein at breakfast",
        "Lights out by 11", "Vegetables at two meals", "No snacking after 9pm"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    TextField("What will you do?", text: $name)
                    Stepper("Times a day: \(target)", value: $target, in: 1...12)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(icons, id: \.self) { candidate in
                            Button { icon = candidate } label: {
                                Image(systemName: candidate)
                                    .font(.headline)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle().fill(
                                            icon == candidate ? Palette.pine.opacity(0.18) : Color(.tertiarySystemGroupedBackground)
                                        )
                                    )
                                    .foregroundStyle(icon == candidate ? Palette.pine : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Ideas") {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { name = suggestion }
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("New habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await onCreate(name, icon, target)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
