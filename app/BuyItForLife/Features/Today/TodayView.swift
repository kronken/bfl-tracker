import StoreKit
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
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
            let outfit = makeOutfit()
            if outfit.offered.isEmpty {
                emptyWardrobe
            } else {
                outfitSections(outfit)
            }
        }
        .sensoryFeedback(.selection, trigger: toggleCount)
        #if DEBUG
        // `-benchToggle <file>`: taps the first item six times and writes
        // how long each tap takes until the next frame is drawn.
        .task {
            guard let file = UserDefaults.standard.string(forKey: "benchToggle") else { return }
            try? await Task.sleep(for: .seconds(3))
            var report = ""
            for _ in 0..<6 {
                guard let item = makeOutfit().clothes.first else { break }
                let start = ContinuousClock.now
                toggle(item)
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() } // runs after the frame is committed
                }
                let elapsed = ContinuousClock.now - start
                report += "\(elapsed.components.attoseconds / 1_000_000_000_000_000 + elapsed.components.seconds * 1000) ms\n"
                try? await Task.sleep(for: .milliseconds(700))
            }
            try? report.write(toFile: file, atomically: true, encoding: .utf8)
        }
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

    /// Everything Today shows for the selected day, worked out once per redraw.
    /// (Computing it per row made every tap re-sort all items and re-count
    /// every item's wears thousands of times.)
    private struct DayOutfit {
        /// Items offered on the day (owned then, not inactive), favorites
        /// first, then most worn.
        var offered: [Item]
        var stats: [UUID: ItemStats]
        var selection: Set<UUID>

        var dailyDrivers: [Item] { offered.filter(\.isDailyDriver) }
        var clothes: [Item] { offered.filter { !$0.isDailyDriver } }
        var wornCount: Int { offered.count { selection.contains($0.id) } }

        func isWorn(_ item: Item) -> Bool { selection.contains(item.id) }
    }

    private func makeOutfit() -> DayOutfit {
        let candidates = items.filter { $0.isOfferedOnToday(on: selectedDay) }
        let stats = Dictionary(candidates.map { ($0.id, $0.stats) }, uniquingKeysWith: { first, _ in first })
        let offered = candidates.sorted {
            OutfitRules.isOrderedBefore(favoriteA: $0.isFavorite, wearsA: stats[$0.id]?.wearCount ?? 0,
                                        favoriteB: $1.isFavorite, wearsB: stats[$1.id]?.wearCount ?? 0)
        }
        let logs = dayLogs
        let selection = OutfitRules.effectiveSelection(
            saved: Set(logs.flatMap { ($0.items ?? []).map(\.id) }),
            isSaved: logs.contains(where: \.isSaved),
            dailyDrivers: Set(offered.filter(\.isDailyDriver).map(\.id))
        )
        return DayOutfit(offered: offered, stats: stats, selection: selection)
    }

    private func suits(_ item: Item) -> Bool {
        guard let dayWeather else { return true }
        return item.suits(temperatureC: dayWeather.temperatureC, conditions: dayWeather.conditions)
    }

    @ViewBuilder
    private func outfitSections(_ outfit: DayOutfit) -> some View {
        if !outfit.dailyDrivers.isEmpty { dailyDriversCard(outfit) }

        let clothes = outfit.clothes
        let suited = clothes.filter(suits)
        let unsuited = clothes.filter { !suits($0) }
        if !clothes.isEmpty {
            SectionLabel(
                "\(dayWeather == nil ? "Your wardrobe" : isToday ? "Suits today" : "Suits that day") · favorites first",
                trailing: "\(outfit.wornCount) worn"
            )
            .padding(.top, 8)
        }
        ForEach(OutfitGroup.allCases) { group in
            let groupItems = suited.filter { OutfitGroup(item: $0) == group }
            if !groupItems.isEmpty { groupSection(group, items: groupItems, outfit: outfit) }
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
                            isWorn: outfit.isWorn(item), dimmed: true
                        ) { toggle(item) }
                    }
                }
                .card(padding: nil)
            }
            .padding(.top, 8)
        }
    }

    // MARK: Daily drivers

    private func dailyDriversCard(_ outfit: DayOutfit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("DAILY DRIVERS").tracking(0.3)
                Spacer()
                Text("ON BY DEFAULT · ANY WEATHER")
            }
            .font(.label)
            .foregroundStyle(.textSecondary)
            FlowLayout(spacing: 8) {
                ForEach(outfit.dailyDrivers) { item in
                    DailyDriverChip(item: item, isOn: outfit.isWorn(item)) { toggle(item) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .card(padding: nil)
    }

    // MARK: Groups

    /// One category section: a title and its items. Pick as many as you like.
    private func groupSection(_ group: OutfitGroup, items: [Item], outfit: DayOutfit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.title)
                .font(.rowTitle)
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider() }
                    OutfitRow(item: item, detail: statsLine(outfit.stats[item.id] ?? item.stats),
                              isWorn: outfit.isWorn(item), dimmed: false) {
                        toggle(item)
                    }
                }
            }
            .card(padding: nil)
        }
    }

    private func statsLine(_ stats: ItemStats) -> String {
        let wears = stats.wearCount == 1 ? "1 wear" : "\(stats.wearCount) wears"
        guard let cpw = stats.costPerWearCents else { return wears }
        return "\(Money.format(fractionalCents: cpw)) / wear · \(wears)"
    }

    // MARK: Saving

    private func toggle(_ item: Item) {
        save(OutfitRules.toggle(item.id, in: makeOutfit().selection))
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
            askForReviewIfDue()
        }
    }

    /// After a week of logging every day, ask for a rating once per version.
    private func askForReviewIfDue() {
        let logged = Set(logs.filter { !($0.items ?? []).isEmpty }.map(\.dayKey))
        let streak = ReviewPrompt.streak(loggedDayKeys: logged, today: .now)
        let version = ReviewPrompt.currentVersion
        guard ReviewPrompt.shouldAsk(streak: streak, askedVersion: ReviewPrompt.askedVersion, currentVersion: version)
        else { return }
        ReviewPrompt.askedVersion = version
        Task {
            // Let the checkmark land first.
            try? await Task.sleep(for: .seconds(1))
            requestReview()
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
