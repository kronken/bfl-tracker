import SwiftUI

/// Corner radii from the design system.
enum Radius {
    /// Cards and grouped lists.
    static let card: CGFloat = 26
    /// Day tiles, wardrobe cards.
    static let tile: CGFloat = 16
    /// Item thumbnails, date buttons.
    static let thumb: CGFloat = 10
}

// MARK: - Card

private struct CardModifier: ViewModifier {
    var padding: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.surface, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.stroke, lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: Radius.card))
            .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
    }
}

extension View {
    /// The design's card: dark surface, hairline border, 26pt corners.
    /// Pass `padding: nil` for lists whose rows bring their own padding.
    func card(padding: CGFloat? = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

// MARK: - Section label

/// Uppercase label above a card, e.g. "SUITS TODAY" with "3 WORN" on the right.
struct SectionLabel: View {
    var title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).tracking(0.3)
            Spacer()
            if let trailing {
                Text(trailing.uppercased())
            }
        }
        .font(.label)
        .foregroundStyle(.textSecondary)
        .padding(.horizontal, 4)
    }
}

// MARK: - Screen header

/// Top-of-screen header: a small line above a large title, with optional
/// buttons aligned to the title's bottom edge.
struct ScreenHeader<Trailing: View>: View {
    var subtitle: String?
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let subtitle {
                    Text(subtitle)
                        .font(.rowDetail)
                        .foregroundStyle(.textSecondary)
                }
                Text(title)
                    .font(.screenTitle)
                    .foregroundStyle(.textPrimary)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(subtitle: String? = nil, title: String) {
        self.init(subtitle: subtitle, title: title) { EmptyView() }
    }
}

// MARK: - Buttons

/// Full-width gold capsule, 50pt tall. The main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rowTitle)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(isEnabled ? AnyShapeStyle(.onAccent) : AnyShapeStyle(.textSecondary))
            .background(isEnabled ? AnyShapeStyle(.accentGold) : AnyShapeStyle(.surfaceRaised), in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Full-width dark capsule with a hairline border, e.g. "Mark as sold".
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rowTitle)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.textPrimary)
            .background(.surfaceRaised, in: .capsule)
            .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Round 44pt Liquid Glass button for a header icon, e.g. the calendar on Today.
struct GlassIconButton: View {
    var systemImage: String
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.textPrimary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Screen scaffold

/// A tab's root screen: dark background, scrolling content with the design's
/// 16pt side margins and 16pt spacing between blocks.
struct TabScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(.appBackground)
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
