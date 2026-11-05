import SwiftData
import SwiftUI

/// Every SwiftData model, for the app, demo data and tests.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Item.self, DayLog.self, Repair.self, PieceEvent.self, Occasion.self, Brand.self,
        ClothingCategory.self, ItemType.self, CareAction.self, CareLogEntry.self,
    ]
}

@main
struct BuyItForLifeApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var settings = AppSettings()
    @State private var weather = WeatherStore()
    @State private var insights = DailyInsightStore()
    private let container = Self.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(weather)
                .environment(insights)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }

    /// The SwiftData store, synced to the user's private iCloud database.
    static func makeContainer() -> ModelContainer {
        #if DEBUG
        if DemoData.isEnabled { return DemoData.makeContainer() }
        #endif
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private("iCloud.com.joakimkronqvist.bifl")
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create the model container: \(error)")
        }
    }
}
