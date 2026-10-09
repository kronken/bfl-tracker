import SwiftUI

struct InsightsView: View {
    var body: some View {
        TabScreen {
            ScreenHeader(title: "Insights")
            PlaceholderCard(text: "Wardrobe cost per day, spending and cost per wear come here.")
        }
    }
}

#Preview {
    NavigationStack { InsightsView() }
        .preferredColorScheme(.dark)
}
