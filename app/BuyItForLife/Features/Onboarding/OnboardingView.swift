import SwiftData
import SwiftUI

/// First-launch flow: what the app does, where the forecast comes from, and
/// the first item.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, city, firstItem, done
    }

    var onFinish: () -> Void

    @Environment(AppSettings.self) private var settings
    @Query private var items: [Item]

    @State private var step: Step = .welcome
    @State private var lastAdded: Item?
    @State private var itemFormID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch step {
                case .welcome:
                    WelcomeStep { go(to: .city) }
                case .city:
                    CityChoiceView { go(to: .firstItem) }
                case .firstItem:
                    FirstItemStep { item in
                        lastAdded = item
                        go(to: .done)
                    }
                    .id(itemFormID)
                case .done:
                    DoneStep(item: lastAdded, itemCount: items.count) {
                        itemFormID = UUID()
                        go(to: .firstItem)
                    } onStart: {
                        settings.onboardingCompleted = true
                        onFinish()
                    }
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity))
        }
        .background(.appBackground)
        #if DEBUG
        // `-onboardingStep 0…3` with `-forceOnboarding YES`, for screenshots.
        .onAppear {
            if let raw = UserDefaults.standard.object(forKey: "onboardingStep") as? String,
               let index = Int(raw), let debugStep = Step(rawValue: index) {
                step = debugStep
                lastAdded = items.first
            }
        }
        #endif
    }

    private func go(to next: Step) {
        withAnimation(.snappy) { step = next }
    }

    /// Back button (on the middle steps) and the step dots.
    private var topBar: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { dot in
                    Capsule()
                        .fill(dotColor(dot))
                        .frame(width: 18, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
            HStack {
                if step == .city || step == .firstItem {
                    GlassIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") {
                        go(to: Step(rawValue: step.rawValue - 1) ?? .welcome)
                    }
                }
                Spacer()
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func dotColor(_ dot: Step) -> Color {
        if dot == step { return .textPrimary }
        return dot.rawValue < step.rawValue ? .textTertiary : .surfaceRaised
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    var onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    exampleCard
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Buy It For Life")
                            .font(.screenTitle)
                            .foregroundStyle(.textPrimary)
                        Text("Know what every piece costs, per wear.")
                            .font(.body)
                            .foregroundStyle(.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        point("hanger", "Register what you own", "A photo, the price, and the weather it’s for.")
                        point("tshirt", "Tap what you wear", "Once a day. The forecast puts the right gear first.")
                        point("chart.line.downtrend.xyaxis", "Watch the cost fall", "Per item, per day, and for the whole wardrobe.")
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            Button("Add your first item", action: onNext)
                .buttonStyle(.primary)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
    }

    /// A €349 pair of boots, falling to €0.85 per wear by the 412th wear.
    private var exampleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                CategoryIcon(category: .footwear)
                    .foregroundStyle(.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: 0x2A1F16), in: .rect(cornerRadius: Radius.thumb))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Leather boots, \(Money.format(cents: 34_900))")
                        .font(.rowTitle)
                        .foregroundStyle(.textPrimary)
                    Text("Cost per wear over 5 years")
                        .font(.rowDetail)
                        .foregroundStyle(.textSecondary)
                }
            }
            ZStack(alignment: .topLeading) {
                GeometryReader { geometry in
                    let w = geometry.size.width, h = geometry.size.height - 20
                    Path { path in
                        path.move(to: CGPoint(x: 6, y: 8))
                        path.addCurve(to: CGPoint(x: w * 0.39, y: h * 0.87),
                                      control1: CGPoint(x: w * 0.1, y: h * 0.65),
                                      control2: CGPoint(x: w * 0.23, y: h * 0.8))
                        path.addCurve(to: CGPoint(x: w - 6, y: h * 0.96),
                                      control1: CGPoint(x: w * 0.6, y: h * 0.93),
                                      control2: CGPoint(x: w * 0.8, y: h * 0.95))
                    }
                    .stroke(.dataBlue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    Circle().fill(.dataBlue).frame(width: 8, height: 8).position(x: 6, y: 8)
                    Circle().fill(.dataBlue).frame(width: 10, height: 10)
                        .overlay { Circle().stroke(.surface, lineWidth: 2) }
                        .position(x: w - 6, y: h * 0.96)
                    Text(Money.format(cents: 34_900))
                        .font(.number(.subheadline))
                        .foregroundStyle(.textSecondary)
                        .position(x: 50, y: 8)
                    Text(Money.format(fractionalCents: 85))
                        .font(.number(.title2))
                        .foregroundStyle(.textPrimary)
                        .fixedSize()
                        .position(x: w - 40, y: h * 0.6)
                    HStack {
                        Text("1st wear")
                        Spacer()
                        Text("412th wear")
                    }
                    .font(.label)
                    .foregroundStyle(.textSecondary)
                    .frame(width: w)
                    .position(x: w / 2, y: geometry.size.height - 8)
                }
            }
            .frame(height: 112)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example: leather boots for 349 euros cost 85 cents per wear by the 412th wear.")
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.textPrimary)
                .frame(width: 36, height: 36)
                .background(.surfaceRaised, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                Text(detail)
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
            }
        }
    }
}

// MARK: - Done

private struct DoneStep: View {
    var item: Item?
    var itemCount: Int
    var onAddAnother: () -> Void
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 14) {
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.positive)
                    .frame(width: 64, height: 64)
                    .background(.positive.opacity(0.14), in: .circle)
                Text("Logged.")
                    .font(.screenTitle)
                    .foregroundStyle(.textPrimary)
                Text("Your wardrobe has \(itemCount == 1 ? "1 item" : "\(itemCount) items"). The more you add, the better Today’s suggestions get.")
                    .font(.body)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            if let item { itemCard(item) }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(action: onAddAnother) {
                    Label("Add another item", systemImage: "plus")
                }
                .buttonStyle(.primary)
                Button("Start using the app", action: onStart)
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .glassEffect(.regular.interactive(), in: .capsule)
                Text("You can add more any time from Wardrobe.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
    }

    private func itemCard(_ item: Item) -> some View {
        let stats = item.stats
        return HStack(spacing: 14) {
            ItemImageView(content: item.thumbnailContent, cornerRadius: Radius.tile, iconSize: 32)
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.rowTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(2)
                Text(meta(item))
                    .font(.rowDetail)
                    .foregroundStyle(.textSecondary)
                if let cpw = stats.costPerWearCents {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Money.format(fractionalCents: cpw))
                            .font(.number(.title2))
                            .foregroundStyle(.textPrimary)
                        Text("/ wear")
                            .font(.rowDetail)
                            .foregroundStyle(.textSecondary)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .card(padding: nil)
    }

    private func meta(_ item: Item) -> String {
        let price = Money.format(cents: item.purchasePriceCents)
        return item.priorWearCount > 0 ? "\(price) · ~\(item.priorWearCount) wears so far" : price
    }
}
