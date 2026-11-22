import SwiftUI

/// The attribution Apple requires wherever WeatherKit data is shown: the
/// Apple Weather mark and a visible link to the legal page listing the other
/// data sources. The link works even before WeatherKit has sent the mark.
struct WeatherAttributionView: View {
    @Environment(WeatherStore.self) private var weather

    /// Where WeatherKit's attribution points; used until it has loaded.
    static let fallbackLegalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    var body: some View {
        HStack(spacing: 12) {
            mark
                .accessibilityLabel("Apple Weather")
            Spacer(minLength: 8)
            Link(destination: weather.attribution?.legalURL ?? Self.fallbackLegalURL) {
                HStack(spacing: 4) {
                    Text("Other data sources")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.footnote)
                .foregroundStyle(.dataBlue)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .accessibilityHint("Opens the Apple Weather legal page")
        }
        .task { await weather.loadAttribution() }
    }

    @ViewBuilder
    private var mark: some View {
        if let url = weather.attribution?.markURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                textMark
            }
            .frame(height: 16)
        } else {
            textMark
        }
    }

    /// " Weather" in text, as Apple allows when the image isn't available.
    private var textMark: some View {
        Text("\u{F8FF} Weather")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.textPrimary)
    }
}
