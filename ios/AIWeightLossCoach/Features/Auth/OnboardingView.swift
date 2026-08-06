import SwiftUI

struct OnboardingView: View {
    @Environment(SessionStore.self) private var session
    @Environment(HealthKitManager.self) private var health

    @State private var step = 0
    @State private var gender = "female"
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var heightCm: Double = 170
    @State private var currentWeight: Double = 75
    @State private var goalWeight: Double = 68
    @State private var weeklyGoal: Double = 0.5
    @State private var activity = "moderate"

    private let activities: [(String, String)] = [
        ("sedentary", "Mostly sitting"),
        ("light", "Light activity"),
        ("moderate", "Moderately active"),
        ("active", "Very active"),
        ("athlete", "Athlete")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step + 1), total: 4)
                .tint(Palette.pine)
                .padding(.horizontal)
                .padding(.top, 12)

            TabView(selection: $step) {
                aboutYou.tag(0)
                measurements.tag(1)
                goals.tag(2)
                permissions.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            footer
        }
        .background(Color(.systemGroupedBackground))
    }

    private var aboutYou: some View {
        stepScaffold(
            title: "A little about you",
            subtitle: "This sets your starting calorie and activity targets. You can change any of it later."
        ) {
            Picker("Gender", selection: $gender) {
                Text("Female").tag("female")
                Text("Male").tag("male")
                Text("Prefer not to say").tag("unspecified")
            }
            .pickerStyle(.segmented)

            DatePicker("Date of birth", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)

            VStack(alignment: .leading, spacing: 6) {
                Text("Daily activity").sectionTitle()
                Picker("Activity", selection: $activity) {
                    ForEach(activities, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var measurements: some View {
        stepScaffold(
            title: "Your measurements",
            subtitle: "Used for BMI and to work out how much energy your body uses at rest."
        ) {
            sliderRow(
                label: "Height",
                value: $heightCm,
                range: 130...215,
                step: 1,
                display: "\(Int(heightCm)) cm"
            )
            sliderRow(
                label: "Current weight",
                value: $currentWeight,
                range: 35...250,
                step: 0.5,
                display: String(format: "%.1f kg", currentWeight)
            )
            if health.status == .authorized {
                Button("Use my latest Health weight") {
                    Task {
                        if let value = await health.latestBodyMassKg() { currentWeight = value }
                    }
                }
                .font(.subheadline)
            }
        }
    }

    private var goals: some View {
        stepScaffold(
            title: "Where you're headed",
            subtitle: "A steady 0.25–0.5 kg a week is the range most people can hold onto."
        ) {
            sliderRow(
                label: "Goal weight",
                value: $goalWeight,
                range: 35...250,
                step: 0.5,
                display: String(format: "%.1f kg", goalWeight)
            )
            VStack(alignment: .leading, spacing: 6) {
                Text("Weekly pace").sectionTitle()
                Picker("Weekly pace", selection: $weeklyGoal) {
                    Text("0.25 kg — gentle").tag(0.25)
                    Text("0.5 kg — steady").tag(0.5)
                    Text("0.75 kg — brisk").tag(0.75)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            if goalWeight < currentWeight {
                let weeks = Int(((currentWeight - goalWeight) / weeklyGoal).rounded())
                Text("At this pace you'd reach \(String(format: "%.1f", goalWeight)) kg in about \(weeks) weeks.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissions: some View {
        stepScaffold(
            title: "Connect Health",
            subtitle: "Steps and workouts sync automatically so your streaks stay honest without extra tapping."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                permissionRow(
                    icon: "heart.text.square",
                    title: "Apple Health",
                    detail: health.status == .authorized ? "Connected" : "Reads steps, distance and weight"
                ) {
                    Task { await health.requestAuthorization() }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
            }
            Spacer()
            Button(step == 3 ? "Start tracking" : "Continue") {
                if step < 3 {
                    withAnimation { step += 1 }
                } else {
                    Task { await save() }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Palette.pine)
            .disabled(session.isWorking)
        }
        .padding(20)
    }

    private func save() async {
        await session.updateProfile([
            "gender": AnyEncodable(gender),
            "birth_date": AnyEncodable(DateFormatter.awlcDay.string(from: birthDate)),
            "height_cm": AnyEncodable(heightCm),
            "activity_level": AnyEncodable(activity),
            "start_weight_kg": AnyEncodable(currentWeight),
            "goal_weight_kg": AnyEncodable(goalWeight),
            "weekly_goal_kg": AnyEncodable(weeklyGoal),
            "timezone": AnyEncodable(TimeZone.current.identifier),
            "onboarded": AnyEncodable(true)
        ])

        _ = try? await APIClient.shared.postVoid(
            "weight", body: ["weight_kg": currentWeight]
        )
        health.writeWeight(currentWeight)
        session.completeOnboarding()
    }

    @ViewBuilder
    private func stepScaffold<Content: View>(
        title: String, subtitle: String, @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.title2.weight(.bold))
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 18) { content() }
                    .cardSurface()
            }
            .padding(20)
        }
    }

    private func sliderRow(
        label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).sectionTitle()
                Spacer()
                Text(display).font(.headline).monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
                .tint(Palette.pine)
        }
    }

    private func permissionRow(
        icon: String, title: String, detail: String, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Palette.pine)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Allow", action: action)
                .buttonStyle(.bordered)
                .disabled(health.status == .authorized)
        }
    }
}
