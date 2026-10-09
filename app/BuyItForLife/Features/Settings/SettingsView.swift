import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WeatherStore.self) private var weather
    @Query private var items: [Item]

    @State private var cityListOpen = false
    @State private var isLocating = false
    @State private var locationProblem: String?

    static let targetStep = 25
    static let presets = [50, 100, 200, 500]

    var body: some View {
        TabScreen {
            ScreenHeader(title: "Settings")
            VStack(alignment: .leading, spacing: 24) {
                weatherSection
                paidOffSection
                Text("Buy It For Life · version \(Self.version)")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
        }
    }

    // MARK: Weather

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Weather")
            VStack(spacing: 0) {
                Button {
                    withAnimation(.snappy) { cityListOpen.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        iconTile("mappin.and.ellipse")
                        Text("City")
                            .font(.body)
                            .foregroundStyle(.textPrimary)
                        Spacer()
                        if isLocating {
                            ProgressView().tint(.textSecondary)
                        } else {
                            Text(locationLabel)
                                .font(.body)
                                .foregroundStyle(.textSecondary)
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.textTertiary)
                            .rotationEffect(.degrees(cityListOpen ? 90 : 0))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minHeight: 56)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(locationLabel)
                .accessibilityHint(cityListOpen ? "Collapses the city list" : "Shows the city list")

                if cityListOpen {
                    VStack(spacing: 0) {
                        RowDivider()
                        cityRow(id: AppSettings.currentLocation, title: "Current location", icon: "location.fill")
                        ForEach(cityChoices) { city in
                            RowDivider().padding(.leading, 60)
                            cityRow(id: city.id, title: city.name, icon: nil)
                        }
                    }
                    .background(Color(hex: 0x101013))
                }
            }
            .card(padding: nil)

            Text(locationProblem ?? cityNote)
                .font(.footnote)
                .foregroundStyle(locationProblem == nil ? .textSecondary : .warning)
                .padding(.horizontal, 4)
        }
    }

    private var locationLabel: String {
        switch settings.weatherLocation {
        case nil: "Not set"
        case AppSettings.currentLocation?: "Current location"
        case let id?: Cities.city(id: id)?.name ?? "Unknown"
        }
    }

    private var cityNote: String {
        switch settings.weatherLocation {
        case nil: "Pick where the forecast for Today comes from."
        case AppSettings.currentLocation?: "Follows you when you travel. Location is only used for the forecast."
        case let id?: "Today sorts your clothes by the forecast in \(Cities.city(id: id)?.name ?? "this city")."
        }
    }

    /// The suggestions for this device's country, plus the chosen city if it
    /// came from another list.
    private var cityChoices: [City] {
        var cities = Cities.suggestions(forRegion: Locale.current.region?.identifier)
        if let id = settings.weatherLocation, let chosen = Cities.city(id: id), !cities.contains(chosen) {
            cities.insert(chosen, at: 0)
        }
        return cities
    }

    private func cityRow(id: String, title: String, icon: String?) -> some View {
        Button {
            Task { await choose(id) }
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.dataBlue)
                    }
                }
                .frame(width: 32)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.textPrimary)
                Spacer()
                if settings.weatherLocation == id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.accentGold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isLocating)
        .accessibilityAddTraits(settings.weatherLocation == id ? .isSelected : [])
    }

    /// Picking "current location" asks for permission and waits for a
    /// position first; if that fails the previous choice is kept.
    private func choose(_ id: String) async {
        locationProblem = nil
        if id == AppSettings.currentLocation {
            isLocating = true
            defer { isLocating = false }
            do {
                _ = try await weather.location.currentLocation()
            } catch LocationProvider.LocationError.denied {
                locationProblem = "Location access is off. Allow it for Buy It For Life in the Settings app, or pick a city."
                return
            } catch {
                locationProblem = "Couldn’t find your location right now. Try again, or pick a city."
                return
            }
        }
        settings.weatherLocation = id
        withAnimation(.snappy) { cityListOpen = false }
        await weather.refreshToday(locationSetting: id, force: true)
    }

    // MARK: Paid off

    private var paidOffSection: some View {
        let target = settings.paidOffTargetCents
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Paid off")
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Target cost per wear")
                            .font(.body)
                            .foregroundStyle(.textPrimary)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Money.format(fractionalCents: Double(target)))
                                .font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                                .foregroundStyle(.textPrimary)
                                .contentTransition(.numericText())
                            Text("/ wear")
                                .font(.rowDetail)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        stepButton("minus", label: "Lower target", enabled: target > Self.targetStep) {
                            setTarget(target - Self.targetStep)
                        }
                        Rectangle().fill(.stroke).frame(width: 1, height: 24)
                        stepButton("plus", label: "Raise target", enabled: true) {
                            setTarget(target + Self.targetStep)
                        }
                    }
                    .padding(2)
                    .background(.surfaceRaised, in: .capsule)
                }
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.self) { preset in
                        Button {
                            setTarget(preset)
                        } label: {
                            Text(Money.format(fractionalCents: Double(preset)))
                                .font(.number(.subheadline))
                                .foregroundStyle(preset == target ? .textPrimary : .textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(preset == target ? AnyShapeStyle(.fillSelected) : AnyShapeStyle(.clear),
                                            in: .capsule)
                                .overlay { Capsule().strokeBorder(.stroke, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(preset == target ? .isSelected : [])
                    }
                }
                HStack(spacing: 10) {
                    Circle().fill(.positive).frame(width: 8, height: 8)
                    Text(paidOffPreview(target: target))
                        .font(.rowDetail)
                        .foregroundStyle(.textPrimary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.surfaceRaised, in: .rect(cornerRadius: Radius.tile))
            }
            .card()
            Text("Items under the target get the Paid off label in Insights and Wardrobe.")
                .font(.footnote)
                .foregroundStyle(.textSecondary)
                .padding(.horizontal, 4)
        }
    }

    private func setTarget(_ cents: Int) {
        withAnimation(.snappy(duration: 0.2)) { settings.paidOffTargetCents = max(Self.targetStep, cents) }
    }

    private func paidOffPreview(target: Int) -> String {
        let owned = items.filter { !$0.isSold }
        guard !owned.isEmpty else { return "Add items to see how many are paid off." }
        let paid = owned.count { $0.stats.isPaidOff(targetCents: target) }
        return "\(paid) of \(owned.count) items are paid off at this target."
    }

    private func iconTile(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.textPrimary)
            .frame(width: 32, height: 32)
            .background(.surfaceRaised, in: .rect(cornerRadius: Radius.thumb))
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .textPrimary : .textTertiary)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AppSettings())
        .environment(WeatherStore())
        .modelContainer(for: [Item.self, DayLog.self], inMemory: true)
        .preferredColorScheme(.dark)
}
