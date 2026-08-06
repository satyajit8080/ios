//
//  DSNavigation.swift
//  AI Weight Loss Coach — Design System
//
//  Screen scaffolding and the custom tab bar. Wrapping every screen in
//  DSScreen guarantees consistent background, gutters and safe-area
//  behaviour without each view re-deriving it.
//

import SwiftUI

// MARK: - Screen scaffold

struct DSScreen<Content: View>: View {
    var title: String?
    var subtitle: String?
    /// Adds standard horizontal gutters. Turn off for edge-to-edge content
    /// like full-bleed charts or camera previews.
    var usesGutter: Bool = true
    var scrolls: Bool = true
    /// Trailing nav item.
    var trailing: AnyView?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            DS.Colors.backgroundGradient
                .ignoresSafeArea()

            if scrolls {
                ScrollView(showsIndicators: false) {
                    body(inner: true)
                }
            } else {
                body(inner: false)
            }
        }
    }

    @ViewBuilder
    private func body(inner scrolling: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            if title != nil || subtitle != nil || trailing != nil {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        if let title {
                            Text(title)
                                .dsText(DS.Typography.display)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .dsText(DS.Typography.subheadline, color: DS.Colors.textSecondary)
                        }
                    }
                    Spacer(minLength: DS.Space.sm)
                    if let trailing {
                        trailing
                    }
                }
                .padding(.horizontal, usesGutter ? 0 : DS.Space.gutter)
                .padding(.top, DS.Space.sm)
            }

            content()
        }
        .padding(.horizontal, usesGutter ? DS.Space.gutter : 0)
        .padding(.bottom, DS.Space.xxxl + 40) // clears the tab bar
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tab bar

struct DSTab: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let selectedIcon: String

    init(id: String, title: String, icon: String, selectedIcon: String? = nil) {
        self.id = id
        self.title = title
        self.icon = icon
        self.selectedIcon = selectedIcon ?? icon + ".fill"
    }

    static let today = DSTab(id: "today", title: "Today", icon: "house")
    static let progress = DSTab(id: "progress", title: "Progress", icon: "chart.line.uptrend.xyaxis", selectedIcon: "chart.line.uptrend.xyaxis")
    static let scan = DSTab(id: "scan", title: "Scan", icon: "camera.viewfinder", selectedIcon: "camera.viewfinder")
    static let coach = DSTab(id: "coach", title: "Coach", icon: "sparkles", selectedIcon: "sparkles")
    static let profile = DSTab(id: "profile", title: "Profile", icon: "person", selectedIcon: "person.fill")
}

/// Floating glass tab bar with a centre action button.
struct DSTabBar: View {
    let tabs: [DSTab]
    @Binding var selection: String
    /// Index that renders as the raised centre button. Nil for none.
    var centerIndex: Int?

    @Namespace private var namespace

    var body: some View {
        DSGlassContainer(spacing: DS.Space.md) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    if index == centerIndex {
                        centerButton(tab)
                    } else {
                        tabButton(tab)
                    }
                }
            }
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.sm)
        // Functional layer — glass belongs here.
        .dsGlass(in: Capsule())
        .dsShadow(.high)
        .padding(.horizontal, DS.Space.xl)
    }

    private func tabButton(_ tab: DSTab) -> some View {
        let isSelected = tab.id == selection

        return Button {
            DS.Haptics.selection()
            withAnimation(DS.Motion.snappy) { selection = tab.id }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .symbolEffect(.bounce, value: isSelected)
                Text(tab.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? DS.Colors.brand : DS.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: DS.Size.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func centerButton(_ tab: DSTab) -> some View {
        Button {
            DS.Haptics.tap()
            withAnimation(DS.Motion.snappy) { selection = tab.id }
        } label: {
            Image(systemName: tab.selectedIcon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(DS.Colors.brandGradient))
                .dsGlass(in: Circle(), interactive: true)
                .dsShadow(.low)
        }
        .buttonStyle(DSPressStyle(scale: 0.92))
        .frame(maxWidth: .infinity)
        .accessibilityLabel(tab.title)
    }
}

// MARK: - Sheet handle

struct DSSheetHandle: View {
    var body: some View {
        Capsule()
            .fill(DS.Colors.border)
            .frame(width: 36, height: 5)
            .padding(.top, DS.Space.sm)
            .accessibilityHidden(true)
    }
}

// MARK: - Nav bar appearance
//
// Call once at launch so pushed UIKit-backed nav bars match the system.

extension DS {
    @MainActor
    static func applyGlobalAppearance() {
        let navBar = UINavigationBarAppearance()
        navBar.configureWithTransparentBackground()
        navBar.titleTextAttributes = [
            .foregroundColor: UIColor.label
        ]
        navBar.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar

        // The custom tab bar replaces the system one, so hide its
        // background rather than fighting its blur.
        let tabBar = UITabBarAppearance()
        tabBar.configureWithTransparentBackground()
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
    }
}

#Preview("Navigation") {
    @Previewable @State var selection = "today"

    return ZStack(alignment: .bottom) {
        DSScreen(title: "Today", subtitle: "Thursday, 6 August") {
            VStack(spacing: DS.Space.lg) {
                DSCoachCard(
                    message: "You've hit your protein goal four days running. That consistency is why the scale is moving.",
                    score: 82,
                    actionTitle: "See why",
                    action: {}
                )
                DSMetricCard(metric: .steps, value: 8420, goal: 10000, delta: 1200)
            }
        }

        DSTabBar(
            tabs: [.today, .progress, .scan, .coach, .profile],
            selection: $selection,
            centerIndex: 2
        )
        .padding(.bottom, DS.Space.sm)
    }
}
