import SwiftData
import SwiftUI

/// The app's four tabs.
struct RootView: View {
    enum TabID: String, Hashable {
        case today, insights, wardrobe, settings
    }

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(WeatherStore.self) private var weather
    @Environment(DailyInsightStore.self) private var insights
    @Query private var items: [Item]

    @State private var router = AppRouter.shared
    @State private var showOnboarding = false

    /// Debug builds can open on another tab with `-initialTab wardrobe`.
    private static var initialTab: TabID {
        #if DEBUG
        UserDefaults.standard.string(forKey: "initialTab").flatMap(TabID.init(rawValue:)) ?? .today
        #else
        .today
        #endif
    }

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Today", systemImage: "tshirt", value: .today) {
                NavigationStack { TodayView() }
            }
            Tab("Insights", systemImage: "chart.line.uptrend.xyaxis", value: .insights) {
                InsightsView()
            }
            Tab("Wardrobe", systemImage: "hanger", value: .wardrobe) {
                WardrobeView()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tint(.accentGold)
        .onAppear {
            router.tab = Self.initialTab
            showOnboarding = needsOnboarding
            Occasion.ensureBuiltIn(in: modelContext)
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            rescheduleReminder()
            // Merges a second Everyday that another device may have synced.
            Occasion.ensureBuiltIn(in: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            rescheduleReminder()
            Task { await refreshInsight() }
        }
        .task { await refreshInsight() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await refreshInsight() } }
        }
        // A pick that can no longer be shown is replaced straight away.
        .onChange(of: settings.insightFilter) { Task { await refreshInsight() } }
        .onChange(of: items.count) { Task { await refreshInsight() } }
        .onChange(of: settings.insightsEnabled) {
            // Turned off and on again: a fresh pick.
            if settings.insightsEnabled { insights.resetToday() }
            Task { await refreshInsight() }
        }
        .onChange(of: settings.onboardingCompleted) {
            // Completed on another device and synced here.
            if settings.onboardingCompleted { showOnboarding = false }
        }
        .onChange(of: router.replayOnboarding) {
            if router.replayOnboarding { showOnboarding = true }
        }
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: { router.replayOnboarding = false }) {
            OnboardingView(isReplay: router.replayOnboarding) {
                router.tab = .today
                showOnboarding = false
            }
        }
    }

    /// Today's insight: the stored one, or a new pick on the first open of the
    /// day. Waits for the forecast first, so weather insights can be timely.
    private func refreshInsight() async {
        guard settings.insightsEnabled else { return }
        await weather.refreshToday(locationSetting: settings.weatherLocation)
        let makeContext = { InsightContext.make(context: modelContext, settings: settings, weather: weather) }
        #if DEBUG
        if let rule = UserDefaults.standard.string(forKey: "debugInsight") {
            insights.showForDebugging(ruleId: rule, context: makeContext())
            return
        }
        #endif
        let ids = Set(items.map(\.id))
        insights.refresh(filter: settings.insightFilter, itemExists: { ids.contains($0) }, makeContext: makeContext)
    }

    private func rescheduleReminder() {
        Task { await Reminders.reschedule(settings: settings, context: modelContext) }
    }

    /// First launch: onboarding not completed and nothing in the wardrobe, so
    /// a reinstall with iCloud data goes straight to the app.
    private var needsOnboarding: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "forceOnboarding") { return true }
        #endif
        return !settings.onboardingCompleted && items.isEmpty
    }
}

#Preview {
    RootView()
        .environment(AppSettings())
        .environment(DailyInsightStore())
        .environment(WeatherStore())
        .modelContainer(for: [Item.self, DayLog.self], inMemory: true)
        .preferredColorScheme(.dark)
}
