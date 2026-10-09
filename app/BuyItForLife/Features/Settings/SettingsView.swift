import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabScreen {
            ScreenHeader(title: "Settings")
            PlaceholderCard(text: "City and paid-off target come here.")
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .preferredColorScheme(.dark)
}
