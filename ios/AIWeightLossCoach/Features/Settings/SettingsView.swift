import SwiftUI

struct SettingsView: View {
    @Binding var showPaywall: Bool
    @Environment(SessionStore.self) private var session
    @Environment(HealthKitManager.self) private var health
    @Environment(PushManager.self) private var push
    @Environment(StoreManager.self) private var store

    @State private var showProfile = false
    @State private var showReminders = false
    @State private var showDeleteConfirm = false
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                premiumSection
                goalsSection
                connectionsSection
                moreSection
                dangerSection
            }
            .navigationTitle("You")
            .sheet(isPresented: $showProfile) { ProfileEditView() }
            .sheet(isPresented: $showReminders) { ReminderSettingsView() }
            .task {
                await session.refreshUser()
                await store.refreshEntitlements()
            }
        }
    }

    private var accountSection: some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Palette.pine.opacity(0.15)).frame(width: 52, height: 52)
                    Text(initials).font(.headline).foregroundStyle(Palette.pine)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.user?.fullName ?? "Your account").font(.headline)
                    Text(session.user?.email ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)

            Button("Edit profile") { showProfile = true }
        }
    }

    private var premiumSection: some View {
        Section("Subscription") {
            if session.user?.isPremium == true {
                HStack {
                    Label("Premium active", systemImage: "sparkles").foregroundStyle(Palette.amber)
                    Spacer()
                    if let until = session.user?.premiumExpiresAt {
                        Text(until.formatted(.dateTime.day().month().year()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Link("Manage subscription", destination: AppConfig.manageSubscriptionsURL)
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        Label("Upgrade to Premium", systemImage: "sparkles")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Restore purchases") {
                    Task {
                        await store.restore()
                        await session.refreshUser()
                    }
                }
                .font(.subheadline)
            }
        }
    }

    private var goalsSection: some View {
        Section {
            targetRow("Daily calories", "\(session.user?.dailyCalorieTarget ?? 0) kcal")
            targetRow("Protein", "\(session.user?.dailyProteinTargetG ?? 0) g")
            targetRow("Water", Units.litres(session.user?.dailyWaterMlTarget ?? 0))
            targetRow("Steps", Units.count(session.user?.dailyStepTarget ?? 0))
        } header: {
            Text("Your targets")
        } footer: {
            Text("Targets recalculate from your weight, height, age and pace whenever you update your profile. Calories never drop below a clinically safe floor.")
        }
    }

    private func targetRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var connectionsSection: some View {
        Section("Connections") {
            HStack {
                Label("Apple Health", systemImage: "heart.text.square")
                Spacer()
                switch health.status {
                case .authorized:
                    Text("Connected").font(.caption).foregroundStyle(Palette.pine)
                case .denied:
                    Button("Open Settings") { AppConfig.openSystemSettings() }.font(.caption)
                case .unavailable:
                    Text("Unavailable").font(.caption).foregroundStyle(.secondary)
                case .notRequested:
                    Button("Connect") { Task { await health.requestAuthorization() } }.font(.caption)
                }
            }
            HStack {
                Label("Notifications", systemImage: "bell")
                Spacer()
                if push.isAuthorized {
                    Text("On").font(.caption).foregroundStyle(Palette.pine)
                } else {
                    Button("Enable") { Task { await push.requestAuthorization() } }.font(.caption)
                }
            }
            Button("Reminder schedule") { showReminders = true }
        }
    }

    private var moreSection: some View {
        Section("More") {
            NavigationLink { CheckInView() } label: {
                Label("Daily check-in", systemImage: "checklist")
            }
            NavigationLink { PredictionView() } label: {
                Label("Weight projection", systemImage: "chart.line.downtrend.xyaxis")
            }
            NavigationLink { ChallengesView(showPaywall: $showPaywall) } label: {
                Label("Challenges", systemImage: "flag.checkered")
            }
            NavigationLink { NotificationCentreView() } label: {
                Label("Notifications", systemImage: "tray.full")
            }
            Link(destination: AppConfig.privacyURL) {
                Label("Privacy policy", systemImage: "hand.raised")
            }
            Link(destination: AppConfig.termsURL) {
                Label("Terms of use", systemImage: "doc.text")
            }
            Link(destination: AppConfig.supportURL) {
                Label("Get help", systemImage: "questionmark.circle")
            }
            HStack {
                Text("Version")
                Spacer()
                Text(AppConfig.versionString).foregroundStyle(.secondary).font(.caption).monospacedDigit()
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Sign out") { showSignOutConfirm = true }
            Button("Delete account", role: .destructive) { showDeleteConfirm = true }
        } footer: {
            Text("Deleting removes your logs, chats and subscription record from our servers. This can't be undone.")
        }
        .confirmationDialog("Sign out of this device?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await session.signOut() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete your account and all data?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) { Task { await session.deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your subscription must be cancelled separately in the App Store.")
        }
    }

    private var initials: String {
        let name = session.user?.fullName ?? session.user?.email ?? "?"
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

struct ProfileEditView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var heightCm: Double = 170
    @State private var goalWeight: Double = 70
    @State private var weeklyGoal: Double = 0.5
    @State private var activity = "moderate"
    @State private var stepTarget: Double = 10000
    @State private var isSaving = false

    private let activities: [(String, String)] = [
        ("sedentary", "Mostly sitting"),
        ("light", "Light activity"),
        ("moderate", "Moderately active"),
        ("active", "Very active"),
        ("athlete", "Athlete")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("About you") {
                    TextField("Name", text: $fullName)
                    HStack {
                        Text("Height")
                        Spacer()
                        Text("\(Int(heightCm)) cm").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $heightCm, in: 130...215, step: 1).tint(Palette.pine)
                    Picker("Activity", selection: $activity) {
                        ForEach(activities, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }

                Section {
                    HStack {
                        Text("Goal weight")
                        Spacer()
                        Text(String(format: "%.1f kg", goalWeight)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $goalWeight, in: 35...250, step: 0.5).tint(Palette.pine)

                    Picker("Weekly pace", selection: $weeklyGoal) {
                        Text("0.25 kg").tag(0.25)
                        Text("0.5 kg").tag(0.5)
                        Text("0.75 kg").tag(0.75)
                        Text("1.0 kg").tag(1.0)
                    }
                } header: {
                    Text("Goal")
                } footer: {
                    Text("We cap loss at 1 kg a week and never set calories below a safe floor, whatever the pace says.")
                }

                Section("Daily step goal") {
                    HStack {
                        Text("Steps")
                        Spacer()
                        Text(Units.count(Int(stepTarget))).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $stepTarget, in: 2000...25000, step: 500).tint(Palette.plum)
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(isSaving)
                }
            }
            .task { load() }
        }
    }

    private func load() {
        guard let user = session.user else { return }
        fullName = user.fullName ?? ""
        heightCm = user.heightCm ?? 170
        goalWeight = user.goalWeightKg ?? 70
        weeklyGoal = user.weeklyGoalKg
        activity = user.activityLevel
        stepTarget = Double(user.dailyStepTarget)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        await session.updateProfile([
            "full_name": AnyEncodable(fullName),
            "height_cm": AnyEncodable(heightCm),
            "goal_weight_kg": AnyEncodable(goalWeight),
            "weekly_goal_kg": AnyEncodable(weeklyGoal),
            "activity_level": AnyEncodable(activity),
            "daily_step_target": AnyEncodable(Int(stepTarget))
        ])
        dismiss()
    }
}

struct ReminderSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PushManager.self) private var push

    @State private var settings: ReminderSettings?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                if let current = settings {
                    Section("Daily nudges") {
                        Toggle("Morning weigh-in", isOn: boolBinding(\.weighInEnabled))
                        Toggle("Water pacing", isOn: boolBinding(\.waterEnabled))
                        Toggle("Log your meals", isOn: boolBinding(\.mealLogEnabled))
                        Toggle("Evening step nudge", isOn: boolBinding(\.stepNudgeEnabled))
                        Toggle("Daily AI check-in", isOn: boolBinding(\.coachCheckinEnabled))
                    }

                    Section("Weigh-in time") {
                        DatePicker(
                            "Remind me at",
                            selection: timeBinding(\.weighInTime),
                            displayedComponents: .hourAndMinute
                        )
                    }

                    Section {
                        Picker("Water reminder every", selection: intBinding(\.waterIntervalMinutes)) {
                            Text("1 hour").tag(60)
                            Text("90 minutes").tag(90)
                            Text("2 hours").tag(120)
                            Text("3 hours").tag(180)
                        }
                        DatePicker("Day starts", selection: timeBinding(\.dayStart), displayedComponents: .hourAndMinute)
                        DatePicker("Day ends", selection: timeBinding(\.dayEnd), displayedComponents: .hourAndMinute)
                    } header: {
                        Text("Waking hours")
                    } footer: {
                        Text("Nothing is sent outside these hours.")
                    }

                    if !push.isAuthorized {
                        Section {
                            Button("Turn on notifications") { Task { await push.requestAuthorization() } }
                        } footer: {
                            Text("Notifications are off for this device, so these reminders won't arrive yet.")
                        }
                    }

                    Section {
                        Button("Schedule water reminders on this device") {
                            Task {
                                await push.scheduleLocalWaterReminders(
                                    intervalMinutes: current.waterIntervalMinutes,
                                    startHour: hour(from: current.dayStart),
                                    endHour: hour(from: current.dayEnd)
                                )
                            }
                        }
                        .disabled(!current.waterEnabled || !push.isAuthorized)
                    } footer: {
                        Text("A local backup in case push notifications don't get through.")
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                settings = try? await APIClient.shared.get("notifications/settings")
            }
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<ReminderSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings?[keyPath: keyPath] ?? false },
            set: { newValue in
                settings?[keyPath: keyPath] = newValue
                save()
            }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<ReminderSettings, Int>) -> Binding<Int> {
        Binding(
            get: { settings?[keyPath: keyPath] ?? 90 },
            set: { newValue in
                settings?[keyPath: keyPath] = newValue
                save()
            }
        )
    }

    private func timeBinding(_ keyPath: WritableKeyPath<ReminderSettings, String>) -> Binding<Date> {
        Binding(
            get: { date(from: settings?[keyPath: keyPath] ?? "08:00") },
            set: { newValue in
                settings?[keyPath: keyPath] = string(from: newValue)
                save()
            }
        )
    }

    private func save() {
        guard let payload = settings, !isSaving else { return }
        isSaving = true
        Task {
            let updated: ReminderSettings? = try? await APIClient.shared.patch("notifications/settings", body: payload)
            if let updated { settings = updated }
            isSaving = false
        }
    }

    private func hour(from raw: String) -> Int {
        Int(raw.split(separator: ":").first.map(String.init) ?? "8") ?? 8
    }

    private func date(from raw: String) -> Date {
        let parts = raw.split(separator: ":").compactMap { Int($0) }
        var components = DateComponents()
        components.hour = parts.first ?? 8
        components.minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(from: components) ?? Date()
    }

    private func string(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

struct NotificationCentreView: View {
    @State private var items: [AppNotification] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if items.isEmpty && !isLoading {
                EmptyStateView(
                    systemImage: "tray",
                    title: "Nothing here yet",
                    message: "Reminders and milestones will show up in this list.",
                    actionTitle: nil,
                    action: nil
                )
                .listRowSeparator(.hidden)
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.title).font(.subheadline.weight(item.readAt == nil ? .semibold : .regular))
                        Spacer()
                        Text(item.createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(item.body).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            items = (try? await APIClient.shared.get("notifications")) ?? []
            isLoading = false
            for item in items where item.readAt == nil {
                _ = try? await APIClient.shared.postVoid("notifications/\(item.id.uuidString)/read")
            }
        }
    }
}
