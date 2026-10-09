import SwiftUI

/// "Use current location" plus the suggested cities for the device's country.
/// Reused by onboarding, Settings and Today.
struct CityPickerList: View {
    @Binding var selection: String?
    var regionCode: String? = Locale.current.region?.identifier

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button {
                selection = AppSettings.currentLocation
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.dataBlue)
                        .frame(width: 36, height: 36)
                        .background(.dataBlue.opacity(0.16), in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use current location")
                            .font(.rowTitle)
                            .foregroundStyle(.textPrimary)
                        Text("Follows you when you travel")
                            .font(.rowDetail)
                            .foregroundStyle(.textSecondary)
                    }
                    Spacer(minLength: 0)
                    checkmark(selection == AppSettings.currentLocation)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 64)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection == AppSettings.currentLocation ? .isSelected : [])
            .card(padding: nil)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(header)
                VStack(spacing: 0) {
                    let cities = Cities.suggestions(forRegion: regionCode)
                    ForEach(Array(cities.enumerated()), id: \.element.id) { index, city in
                        if index > 0 { RowDivider() }
                        cityRow(city)
                    }
                }
                .card(padding: nil)
            }
        }
    }

    private var header: String {
        guard Cities.isCovered(regionCode: regionCode), let regionCode,
              let country = Locale.current.localizedString(forRegionCode: regionCode)
        else { return "Major cities" }
        return "Suggested for \(country)"
    }

    private func cityRow(_ city: City) -> some View {
        Button {
            selection = city.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(city.name)
                        .font(.body)
                        .foregroundStyle(.textPrimary)
                    Text(regionLine(city))
                        .font(.footnote)
                        .foregroundStyle(.textSecondary)
                }
                Spacer(minLength: 0)
                checkmark(selection == city.id)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == city.id ? .isSelected : [])
    }

    /// The region, plus the country when showing the global list.
    private func regionLine(_ city: City) -> String {
        guard !Cities.isCovered(regionCode: regionCode),
              let country = Locale.current.localizedString(forRegionCode: city.countryCode)
        else { return city.region }
        return "\(city.region), \(country)"
    }

    @ViewBuilder
    private func checkmark(_ isOn: Bool) -> some View {
        if isOn {
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.accentGold)
        }
    }
}

/// The full "Your city" step: title, picker and a Continue button. When
/// "current location" is picked, Continue asks for permission and waits for a
/// position before finishing.
struct CityChoiceView: View {
    var title = "Your city"
    var showsFooter = true
    var onDone: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(WeatherStore.self) private var weather

    @State private var selection: String?
    @State private var isLocating = false
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.screenTitle)
                        .foregroundStyle(.textPrimary)
                    Text("The forecast there decides which clothes come first each morning.")
                        .font(.body)
                        .foregroundStyle(.textSecondary)
                }
                .padding(.horizontal, 4)

                CityPickerList(selection: $selection)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) { footer }
        .background(.appBackground)
        .onAppear { selection = settings.weatherLocation }
        .onChange(of: selection) { problem = nil }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.warning)
                    .multilineTextAlignment(.center)
            }
            Button(action: { Task { await confirm() } }) {
                if isLocating {
                    HStack(spacing: 8) {
                        ProgressView().tint(.onAccent)
                        Text("Finding your location…")
                    }
                } else {
                    Text(ctaTitle)
                }
            }
            .buttonStyle(.primary)
            .disabled(selection == nil || isLocating)
            if showsFooter {
                Text("Only used to fetch the forecast. Change it any time in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.appBackground)
    }

    private var ctaTitle: String {
        switch selection {
        case nil: "Pick a city"
        case AppSettings.currentLocation?: "Continue with current location"
        case let id?: "Continue with \(Cities.city(id: id)?.name ?? "this city")"
        }
    }

    private func confirm() async {
        guard let selection else { return }
        if selection == AppSettings.currentLocation {
            isLocating = true
            defer { isLocating = false }
            do {
                _ = try await weather.location.currentLocation()
            } catch LocationProvider.LocationError.denied {
                problem = "Location access is off. Pick a city, or allow location for Buy It For Life in the Settings app."
                return
            } catch {
                problem = "Couldn’t find your location right now. Try again, or pick a city."
                return
            }
        }
        settings.weatherLocation = selection
        await weather.refreshToday(locationSetting: selection, force: true)
        onDone()
    }
}
