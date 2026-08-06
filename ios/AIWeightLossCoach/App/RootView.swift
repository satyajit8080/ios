import SwiftUI
 
struct RootView: View {
    @Environment(SessionStore.self) private var session
 
    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                LaunchView()
            case .signedOut:
                AuthView()
            case .onboarding:
                OnboardingView()
            case .signedIn:
                MainTabView()
            }
        }
        .dsAnimation(DS.Motion.standard, value: session.phase)
    }
}
 
// MARK: - Launch
 
struct LaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
 
    var body: some View {
        ZStack {
            DS.Colors.brandGradient
                .ignoresSafeArea()
 
            VStack(spacing: DS.Space.xl) {
                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.white)
                    .scaleEffect(pulse ? 1.06 : 0.94)
                    .opacity(pulse ? 1 : 0.7)
 
                ProgressView()
                    .tint(.white)
            }
            .accessibilityElement()
            .accessibilityLabel("Loading")
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
 
// MARK: - Main tabs
 
struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(HealthKitManager.self) private var health
    @Environment(PushManager.self) private var push
    @Environment(\.scenePhase) private var scenePhase
 
    @State private var selection = Tab.today.rawValue
    @State private var showPaywall = false
    @State private var showScan = false
 
    private enum Tab: String {
        case today, food, scan, coach, progress, you
    }
 
    // Six slots: five destinations plus the raised scan action. The scan
    // button presents a sheet rather than switching tabs, so it never
    // becomes a place you can get stuck.
    private let tabs: [DSTab] = [
        DSTab(id: Tab.today.rawValue, title: "Today", icon: "square.grid.2x2", selectedIcon: "square.grid.2x2.fill"),
        DSTab(id: Tab.food.rawValue, title: "Food", icon: "fork.knife", selectedIcon: "fork.knife"),
        DSTab(id: Tab.scan.rawValue, title: "Scan", icon: "camera.viewfinder", selectedIcon: "camera.viewfinder"),
        DSTab(id: Tab.coach.rawValue, title: "Coach", icon: "sparkles", selectedIcon: "sparkles"),
        DSTab(id: Tab.progress.rawValue, title: "Progress", icon: "chart.xyaxis.line", selectedIcon: "chart.xyaxis.line"),
        DSTab(id: Tab.you.rawValue, title: "You", icon: "person", selectedIcon: "person.fill")
    ]
 
    var body: some View {
        ZStack(alignment: .bottom) {
            DS.Colors.backgroundGradient
                .ignoresSafeArea()
 
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
 
            DSTabBar(tabs: tabs, selection: $selection, centerIndex: 2)
                .padding(.bottom, DS.Space.sm)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showScan) { ScanMealView() }
        .onChange(of: selection) { _, new in
            // The centre button is an action, not a destination.
            guard new == Tab.scan.rawValue else { return }
            showScan = true
            selection = Tab.today.rawValue
        }
        .task {
            if health.status == .notRequested { await health.requestAuthorization() }
            await health.syncAll()
            health.startBackgroundSync()
            if !push.isAuthorized { await push.requestAuthorization() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Health samples can land while the app is backgrounded; pick
            // them up on return.
            if phase == .active {
                Task { await health.syncAll() }
            }
        }
    }
 
    @ViewBuilder
    private var content: some View {
        switch Tab(rawValue: selection) ?? .today {
        case .today, .scan:
            DashboardView(showPaywall: $showPaywall)
        case .food:
            FoodLogView(showPaywall: $showPaywall)
        case .coach:
            CoachView(showPaywall: $showPaywall)
        case .progress:
            ProgressHubView()
        case .you:
            SettingsView(showPaywall: $showPaywall)
        }
    }
}
 
// MARK: - Progress hub
 
struct ProgressHubView: View {
    enum Section: String, CaseIterable, Identifiable {
        case weight = "Weight"
        case forecast = "Forecast"
        case steps = "Steps"
        case water = "Water"
        case habits = "Habits"
        case trends = "Trends"
        var id: String { rawValue }
    }
 
    @State private var section: Section = .weight
 
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.sm) {
                        ForEach(Section.allCases) { item in
                            DSChip(title: item.rawValue, isSelected: section == item) {
                                withAnimation(DS.Motion.snappy) { section = item }
                            }
                        }
                    }
                    .padding(.horizontal, DS.Space.gutter)
                    .padding(.vertical, DS.Space.xs)
                }
                .padding(.bottom, DS.Space.sm)
 
                switch section {
                case .weight: WeightView()
                case .forecast: PredictionView()
                case .steps: StepsView()
                case .water: WaterView()
                case .habits: HabitsView()
                case .trends: AnalyticsView()
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .background(DS.Colors.background)
        }
    }
}
