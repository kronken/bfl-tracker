import SwiftData
import SwiftUI

@main
struct BuyItForLifeApp: App {
    @State private var settings = AppSettings()
    private let container = Self.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }

    /// The SwiftData store, synced to the user's private iCloud database.
    static func makeContainer() -> ModelContainer {
        #if DEBUG
        if DemoData.isEnabled { return DemoData.makeContainer() }
        #endif
        let schema = Schema([Item.self, DayLog.self])
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
