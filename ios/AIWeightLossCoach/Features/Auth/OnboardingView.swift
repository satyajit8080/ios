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
 
    private let stepCount = 4
 
    private let activities: [(String, String)] = [
        ("sedentary", "Mostly sitting"),
        ("light", "Light activity"),
        ("moderate", "Moderately active"),
        ("active", "Very active"),
        ("athlete", "Athlete")
    ]
 
    // MARK: Safety
    //
    // A goal weight below a BMI of 18.5 is clinically underweight. The app
    // must not present that as a target it will coach someone toward. This
    // is a soft gate: it warns and blocks advancing, and points at a
    // clinician rather than silently clamping the number, which would be
    // confusing and easy to work around.
 
    private var goalBMI: Double {
        let metres = heightCm / 100
        guard metres > 0 else { return 0 }
        return goalWeight / (metres * metres)
    }
 
    private var goalIsUnderweight: Bool { goalBMI < 18.5 }
 
    private var canAdvance: Bool {
        if step == 2 { return !goalIsUnderweight }
        return true
    }
 
    var body: some View {
        ZStack {
            DS.Colors.backgroundGradient.ignoresSafeArea()
 
            VStack(spacing: 0) {
                progressHeader
 
                TabView(selection: $step) {
                    aboutYou.tag(0)
                    measurements.tag(1)
                    goals.tag(2)
                    permissions.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
 
                footer
            }
        }
    }
 
    // MARK: Progress
 
    private var progressHeader: some View {
        VStack(spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.xs) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? DS.Colors.brand : DS.Colors.separator)
                        .frame(height: 5)
                }
            }
            .dsAnimation(DS.Motion.standard, value: step)
 
            Text("Step \(step + 1) of \(stepCount)")
                .dsOverline()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.top, DS.Space.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step + 1) of \(stepCount)")
    }
 
    // MARK: Steps
 
    private var aboutYou: some View {
        stepScaffold(
            title: "A little about you",
            subtitle: "This sets your starting calorie and activity targets. You can change any of it later."
        ) {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Gender").dsOverline()
                DSSegmentedControl(
                    options: [
                        ("female", "Female"),
                        ("male", "Male"),
                        ("unspecified", "Prefer not to say")
                    ],
                    selection: $gender
                )
            }
 
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Date of birth").dsOverline()
                DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(DS.Colors.brand)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
 
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Daily activity").dsOverline()
                VStack(spacing: DS.Space.sm) {
                    ForEach(activities, id: \.0) { value, label in
                        activityRow(value: value, label: label)
                    }
                }
            }
        }
    }
 
    private func activityRow(value: String, label: String) -> some View {
        let isSelected = activity == value
 
        return Button {
            DS.Haptics.selection()
            withAnimation(DS.Motion.snappy) { activity = value }
        } label: {
            HStack {
                Text(label)
                    .dsText(DS.Typography.body, color: isSelected ? DS.Colors.brand : DS.Colors.textPrimary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: DS.Size.iconMd))
                    .foregroundStyle(isSelected ? DS.Colors.brand : DS.Colors.border)
            }
            .padding(.horizontal, DS.Space.lg)
            .frame(height: DS.Size.minTapTarget + 4)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(isSelected ? DS.Colors.brandSoft : DS.Colors.surfaceSunken)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressStyle(scale: 0.99))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
 
    private var measurements: some View {
        stepScaffold(
            title: "Your measurements",
            subtitle: "Used for BMI and to work out how much energy your body uses at rest."
        ) {
            DSSliderRow(
                label: "Height",
                value: $heightCm,
                range: 130...215,
                step: 1,
                display: "\(Int(heightCm)) cm"
            )
 
            DSSliderRow(
                label: "Current weight",
                value: $currentWeight,
                range: 35...250,
                step: 0.5,
                display: String(format: "%.1f kg", currentWeight)
            )
 
            if health.status == .authorized {
                DSSecondaryButton(title: "Use my latest Health weight", icon: "heart.text.square") {
                    Task {
                        if let value = await health.latestBodyMassKg() {
                            withAnimation(DS.Motion.standard) { currentWeight = value }
                            DS.Haptics.success()
                        }
                    }
                }
            }
        }
    }
 
    private var goals: some View {
        stepScaffold(
            title: "Where you're headed",
            subtitle: "A steady 0.25–0.5 kg a week is the range most people can hold onto."
        ) {
            DSSliderRow(
                label: "Goal weight",
                value: $goalWeight,
                range: 35...250,
                step: 0.5,
                display: String(format: "%.1f kg", goalWeight)
            )
 
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text("Weekly pace").dsOverline()
                DSSegmentedControl(
                    options: [
                        (0.25, "Gentle"),
                        (0.5, "Steady"),
                        (0.75, "Brisk")
                    ],
                    selection: $weeklyGoal
                )
                Text(paceDetail)
                    .dsText(DS.Typography.footnote, color: DS.Colors.textTertiary)
            }
 
            if goalIsUnderweight {
                DSBanner(
                    kind: .warning,
                    message: "A goal of \(String(format: "%.1f", goalWeight)) kg puts your BMI at \(String(format: "%.1f", goalBMI)), which is below the healthy range. Pick a higher goal, or talk to a doctor or dietitian about the right target for you."
                )
            } else if goalWeight < currentWeight {
                let weeks = Int(((currentWeight - goalWeight) / weeklyGoal).rounded())
                DSBanner(
                    kind: .info,
                    message: "At this pace you'd reach \(String(format: "%.1f", goalWeight)) kg in about \(weeks) weeks."
                )
            }
        }
    }
 
    private var paceDetail: String {
        switch weeklyGoal {
        case 0.25: return "0.25 kg a week — easiest to sustain alongside normal life."
        case 0.75: return "0.75 kg a week — a large deficit, and harder to hold."
        default: return "0.5 kg a week — the pace most people stick with."
        }
    }
 
    private var permissions: some View {
        stepScaffold(
            title: "Connect Health",
            subtitle: "Steps and workouts sync automatically so your streaks stay honest without extra tapping."
        ) {
            permissionRow(
                icon: "heart.text.square",
                title: "Apple Health",
                detail: health.status == .authorized
                    ? "Connected"
                    : "Reads steps, distance and weight"
            ) {
                Task { await health.requestAuthorization() }
            }
 
            Text("You can skip this and connect later from Settings.")
                .dsText(DS.Typography.footnote, color: DS.Colors.textTertiary)
        }
    }
 
    private func permissionRow(
        icon: String, title: String, detail: String, action: @escaping () -> Void
    ) -> some View {
        let isConnected = health.status == .authorized
 
        return HStack(spacing: DS.Space.md) {
            Image(systemName: icon)
                .font(.system(size: DS.Size.iconMd, weight: .medium))
                .foregroundStyle(DS.Colors.brand)
                .frame(width: 44, height: 44)
                .background(DS.Colors.brandSoft, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
 
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title).dsText(DS.Typography.headline)
                Text(detail).dsText(DS.Typography.caption, color: DS.Colors.textSecondary)
            }
 
            Spacer(minLength: DS.Space.sm)
 
            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: DS.Size.iconMd))
                    .foregroundStyle(DS.Colors.success)
                    .accessibilityLabel("Connected")
            } else {
                DSSecondaryButton(title: "Allow", fullWidth: false, action: action)
            }
        }
        .accessibilityElement(children: .combine)
    }
 
    // MARK: Footer
 
    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            if step > 0 {
                DSSecondaryButton(title: "Back", fullWidth: false) {
                    withAnimation(DS.Motion.standard) { step -= 1 }
                }
            }
 
            DSPrimaryButton(
                title: step == stepCount - 1 ? "Start tracking" : "Continue",
                isLoading: session.isWorking,
                isEnabled: canAdvance
            ) {
                if step < stepCount - 1 {
                    withAnimation(DS.Motion.standard) { step += 1 }
                } else {
                    Task { await save() }
                }
            }
        }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.top, DS.Space.md)
        .padding(.bottom, DS.Space.lg)
    }
 
    // MARK: Save
    //
    // Unchanged from the original — same fields, same endpoints.
 
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
        DS.Haptics.milestone()
        session.completeOnboarding()
    }
 
    // MARK: Scaffold
 
    @ViewBuilder
    private func stepScaffold<Content: View>(
        title: String, subtitle: String, @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text(title)
                        .dsText(DS.Typography.title1)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .dsText(DS.Typography.subheadline, color: DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, DS.Space.xl)
 
                DSCard {
                    VStack(alignment: .leading, spacing: DS.Space.xl) {
                        content()
                    }
                }
            }
            .padding(.horizontal, DS.Space.gutter)
            .padding(.bottom, DS.Space.xl)
        }
    }
}
