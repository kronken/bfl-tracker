import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Environment(WeatherStore.self) private var weather

    @Query(sort: \Item.purchaseDate, order: .reverse) private var items: [Item]
    @Query private var logs: [DayLog]

    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var pastWeather: WeatherSnapshot?
    @State private var showPicker = false
    @State private var showCityChoice = false
    @State private var showNewItem = false
    @State private var toggleCount = 0

    private let calendar = Calendar.current

    var body: some View {
        TabScreen {
            ScreenHeader(subtitle: dateLabel, title: title) {
                GlassIconButton(systemImage: "calendar", accessibilityLabel: "Pick a day") { showPicker = true }
            }
            WeekStrip(selectedDay: $selectedDay, loggedDayKeys: loggedDayKeys)
            weatherSection
            if owned.isEmpty {
                emptyWardrobe
            } else {
                outfitSections
            }
        }
        .sensoryFeedback(.selection, trigger: toggleCount)
        #if DEBUG
        // `-openTodaySheet picker|city` on launch, for screenshots.
        .onAppear {
            switch UserDefaults.standard.string(forKey: "openTodaySheet") {
            case "picker": showPicker = true
            case "city": showCityChoice = true
            default: break
            }
        }
        #endif
        .task(id: settings.weatherLocation) {
            await weather.refreshToday(locationSetting: settings.weatherLocation)
        }
        .task(id: "\(dayKey)|\(settings.weatherLocation ?? "")") {
            await loadPastWeather()
        }
        .onChange(of: weather.today) { storeTodaysWeather() }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            // A new day may have started while the app was in the background.
            if !calendar.isDateInToday(selectedDay), selectedDay > calendar.startOfDay(for: .now) {
                selectedDay = calendar.startOfDay(for: .now)
            }
            Task { await weather.refreshToday(locationSetting: settings.weatherLocation) }
        }
        .sheet(isPresented: $showPicker) {
            PickDaySheet(selectedDay: $selectedDay)
        }
        .sheet(isPresented: $showCityChoice) {
            NavigationStack {
                CityChoiceView(showsFooter: false) { showCityChoice = false }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showCityChoice = false }.tint(.textPrimary)
                        }
                    }
            }
            .presentationBackground(.appBackground)
        }
        .sheet(isPresented: $showNewItem) {
            ItemFormView(mode: .new)
        }
    }

    // MARK: Day

    private var dayKey: String { DayKey.make(for: selectedDay) }
    private var isToday: Bool { calendar.isDateInToday(selectedDay) }

    private var title: String {
        if isToday { return "Today" }
        if calendar.isDateInYesterday(selectedDay) { return "Yesterday" }
        return selectedDay.formatted(.dateTime.weekday(.wide))
    }

    private var dateLabel: String {
        selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var loggedDayKeys: Set<String> {
        Set(logs.filter { !($0.items ?? []).isEmpty }.map(\.dayKey))
    }

    /// The selected day's logs; more than one only if sync created duplicates.
    private var dayLogs: [DayLog] { logs.filter { $0.dayKey == dayKey } }

    private func isWorn(_ item: Item) -> Bool { dayLogs.contains { $0.isWorn(item) } }

    // MARK: Weather

    private var dayWeather: WeatherSnapshot? {
        if isToday, case .loaded(let snapshot) = weather.today { return snapshot }
        return dayLogs.lazy.compactMap(\.weather).first ?? pastWeather
    }

    @ViewBuilder
    private var weatherSection: some View {
        if let dayWeather {
            WeatherCard(snapshot: dayWeather, isToday: isToday, attribution: weather.attribution)
        } else if isToday {
            switch weather.today {
            case .needsLocation:
                WeatherPromptCard(
                    title: "Where should the forecast come from?",
                    message: "Pick your city or use your location, and Today puts the right clothes first.",
                    actionTitle: "Choose city"
                ) { showCityChoice = true }
            case .locationDenied:
                WeatherPromptCard(
                    title: "Location access is off",
                    message: "Allow location for Buy It For Life in the Settings app, or pick a city instead.",
                    actionTitle: "Choose a city"
                ) { showCityChoice = true }
            case .failed:
                WeatherPromptCard(
                    title: "Weather unavailable",
                    message: "The forecast couldn’t be loaded. Your clothes are listed without it.",
                    actionTitle: "Try again"
                ) {
                    Task { await weather.refreshToday(locationSetting: settings.weatherLocation, force: true) }
                }
            case .loading, .loaded:
                WeatherCard.placeholder
            }
        }
    }

    private func storeTodaysWeather() {
        guard case .loaded(let snapshot) = weather.today,
              let log = try? DayLog.fetchOrCreate(dayKey: DayKey.make(for: .now), in: modelContext),
              log.weather != snapshot
        else { return }
        log.store(snapshot)
        try? modelContext.save()
    }

    /// For a past day without a stored snapshot, fetch its noon weather once
    /// and keep it on the day.
    private func loadPastWeather() async {
        pastWeather = nil
        guard !isToday, dayLogs.allSatisfy({ $0.weather == nil }) else { return }
        let key = dayKey
        guard let snapshot = await weather.history(for: key, locationSetting: settings.weatherLocation),
              key == dayKey
        else { return }
        pastWeather = snapshot
        if let log = try? DayLog.fetchOrCreate(dayKey: key, in: modelContext) {
            log.store(snapshot)
            try? modelContext.save()
        }
    }

    // MARK: Outfit

    /// Items in the wardrobe on the selected day, most worn first.
    private var owned: [Item] {
        items.filter { $0.wasOwned(on: selectedDay) }
            .sorted { $0.stats.wearCount > $1.stats.wearCount }
    }

    private var wornCount: Int { owned.count(where: isWorn) }

    @ViewBuilder
    private var outfitSections: some View {
        if let dayWeather {
            let suited = owned.filter { $0.suits(temperatureC: dayWeather.temperatureC, conditions: dayWeather.conditions) }
            let unsuited = owned.filter { !$0.suits(temperatureC: dayWeather.temperatureC, conditions: dayWeather.conditions) }
            if !suited.isEmpty {
                outfitList(
                    label: isToday ? "Suits today" : "Suits that day",
                    trailing: "\(wornCount) worn",
                    items: suited
                ) { item in
                    statsLine(item)
                }
            }
            if !unsuited.isEmpty {
                outfitList(
                    label: "Not for this weather",
                    trailing: suited.isEmpty ? "\(wornCount) worn" : nil,
                    items: unsuited,
                    dimmed: true
                ) { item in
                    item.unsuitedReason(temperatureC: dayWeather.temperatureC, conditions: dayWeather.conditions)
                }
            }
        } else {
            outfitList(label: "Your wardrobe", trailing: "\(wornCount) worn", items: owned) { item in
                statsLine(item)
            }
        }
    }

    private func statsLine(_ item: Item) -> String {
        let stats = item.stats
        let wears = stats.wearCount == 1 ? "1 wear" : "\(stats.wearCount) wears"
        guard let cpw = stats.costPerWearCents else { return wears }
        return "\(Money.format(fractionalCents: cpw)) / wear · \(wears)"
    }

    private func outfitList(
        label: String,
        trailing: String?,
        items: [Item],
        dimmed: Bool = false,
        detail: @escaping (Item) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label, trailing: trailing)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider() }
                    OutfitRow(item: item, detail: detail(item), isWorn: isWorn(item), dimmed: dimmed) {
                        toggle(item)
                    }
                }
            }
            .card(padding: nil)
        }
        .padding(.top, 8)
    }

    private func toggle(_ item: Item) {
        guard let log = try? DayLog.fetchOrCreate(dayKey: dayKey, in: modelContext) else { return }
        if log.weather == nil, let dayWeather { log.store(dayWeather) }
        withAnimation(.snappy(duration: 0.2)) { log.toggle(item) }
        try? modelContext.save()
        toggleCount += 1
    }

    private var emptyWardrobe: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(items.isEmpty ? "Nothing to wear yet" : "Nothing owned on this day")
                .font(.rowTitle)
                .foregroundStyle(.textPrimary)
            Text(items.isEmpty
                 ? "Add your clothes, then tap what you wear each day."
                 : "Items show up here from the day you bought them.")
                .font(.rowDetail)
                .foregroundStyle(.textSecondary)
            if items.isEmpty {
                Button("Add an item") { showNewItem = true }
                    .buttonStyle(.primary)
            }
        }
        .card()
        .padding(.top, 8)
    }
}

#Preview {
    NavigationStack { TodayView() }
        .environment(AppSettings())
        .environment(WeatherStore())
        .modelContainer(for: [Item.self, DayLog.self], inMemory: true)
        .preferredColorScheme(.dark)
}
