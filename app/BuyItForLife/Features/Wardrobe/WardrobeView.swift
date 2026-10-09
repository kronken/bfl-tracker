import SwiftUI

struct WardrobeView: View {
    var body: some View {
        TabScreen {
            ScreenHeader(title: "Wardrobe")
            PlaceholderCard(text: "Your items come here.")
        }
    }
}

#Preview {
    NavigationStack { WardrobeView() }
        .preferredColorScheme(.dark)
}
