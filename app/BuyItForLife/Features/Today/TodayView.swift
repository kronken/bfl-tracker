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
    /// Groups switched to pick-any ("Wore more?") and groups expanded after
    /// picking, keyed by day and group, so both reset on a new day.
    @State private var multiGroups: Set<String> = []
    @State private var expandedGroups: Set<String> = []

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

    /// Items Today offers on the selected day (owned then, not inactive),
    /// favorites first, then most worn.
    private var owned: [Item] {
        items.filter { $0.isOfferedOnToday(on: selectedDay) }
            .sorted {
                OutfitRules.isOrderedBefore(favoriteA: $0.isFavorite, wearsA: $0.stats.wearCount,
                                            favoriteB: $1.isFavorite, wearsB: $1.stats.wearCount)
            }
    }

    private var dailyDrivers: [Item] { owned.filter(\.isDailyDriver) }
    private var clothes: [Item] { owned.filter { !$0.isDailyDriver } }

    /// What counts as worn on the selected day: the saved outfit, or for a day
    /// nobody has touched yet, every daily driver.
    private var selection: Set<UUID> {
        OutfitRules.effectiveSelection(
            saved: Set(dayLogs.flatMap { ($0.items ?? []).map(\.id) }),
            isSaved: dayLogs.contains(where: \.isSaved),
            dailyDrivers: Set(dailyDrivers.map(\.id))
        )
    }

    private func isWorn(_ item: Item) -> Bool { selection.contains(item.id) }

    private var wornCount: Int { owned.count(where: isWorn) }

    private func suits(_ item: Item) -> Bool {
        guard let dayWeather else { return true }
        return item.suits(temperatureC: dayWeather.temperatureC, conditions: dayWeather.conditions)
    }

    @ViewBuilder
    private var outfitSections: some View {
        if !dailyDrivers.isEmpty { dailyDriversCard }

        let suited = clothes.filter(suits)
        let unsuited = clothes.filter { !suits($0) }
        if !clothes.isEmpty {
            SectionLabel(
                "\(dayWeather == nil ? "Your wardrobe" : isToday ? "Suits today" : "Suits that day") · favorites first",
                trailing: "\(wornCount) worn"
            )
            .padding(.top, 8)
        }
        ForEach(OutfitGroup.allCases) { group in
            let groupItems = suited.filter { OutfitGroup(category: $0.category) == group }
            if !groupItems.isEmpty { groupSection(group, items: groupItems) }
        }
        if !unsuited.isEmpty, let dayWeather {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Not for this weather")
                VStack(spacing: 0) {
                    ForEach(Array(unsuited.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { RowDivider() }
                        OutfitRow(
                            item: item,
                            detail: item.unsuitedReason(temperatureC: dayWeather.temperatureC,
                                                        conditions: dayWeather.conditions),
                            isWorn: isWorn(item), dimmed: true
                        ) { toggle(item) }
                    }
                }
                .card(padding: nil)
            }
            .padding(.top, 8)
        }
    }

    // MARK: Daily drivers

    private var dailyDriversCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("DAILY DRIVERS").tracking(0.3)
                Spacer()
                Text("ON BY DEFAULT · ANY WEATHER")
            }
            .font(.label)
            .foregroundStyle(.textSecondary)
            FlowLayout(spacing: 8) {
                ForEach(dailyDrivers) { item in
                    DailyDriverChip(item: item, isOn: isWorn(item)) { toggle(item) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card(padding: nil)
    }

    // MARK: Groups

    /// Per-day group state, e.g. "2026-10-10|bottoms". Resets on a new day.
    private func groupKey(_ group: OutfitGroup) -> String { "\(dayKey)|\(group.rawValue)" }

    private func selectedCount(in group: OutfitGroup) -> Int {
        clothes.count { OutfitGroup(category: $0.category) == group && isWorn($0) }
    }

    /// Pick-one unless switched to "Wore more?" today, or more than one is
    /// already picked (e.g. an older day).
    private func isPickOne(_ group: OutfitGroup) -> Bool {
        group.isPickOneByDefault && !multiGroups.contains(groupKey(group)) && selectedCount(in: group) <= 1
    }

    private func groupSection(_ group: OutfitGroup, items: [Item]) -> some View {
        let pickOne = isPickOne(group)
        let picked = items.filter(isWorn)
        let collapsed = pickOne && !picked.isEmpty && !expandedGroups.contains(groupKey(group))
        let shown = collapsed ? picked : items
        let hidden = items.count - picked.count
        let rule = collapsed ? (hidden > 0 ? "\(hidden) more hidden" : "Picked") : (pickOne ? "Pick one" : "Pick any")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.title)
                        .font(.rowTitle)
                        .foregroundStyle(.textPrimary)
                    Text(rule)
                        .font(.footnote)
                        .foregroundStyle(.textSecondary)
                }
                Spacer()
                if group.isPickOneByDefault {
                    Button(collapsed ? "Change" : (pickOne ? "Wore more?" : "Pick one")) {
                        withAnimation(.snappy) { groupAction(group, collapsed: collapsed, pickOne: pickOne) }
                    }
                    .font(.rowDetail)
                    .foregroundStyle(.dataBlue)
                    .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 44)

            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider() }
                    OutfitRow(item: item, detail: statsLine(item), isWorn: isWorn(item), dimmed: false) {
                        toggle(item)
                    }
                }
            }
            .card(padding: nil)
        }
    }

    private func groupAction(_ group: OutfitGroup, collapsed: Bool, pickOne: Bool) {
        let key = groupKey(group)
        if collapsed {
            expandedGroups.insert(key)
        } else if pickOne {
            multiGroups.insert(key)
        } else {
            // Back to pick one: keep only the first picked item (favorite / most worn).
            multiGroups.remove(key)
            let picked = clothes.filter { OutfitGroup(category: $0.category) == group && isWorn($0) }
            if picked.count > 1 {
                save(selection.subtracting(picked.dropFirst().map(\.id)))
            }
        }
    }

    private func statsLine(_ item: Item) -> String {
        let stats = item.stats
        let wears = stats.wearCount == 1 ? "1 wear" : "\(stats.wearCount) wears"
        guard let cpw = stats.costPerWearCents else { return wears }
        return "\(Money.format(fractionalCents: cpw)) / wear · \(wears)"
    }

    // MARK: Saving

    private func toggle(_ item: Item) {
        let group = OutfitGroup(category: item.category)
        let pickOne = !item.isDailyDriver && isPickOne(group)
        let groupIDs = Set(clothes.filter { OutfitGroup(category: $0.category) == group }.map(\.id))
        let wasWorn = isWorn(item)
        let newSelection = OutfitRules.toggle(item.id, in: selection, group: groupIDs, pickOne: pickOne)
        // Picking in a pick-one group collapses it to the picked row.
        if pickOne && !wasWorn { expandedGroups.remove(groupKey(group)) }
        save(newSelection)
    }

    /// Stores the day's outfit; from now on the day counts as saved.
    private func save(_ newSelection: Set<UUID>) {
        guard let log = try? DayLog.fetchOrCreate(dayKey: dayKey, in: modelContext) else { return }
        if log.weather == nil, let dayWeather { log.store(dayWeather) }
        withAnimation(.snappy(duration: 0.2)) {
            log.items = items.filter { newSelection.contains($0.id) }
            log.userEdited = true
        }
        try? modelContext.save()
        toggleCount += 1
        if isToday {
            Task { await Reminders.reschedule(settings: settings, context: modelContext) }
        }
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
