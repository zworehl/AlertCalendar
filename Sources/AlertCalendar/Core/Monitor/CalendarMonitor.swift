import AppKit
import Combine
import CoreLocation
import EventKit
import Foundation

extension EKReminder: @retroactive @unchecked Sendable {}

@MainActor
final class CalendarMonitor: ObservableObject {
    @Published var combinedMenuBarLabel = "No upcoming items"
    @Published var combinedMenuBarColor: NSColor = .systemGray
    @Published var combinedMenuBarAlertedSegmentIndex: Int?
    @Published var combinedMenuBarAlertTextOpacity: CGFloat = 0
    @Published var combinedMenuBarDotColors: [NSColor] = [.systemGray]
    @Published var combinedMenuBarMarkerStyles: [MenuMarkerStyle] = [.color(.systemGray)]
    @Published var combinedMenuBarSegments: [String] = ["No upcoming items"]
    @Published var combinedMenuBarSegmentBackgroundColors: [NSColor] = [.clear]
    @Published var combinedMenuBarSegmentBackgroundProgresses: [CGFloat] = [0]
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

    let eventStore = EKEventStore()
    let defaults = UserDefaults.standard

    var heartbeatCancellable: AnyCancellable?
    var defaultsObserver: AnyCancellable?
    var eventStoreObserver: AnyCancellable?
    var refreshQueueTask: Task<Void, Never>?
    var isRefreshRunning = false
    var hasPendingRefresh = false
    var tickCount = 0
    var lastPeriodicRefreshDate: Date?
    var blinkPhase = false
    var hasEventsAccess = false
    var hasRemindersAccess = false
    var birthdayCalendarIDs: Set<String> = []
    var allDayEventItems: [UpcomingItem] = []
    var alreadyNotified: Set<String> = []
    var silencedAlertKeys: Set<String> = []
    var skippedItemKeys: Set<String> = []
    var cachedWeatherItem: UpcomingItem?
    var lastWeatherFetchDate: Date?
    var weatherCacheSignature: String?
    var oneShotLocationManager: CLLocationManager?
    var oneShotLocationDelegate: OneShotLocationDelegate?
    var locationPermissionManager: CLLocationManager?
    var locationPermissionDelegate: LocationPermissionDelegate?

    init() {
        registerDefaultSettings()
        skippedItemKeys = Set(defaults.stringArray(forKey: DefaultsKeys.skippedItemKeys) ?? [])
        startObservers()
        startHeartbeat()

        Task {
            await bootstrap()
        }
    }

    func refreshNow() {
        enqueueRefresh()
    }

    func silenceCurrentAlert() {
        guard let activeAlertItem else { return }
        silencedAlertKeys.insert(activeAlertItem.notificationKey)
        self.activeAlertItem = nil
        blinkPhase = false
        updateMenuBarState(now: Date(), settings: snapshotSettings())
    }

    func subtitle(for item: UpcomingItem) -> String {
        let now = Date()
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
        } else if item.kind == .weather, let endDate = item.endDate, endDate > item.date {
            if item.date <= now, endDate > now {
                let elapsed = elapsedCountdown(from: item.date, to: now, simplified: settings.useSimplifiedCountdown)
                let remaining = relativeCountdown(to: endDate, from: now, simplified: settings.useSimplifiedCountdown)
                tail = "\(elapsed) elapsed • \(remaining) left"
            } else if item.date > now {
                let duration = relativeCountdown(to: endDate, from: item.date, simplified: settings.useSimplifiedCountdown)
                tail = "in \(relativeCountdown(to: item.date, from: now, simplified: settings.useSimplifiedCountdown)) • for \(duration)"
            } else {
                tail = "\(elapsedCountdown(from: item.date, to: endDate, simplified: settings.useSimplifiedCountdown)) total"
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
        let seconds = max(0, Int(activeAlertItem.date.timeIntervalSince(Date())))
        if seconds < 60 {
            return "\(activeAlertItem.title) starts in \(seconds)s."
        }
        let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))
        return "\(activeAlertItem.title) starts in \(minutes) minute\(minutes == 1 ? "" : "s")."
    }

    struct SettingsSnapshot {
        let includeEvents: Bool
        let includeAllDayEvents: Bool
        let includeReminders: Bool
        let includeWeather: Bool
        let includeAstronomy: Bool
        let useAutomaticAstronomyLocation: Bool
        let astronomyColorID: String
        let astronomyLatitude: Double
        let astronomyLongitude: Double
        let selectedEventCalendarIDs: Set<String>
        let selectedReminderCalendarIDs: Set<String>
        let weekdayOnlyEventCalendarIDs: Set<String>
        let weekdayOnlyReminderCalendarIDs: Set<String>
        let lookAheadHours: Int
        let alertLeadMinutes: Int
        let nearUpcomingAlternateMinutes: Int
        let concurrentEventRotationSeconds: Int
        let enableBlinkAlert: Bool
        let useSimplifiedCountdown: Bool
        let activeEventDisplayMode: ActiveEventDisplayMode
        let useEventTitleEllipsis: Bool
        let eventTitleMaxCharacters: Int
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
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    }

    func enqueueRefresh() {
        hasPendingRefresh = true
        guard !isRefreshRunning else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            self.isRefreshRunning = true
            defer {
                self.isRefreshRunning = false
                self.refreshQueueTask = nil
            }

            while self.hasPendingRefresh {
                self.hasPendingRefresh = false
                await self.refreshUpcomingItemsImpl()
            }
        }
        refreshQueueTask = task
    }

    func enqueueRefreshAndWait() async {
        enqueueRefresh()
        await refreshQueueTask?.value
    }
}
