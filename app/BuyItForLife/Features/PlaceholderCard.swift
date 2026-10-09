import SwiftUI

/// Temporary content for screens that are not built yet.
struct PlaceholderCard: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.rowDetail)
            .foregroundStyle(.textSecondary)
            .card()
    }
}
