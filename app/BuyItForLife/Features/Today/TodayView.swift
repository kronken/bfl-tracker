import SwiftUI

struct TodayView: View {
    var body: some View {
        TabScreen {
            ScreenHeader(
                subtitle: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                title: "Today"
            )
            SectionLabel("Suits today", trailing: "0 worn")
            PlaceholderCard(text: "Weather and today's outfit come here.")
        }
    }
}

#Preview {
    NavigationStack { TodayView() }
        .preferredColorScheme(.dark)
}
