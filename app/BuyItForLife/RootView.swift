import SwiftUI

/// The app's four tabs.
struct RootView: View {
    enum TabID: String, Hashable {
        case today, insights, wardrobe, settings
    }

    @State private var selection: TabID = Self.initialTab

    /// Debug builds can open on another tab with `-initialTab wardrobe`.
    private static var initialTab: TabID {
        #if DEBUG
        UserDefaults.standard.string(forKey: "initialTab").flatMap(TabID.init(rawValue:)) ?? .today
        #else
        .today
        #endif
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "tshirt", value: .today) {
                NavigationStack { TodayView() }
            }
            Tab("Insights", systemImage: "chart.line.uptrend.xyaxis", value: .insights) {
                NavigationStack { InsightsView() }
            }
            Tab("Wardrobe", systemImage: "hanger", value: .wardrobe) {
                WardrobeView()
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tint(.accentGold)
    }
}

#Preview {
    RootView()
        .environment(AppSettings())
        .preferredColorScheme(.dark)
}
