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
        .animation(.easeInOut(duration: 0.25), value: session.phase)
    }
}

struct LaunchView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.pineDeep, Palette.pine],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "figure.walk.motion")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white)
                ProgressView().tint(.white)
            }
            .accessibilityLabel("Loading")
        }
    }
}

struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(HealthKitManager.self) private var health
    @Environment(PushManager.self) private var push
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = 0
    @State private var showPaywall = false

    var body: some View {
        TabView(selection: $selection) {
            DashboardView(showPaywall: $showPaywall)
                .tabItem { Label("Today", systemImage: "square.grid.2x2") }
                .tag(0)

            FoodLogView(showPaywall: $showPaywall)
                .tabItem { Label("Food", systemImage: "fork.knife") }
                .tag(1)

            CoachView(showPaywall: $showPaywall)
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(2)

            ProgressHubView()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                .tag(3)

            SettingsView(showPaywall: $showPaywall)
                .tabItem { Label("You", systemImage: "person.crop.circle") }
                .tag(4)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .task {
            if health.status == .notRequested { await health.requestAuthorization() }
            await health.syncAll()
            health.startBackgroundSync()
            if !push.isAuthorized { await push.requestAuthorization() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Health samples can land while the app is backgrounded; pick them up on return.
            if phase == .active {
                Task { await health.syncAll() }
            }
        }
    }
}

struct ProgressHubView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case weight = "Weight"
        case forecast = "Forecast"
        case steps = "Steps"
        case water = "Water"
        case habits = "Habits"
        case trends = "Trends"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .weight

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Tab.allCases) { item in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { tab = item }
                            } label: {
                                Text(item.rawValue)
                                    .font(.subheadline.weight(tab == item ? .semibold : .regular))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule().fill(
                                            tab == item ? Palette.pine : Color(.secondarySystemGroupedBackground)
                                        )
                                    )
                                    .foregroundStyle(tab == item ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 10)

                switch tab {
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
            .background(Color(.systemGroupedBackground))
        }
    }
}
