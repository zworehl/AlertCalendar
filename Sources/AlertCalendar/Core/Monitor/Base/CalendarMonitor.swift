import AppKit
import Combine
import EventKit
import Foundation

extension EKReminder: @retroactive @unchecked Sendable {}

@MainActor
final class CalendarMonitor: ObservableObject {
    @Published var isInitialLoadInProgress = true
    @Published var combinedMenuBarLabel = "Loading..."
    @Published var combinedMenuBarColor: NSColor = .systemGray
    @Published var combinedMenuBarAlertedSegmentIndex: Int?
    @Published var combinedMenuBarAlertTextOpacity: CGFloat = 0
    @Published var combinedMenuBarDotColors: [NSColor] = [.systemGray]
    @Published var combinedMenuBarMarkerStyles: [MenuMarkerStyle] = [.color(.systemGray)]
    @Published var combinedMenuBarSegments: [String] = ["Loading..."]
    @Published var combinedMenuBarSegmentBackgroundColors: [NSColor] = [.clear]
    @Published var combinedMenuBarSegmentBackgroundProgresses: [CGFloat] = [0]
    @Published var combinedMenuBarSegmentParticipationStatuses: [EventParticipationStatus?] = [nil]
    @Published var combinedMenuBarSegmentTextureStatuses: [EventParticipationStatus?] = [nil]
    @Published var combinedMenuBarSegmentAccessorySymbolNames: [[String]] = [[]]
    @Published var combinedMenuBarFootballDisplay: FootballMenuBarDisplay?
    @Published var combinedMenuBarFootballTrailingText: String?
    @Published var combinedMenuBarFootballStatusText: String?
    @Published var combinedMenuBarFootballStatusColor: NSColor = .systemGreen
    @Published var combinedMenuBarFootballGoalHighlightSide: FootballScoreSide?
    @Published var combinedMenuBarFootballGoalHighlightTextOpacity: CGFloat = 0
    @Published var hasEventsAccess = false
    @Published var hasRemindersAccess = false
    @Published var availableEventCalendars: [AvailableCalendar] = []
    @Published var availableReminderCalendars: [AvailableCalendar] = []
    @Published var eventsMenuBarLabel = "No events"
    @Published var remindersMenuBarLabel = "No reminders"
    @Published var eventsMenuBarColor: NSColor = .systemGray
    @Published var remindersMenuBarColor: NSColor = .systemGray
    @Published var upcomingItems: [UpcomingItem] = []
    @Published var activeAlertItem: UpcomingItem?
    @Published var calendarAccessDescription = "Requesting access..."
    @Published var astronomyLocationStatus = "Manual coordinates"
    @Published var lastRefreshDate: Date?
    @Published var refreshDiagnostics = CalendarMonitorRefreshDiagnostics()
    @Published var externalFeedDiagnostics = ExternalFeedDiagnostics()
    @Published var footballMenuSections: [FootballMenuCompetitionSection] = []
    @Published var footballLiveAndNextDaySection = FootballMatchesOverviewSection.placeholder(title: "Now & Next 24 Hours")
    @Published var managedFootballMatchIDs: Set<String> = []
    @Published var managedFootballMatches: [FootballFixtureMatch] = []
    @Published var gameSales: [GameSaleEvent] = []
    @Published var isRefreshingGameSales = false
    @Published var gameSalesErrorDescription: String?
    @Published private(set) var lastGameSalesRefreshDate: Date?
    @Published var isSyncingGoogleHolidays = false
    @Published var googleHolidaySyncErrorDescription: String?
    @Published private(set) var googleHolidayLastRefreshDate: Date?
    @Published private(set) var lastFootballRefreshDate: Date?
    @Published private(set) var lastAstronomyLocationRefreshDate: Date?
    @Published var calendarAlertRuleStatusDescription: String?
    @Published var slackStatusSyncErrorDescription: String?
    @Published var lastSlackStatusSyncDate: Date?
    @Published var slackConnectionStatusMessage: String?
    @Published var slackRuntimeStatusDescription: String?
    @Published private(set) var currentSettings = AppSettings.defaults

    let eventStore: EKEventStore
    let defaults: UserDefaults
    let footballClient: FootballDataAPIClient
    let footballImageStore: FootballImageStore
    let gameSalesClient: GameSalesFeedClient
    let googleHolidayClient: GoogleHolidayFeedClient
    let slackClient: SlackAPIClient
    let clock: AlertCalendarClockProviding

    var settingsStore: AppSettingsStore {
        AppSettingsStore(defaults: defaults)
    }

    var heartbeatCancellable: AnyCancellable?
    var menuBarAnimationCancellable: AnyCancellable?
    var defaultsObserver: AnyCancellable?
    var eventStoreObserver: AnyCancellable?
    var appActivationObserver: AnyCancellable?
    var workspaceResumeObserver: AnyCancellable?
    let refreshCoordinator = CalendarMonitorRefreshCoordinator()
    var tickCount = 0
    var lastPeriodicRefreshDate: Date?
    var birthdayCalendarIDs: Set<String> = []
    var allDayEventItems: [UpcomingItem] = []
    var alreadyNotified: Set<String> = []
    var silencedAlertKeys: Set<String> = []
    var skippedItemKeys: Set<String> = []
    var locationRuntimeState = CalendarMonitorLocationRuntimeState()
    var footballState = CalendarMonitorFootballState()
    var gameSalesState = CalendarMonitorGameSalesState()
    var googleHolidayState = CalendarMonitorGoogleHolidayState()
    var menuBarRotationState = MenuBarRotationState()
    var slackRuntimeState = CalendarMonitorSlackRuntimeState()
    var calendarAlertFullSyncTask: Task<Void, Never>?
    var calendarAlertFullSyncToken: UUID?
    var calendarAlertFullSyncFingerprintInProgress: String?

    init(
        eventStore: EKEventStore = EKEventStore(),
        defaults: UserDefaults = .standard,
        footballClient: FootballDataAPIClient = FootballDataAPIClient(),
        footballImageStore: FootballImageStore = FootballImageStore(),
        gameSalesClient: GameSalesFeedClient = GameSalesFeedClient(),
        googleHolidayClient: GoogleHolidayFeedClient = GoogleHolidayFeedClient(),
        slackClient: SlackAPIClient = SlackAPIClient(),
        clock: AlertCalendarClockProviding = SystemAlertCalendarClock()
    ) {
        self.eventStore = eventStore
        self.defaults = defaults
        self.footballClient = footballClient
        self.footballImageStore = footballImageStore
        self.gameSalesClient = gameSalesClient
        self.googleHolidayClient = googleHolidayClient
        self.slackClient = slackClient
        self.clock = clock

        registerDefaultSettings()
        currentSettings = settingsStore.load()
        managedFootballEventRecords = Self.decodeManagedFootballEventRecords(
            from: defaults.data(forKey: DefaultsKeys.managedFootballEventRecords)
        )
        managedGameSaleEventRecords = Self.decodeManagedGameSaleEventRecords(
            from: defaults.data(forKey: DefaultsKeys.managedGameSaleEventRecords)
        )
        managedGoogleHolidayEventRecords = Self.decodeManagedGoogleHolidayEventRecords(
            from: defaults.data(forKey: DefaultsKeys.managedGoogleHolidayEventRecords)
        )
        self.googleHolidayLastRefreshDate = defaults.object(
            forKey: DefaultsKeys.googleHolidayLastRefreshDate
        ) as? Date
        skippedItemKeys = Set(defaults.stringArray(forKey: DefaultsKeys.skippedItemKeys) ?? [])
        startObservers()
        startHeartbeat()

        Task {
            await bootstrap()
        }
    }

    private static func decodeManagedFootballEventRecords(from data: Data?) -> [ManagedFootballEventRecord] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([ManagedFootballEventRecord].self, from: data)) ?? []
    }

    private static func decodeManagedGameSaleEventRecords(from data: Data?) -> [ManagedGameSaleEventRecord] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([ManagedGameSaleEventRecord].self, from: data)) ?? []
    }

    private static func decodeManagedGoogleHolidayEventRecords(
        from data: Data?
    ) -> [ManagedGoogleHolidayEventRecord] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([ManagedGoogleHolidayEventRecord].self, from: data)) ?? []
    }

    func refreshNow(reason: CalendarMonitorRefreshReason = .manual) {
        enqueueRefresh(reason: reason)
    }

    func silenceCurrentAlert() {
        guard let activeAlertItem else { return }
        silencedAlertKeys.insert(activeAlertItem.notificationKey)
        self.activeAlertItem = nil
        updateMenuBarState(now: fixedSecondNow(), settings: snapshotSettings())
    }

    func subtitle(for item: UpcomingItem) -> String {
        let now = fixedSecondNow()
        let dateText: String
        if item.kind == .event, let endDate = item.endDate, item.date <= now, endDate > now {
            dateText = "Started \(Self.dayFormatter.string(from: item.date)) at \(Self.timeFormatter.string(from: item.date))"
        } else {
            dateText = "\(Self.dayFormatter.string(from: item.date)) at \(Self.timeFormatter.string(from: item.date))"
        }

        let settings = snapshotSettings()
        let tail: String
        if item.kind == .event, let endDate = item.endDate, item.date <= now, endDate > now {
            switch settings.activeEventDisplayMode {
            case .remaining:
                tail = "\(relativeCountdown(to: endDate, from: now, simplified: settings.useSimplifiedCountdown)) left"
            case .elapsed:
                tail = "started \(elapsedCountdown(from: item.date, to: now, simplified: settings.useSimplifiedCountdown)) ago"
            }
        } else if item.kind == .reminder, item.date <= now {
            tail = "\(elapsedCountdown(from: item.date, to: now, simplified: settings.useSimplifiedCountdown)) ago"
        } else {
            tail = "in \(relativeCountdown(to: item.date, from: now, simplified: settings.useSimplifiedCountdown))"
        }
        return "\(item.kind.rawValue) • \(item.calendarName) • \(dateText) • \(tail)"
    }

    var activeAlertDescription: String? {
        guard let activeAlertItem else { return nil }
        return Self.alertDescription(for: activeAlertItem, now: fixedSecondNow())
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    func fixedSecondNow() -> Date {
        clock.nowRoundedToSecond()
    }

    func markGameSalesRefreshed(at date: Date) {
        lastGameSalesRefreshDate = date
    }

    func markGoogleHolidaysRefreshed(at date: Date) {
        googleHolidayLastRefreshDate = date
    }

    func markFootballRefreshed(at date: Date) {
        lastFootballRefreshDate = date
    }

    func markAstronomyLocationRefreshed(at date: Date) {
        lastAstronomyLocationRefreshDate = date
    }

    func reloadCurrentSettings() {
        let settings = settingsStore.load()
        currentSettings = settings
        prepareFootballNotificationAuthorizationIfNeeded(settings: settings)
        prepareGameSaleNotificationAuthorizationIfNeeded()
    }

    func persistSettings(_ settings: AppSettings) {
        settingsStore.save(settings)
        reloadCurrentSettings()
    }

    func enqueueRefresh(reason: CalendarMonitorRefreshReason = .manual) {
        refreshCoordinator.enqueue(
            reason: reason,
            now: { [weak self] in self?.fixedSecondNow() ?? AlertCalendarClock.nowRoundedToSecond() },
            publishDiagnostics: { [weak self] diagnostics in
                self?.refreshDiagnostics = diagnostics
            },
            refresh: { [weak self] reason in
                await self?.refreshUpcomingItemsImpl(reason: reason)
            }
        )
    }

    func enqueueRefreshAndWait(reason: CalendarMonitorRefreshReason = .manual) async {
        enqueueRefresh(reason: reason)
        await refreshCoordinator.waitForCurrentTask()
    }
}
