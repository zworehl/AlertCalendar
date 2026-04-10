import AppKit
import Combine
import Foundation

extension CalendarMonitor {
    func bootstrap() async {
        await requestCalendarAccess()
        if defaults.bool(forKey: DefaultsKeys.useAutomaticAstronomyLocation) {
            await refreshAutomaticAstronomyLocationIfNeeded(trigger: .launch)
        } else {
            astronomyLocationStatus = "Manual coordinates"
        }
        refreshAvailableCalendars()
        await refreshUpcomingItems()
    }

    func registerDefaultSettings() {
        defaults.register(defaults: [
            DefaultsKeys.includeEvents: true,
            DefaultsKeys.includeAllDayEvents: true,
            DefaultsKeys.includeReminders: true,
            DefaultsKeys.includeAstronomy: true,
            DefaultsKeys.useAutomaticAstronomyLocation: false,
            DefaultsKeys.astronomyColorID: "blue",
            DefaultsKeys.astronomyLatitude: 18.4655,
            DefaultsKeys.astronomyLongitude: -66.1057,
            DefaultsKeys.weekdayOnlyEventCalendarIDs: [],
            DefaultsKeys.weekdayOnlyReminderCalendarIDs: [],
            DefaultsKeys.lookAheadHours: 24,
            DefaultsKeys.menuBarRotationWindowMinutes: 60,
            DefaultsKeys.alertLeadMinutes: 5,
            DefaultsKeys.concurrentEventRotationSeconds: 30,
            DefaultsKeys.maxListItems: 8,
            DefaultsKeys.enableBlinkAlert: true,
            DefaultsKeys.useSimplifiedCountdown: true,
            DefaultsKeys.activeEventDisplayMode: ActiveEventDisplayMode.remaining.rawValue,
            DefaultsKeys.useEventTitleEllipsis: true,
            DefaultsKeys.eventTitleMaxCharacters: 22,
            DefaultsKeys.menuBarFontSize: 13.0,
            DefaultsKeys.skippedItemKeys: [],
            DefaultsKeys.footballTargetCalendarID: "",
            DefaultsKeys.footballCalendarAlertOption: FootballCalendarAlertOption.none.rawValue,
            DefaultsKeys.showFinishedFootballMatches: true,
            DefaultsKeys.didAutoRecoverEmptyEventCalendarSelection: false,
            DefaultsKeys.didAutoRecoverEmptyReminderCalendarSelection: false,
        ])
    }

    func startObservers() {
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.enqueueRefresh()
            }

        eventStoreObserver = NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.invalidateManagedFootballSnapshotCache(markEventStoreChanged: true)
                self.enqueueRefresh()
            }

        appActivationObserver = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleAutomaticAstronomyLocationRefresh(trigger: .appActivation)
            }

        startWiFiNetworkMonitoring()
    }

    func startHeartbeat() {
        heartbeatCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }

                tickCount += 1
                let now = fixedSecondNow()
                let settings = snapshotSettings()

                evaluateAlert(now: now, settings: settings)
                updateMenuBarState(now: now, settings: settings)
                scheduleHourlyAutomaticAstronomyLocationRefreshIfNeeded(now: now)

                let periodicRefreshInterval: TimeInterval = 5 * 60
                if lastPeriodicRefreshDate == nil || now.timeIntervalSince(lastPeriodicRefreshDate!) >= periodicRefreshInterval {
                    lastPeriodicRefreshDate = now
                    enqueueRefresh()
                } else if shouldRefreshFootballOnHeartbeat(now: now) {
                    enqueueRefresh()
                }
            }
    }

    func requestCalendarAccess() async {
        hasEventsAccess = await requestEventsAccess()
        hasRemindersAccess = await requestRemindersAccess()
        updateAccessDescription()
    }

    func requestEventsAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToEvents { granted, _ in
                    continuation.resume(returning: granted)
                }
            } else {
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func requestRemindersAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToReminders { granted, _ in
                    continuation.resume(returning: granted)
                }
            } else {
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func updateAccessDescription() {
        switch (hasEventsAccess, hasRemindersAccess) {
        case (true, true):
            calendarAccessDescription = "Calendar + Reminders access granted."
        case (true, false):
            calendarAccessDescription = "Calendar events granted. Reminders denied."
        case (false, true):
            calendarAccessDescription = "Reminders granted. Calendar events denied."
        case (false, false):
            calendarAccessDescription = "Calendar and Reminders access denied."
        }
    }
}
