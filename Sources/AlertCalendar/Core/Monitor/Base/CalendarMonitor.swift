import AppKit
import Combine
import EventKit
import Foundation

extension EKReminder: @retroactive @unchecked Sendable {}

@MainActor
final class CalendarMonitor: ObservableObject {
    @Published var isInitialLoadInProgress = true {
        didSet {
            menuBarPresentationModel.setInitialLoading(isInitialLoadInProgress)
        }
    }
    let menuBarPresentationModel = MenuBarPresentationModel()
    var combinedMenuBarLabel = "Loading..."
    var combinedMenuBarColor: NSColor = .systemGray
    var combinedMenuBarAlertedSegmentIndex: Int?
    var combinedMenuBarAlertTextOpacity: CGFloat = 0
    var combinedMenuBarDotColors: [NSColor] = [.systemGray]
    var combinedMenuBarMarkerStyles: [MenuMarkerStyle] = [.color(.systemGray)]
    var combinedMenuBarSegments: [String] = ["Loading..."]
    var combinedMenuBarSegmentBackgroundColors: [NSColor] = [.clear]
    var combinedMenuBarSegmentBackgroundProgresses: [CGFloat] = [0]
    var combinedMenuBarSegmentParticipationStatuses: [EventParticipationStatus?] = [nil]
    var combinedMenuBarSegmentTextureStatuses: [EventParticipationStatus?] = [nil]
    var combinedMenuBarSegmentAccessorySymbolNames: [[String]] = [[]]
    var combinedMenuBarFootballDisplay: FootballMenuBarDisplay?
    var combinedMenuBarFootballTrailingText: String?
    var combinedMenuBarFootballStatusText: String?
    var combinedMenuBarFootballStatusColor: NSColor = .systemGreen
    var combinedMenuBarFootballGoalHighlightSide: FootballScoreSide?
    var combinedMenuBarFootballGoalHighlightTextOpacity: CGFloat = 0
    @Published var hasEventsAccess = false
    @Published var hasRemindersAccess = false
    @Published var availableEventCalendars: [AvailableCalendar] = []
    @Published var availableReminderCalendars: [AvailableCalendar] = []
    var eventsMenuBarLabel = "No events"
    var remindersMenuBarLabel = "No reminders"
    var eventsMenuBarColor: NSColor = .systemGray
    var remindersMenuBarColor: NSColor = .systemGray
    @Published var upcomingItems: [UpcomingItem] = []
    @Published var activeAlertItem: UpcomingItem?
    @Published var calendarAccessDescription = "Requesting access..."
    @Published var astronomyLocationStatus = "Manual coordinates"
    @Published var lastRefreshDate: Date?
    @Published var refreshDiagnostics = CalendarMonitorRefreshDiagnostics()
    @Published var externalFeedDiagnostics = ExternalFeedDiagnostics()
    @Published var dataRefreshIssues: [DataRefreshIssue] = []
    var dataRefreshHealthState = CalendarMonitorDataRefreshHealthState()
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
    @Published var agendaSummaryState = AgendaSummaryState.idle
    @Published var agendaSummaryAvailability = AgendaSummaryAvailability.unsupportedSystem
    @Published var agendaSummaryGenerationErrorDescription: String?
    @Published var rewrittenEventTitlesByItemKey: [String: String] = [:]
    @Published private(set) var currentSettings = AppSettings.defaults

    let eventStore: EKEventStore
    let defaults: UserDefaults
    let footballClient: FootballDataAPIClient
    let footballImageStore: FootballImageStore
    let gameSalesClient: GameSalesFeedClient
    let googleHolidayClient: GoogleHolidayFeedClient
    let slackClient: SlackAPIClient
    let agendaSummaryClient: any AgendaSummaryGenerating
    let agendaSummaryAttachmentPreviewProvider: any AgendaSummaryAttachmentPreviewProviding
    let agendaSummaryLinkPreviewProvider: any AgendaSummaryLinkPreviewProviding
    let eventTitleRewriter: any EventTitleRewriting
    let eventMailContextProvider: any EventMailContextProviding
    let clock: AlertCalendarClockProviding
    let footballMatchCacheStore: FootballMatchCacheStore?
    let eventTitleRewriteCacheStore: EventTitleRewriteCacheStore?

    var settingsStore: AppSettingsStore {
        AppSettingsStore(defaults: defaults)
    }

    var heartbeatTask: Task<Void, Never>?
    var menuBarAnimationCancellable: AnyCancellable?
    @Published var activeFocusCalendarFilterState: FocusCalendarFilterState?
    var focusFilterRuntime = FocusFilterRuntimeState()
    var defaultsObserver: AnyCancellable?
    var eventStoreObserver: AnyCancellable?
    var appActivationObserver: AnyCancellable?
    var workspaceResumeObserver: AnyCancellable?
    var terminationObserver: AnyCancellable?
    let refreshCoordinator = CalendarMonitorRefreshCoordinator()
    var lastCalendarStateRefreshDate: Date?
    var lastPeriodicRefreshDate: Date?
    var lastAgendaSummaryAvailabilityCheckDate: Date?
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
    var agendaSummaryTask: Task<Void, Never>?
    var agendaSummaryRetryTask: Task<Void, Never>?
    var agendaSummaryRetryAttempt = 0
    var agendaSummaryRequestFingerprint: Int?
    var eventTitleRewriteTask: Task<Void, Never>?
    var eventTitleRewriteRetryTask: Task<Void, Never>?
    var eventTitleRewriteRetryAttempt = 0
    var eventTitleRewriteFingerprint: Int?
    var notificationAuthorizationTask: Task<Void, Never>?
    var persistentEventTitleRewriteCache = EventTitleRewriteCacheSnapshot.empty
    var virtualLocationTextCache = AlertCalendarLRUCache<String, Bool>(capacity: 256)
    var lastSuccessfulReminderItems: [UpcomingItem] = []
    var reminderRefreshTask: Task<Void, Never>?
    var reminderRefreshToken: UUID?
    var reminderRefreshFingerprint: String?

    init(
        eventStore: EKEventStore = EKEventStore(),
        defaults: UserDefaults = .standard,
        footballClient: FootballDataAPIClient = FootballDataAPIClient(),
        footballImageStore: FootballImageStore = FootballImageStore(),
        gameSalesClient: GameSalesFeedClient = GameSalesFeedClient(),
        googleHolidayClient: GoogleHolidayFeedClient = GoogleHolidayFeedClient(),
        slackClient: SlackAPIClient = SlackAPIClient(),
        agendaSummaryClient: any AgendaSummaryGenerating = AppleIntelligenceAgendaSummaryClient(),
        agendaSummaryAttachmentPreviewProvider: any AgendaSummaryAttachmentPreviewProviding = AgendaSummaryAttachmentPreviewClient(),
        agendaSummaryLinkPreviewProvider: any AgendaSummaryLinkPreviewProviding = AgendaSummaryLinkPreviewClient(),
        eventTitleRewriter: any EventTitleRewriting = AppleIntelligenceEventTitleRewriter(),
        eventMailContextProvider: any EventMailContextProviding = AppleMailEventContextProvider(),
        clock: AlertCalendarClockProviding = SystemAlertCalendarClock(),
        footballMatchCacheStore: FootballMatchCacheStore? = nil,
        eventTitleRewriteCacheStore: EventTitleRewriteCacheStore? = nil
    ) {
        self.eventStore = eventStore
        self.defaults = defaults
        self.footballClient = footballClient
        self.footballImageStore = footballImageStore
        self.gameSalesClient = gameSalesClient
        self.googleHolidayClient = googleHolidayClient
        self.slackClient = slackClient
        self.agendaSummaryClient = agendaSummaryClient
        self.agendaSummaryAttachmentPreviewProvider = agendaSummaryAttachmentPreviewProvider
        self.agendaSummaryLinkPreviewProvider = agendaSummaryLinkPreviewProvider
        self.eventTitleRewriter = eventTitleRewriter
        self.eventMailContextProvider = eventMailContextProvider
        self.clock = clock
        self.footballMatchCacheStore = footballMatchCacheStore
            ?? (defaults === UserDefaults.standard ? FootballMatchCacheStore.defaultStore() : nil)
        self.eventTitleRewriteCacheStore = eventTitleRewriteCacheStore
            ?? (defaults === UserDefaults.standard ? EventTitleRewriteCacheStore.defaultStore() : nil)
        if let cachedTitles = self.eventTitleRewriteCacheStore?.load() {
            persistentEventTitleRewriteCache = cachedTitles
        }
        self.agendaSummaryAvailability = agendaSummaryClient.availability

        registerDefaultSettings()
        activeFocusCalendarFilterState = FocusCalendarFilterStateStore.load(defaults: defaults)
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
        if let footballCache = self.footballMatchCacheStore?.load(now: clock.nowRoundedToSecond()) {
            footballMatchesByID = Dictionary(
                footballCache.matches.map { ($0.id, $0) },
                uniquingKeysWith: { _, newest in newest }
            )
            lastFootballRefreshDate = footballCache.fetchedAt
        }
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
        if item.isDateOnlyReminder {
            dateText = Self.dayFormatter.string(from: item.date)
        } else if item.kind == .event, let endDate = item.endDate, item.date <= now, endDate > now {
            dateText = "Started \(Self.dayFormatter.string(from: item.date)) at \(Self.timeFormatter.string(from: item.date))"
        } else {
            dateText = "\(Self.dayFormatter.string(from: item.date)) at \(Self.timeFormatter.string(from: item.date))"
        }

        let settings = snapshotSettings()
        let tail: String
        if item.isDateOnlyReminder {
            tail = AlertCalendarRelativeTimeFormatter.calendarDayRelativeText(
                for: item.date,
                relativeTo: now
            )
        } else if item.kind == .event, let endDate = item.endDate, item.date <= now, endDate > now {
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

    func reloadCurrentSettings(_ loadedSettings: AppSettings? = nil) {
        let settings = loadedSettings ?? settingsStore.load()
        let shouldInvalidateAgendaSummary = currentSettings.showAgendaSummary != settings.showAgendaSummary
            || currentSettings.agendaSummaryMaximumWords != settings.agendaSummaryMaximumWords
            || currentSettings.useLinkedPagePreviewsInAgendaSummary != settings.useLinkedPagePreviewsInAgendaSummary
        currentSettings = settings
        if shouldInvalidateAgendaSummary {
            cancelAgendaSummary()
        }
        if !isInitialLoadInProgress {
            prepareNotificationAuthorizationIfNeeded(settings: settings)
            updateWiFiNetworkMonitoring(isEnabled: settings.useAutomaticAstronomyLocation)
        }
    }

    func persistSettings(_ settings: AppSettings) {
        settingsStore.save(settings)
        reloadCurrentSettings()
    }

    @discardableResult
    func enqueueRefresh(reason: CalendarMonitorRefreshReason = .manual) -> Int {
        refreshCoordinator.enqueue(
            reason: reason,
            now: { [weak self] in self?.fixedSecondNow() ?? AlertCalendarClock.nowRoundedToSecond() },
            publishDiagnostics: { [weak self] diagnostics in
                self?.refreshDiagnostics = diagnostics
            },
            refreshReasons: { [weak self] reasons in
                await self?.refreshUpcomingItemsImpl(reasons: reasons)
                    ?? CalendarMonitorRefreshExecutionReport()
            }
        )
    }

    func enqueueRefreshAndWait(reason: CalendarMonitorRefreshReason = .manual) async {
        let requestID = enqueueRefresh(reason: reason)
        await refreshCoordinator.waitForRequest(requestID)
    }
}
