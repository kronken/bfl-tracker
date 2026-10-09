import SwiftUI

/// The app's four tabs.
struct RootView: View {
    enum TabID: Hashable {
        case today, insights, wardrobe, settings
    }

    @State private var selection: TabID = .today

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "tshirt", value: .today) {
                NavigationStack { TodayView() }
            }
            Tab("Insights", systemImage: "chart.line.uptrend.xyaxis", value: .insights) {
                NavigationStack { InsightsView() }
            }
            Tab("Wardrobe", systemImage: "hanger", value: .wardrobe) {
                NavigationStack { WardrobeView() }
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
