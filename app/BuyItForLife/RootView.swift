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
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { rescheduleReminder() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            rescheduleReminder()
        }
        .onChange(of: settings.onboardingCompleted) {
            // Completed on another device and synced here.
            if settings.onboardingCompleted { showOnboarding = false }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                router.tab = .today
                showOnboarding = false
            }
        }
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
        .environment(WeatherStore())
        .modelContainer(for: [Item.self, DayLog.self], inMemory: true)
        .preferredColorScheme(.dark)
}
