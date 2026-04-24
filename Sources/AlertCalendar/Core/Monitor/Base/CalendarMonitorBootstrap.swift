import AppKit
import Combine
import Foundation

extension CalendarMonitor {
    func bootstrap() async {
        await requestCalendarAccess()
        if snapshotSettings().useAutomaticAstronomyLocation {
            await refreshAutomaticAstronomyLocationIfNeeded(trigger: .launch)
        } else {
            astronomyLocationStatus = "Manual coordinates"
        }
        refreshAvailableCalendars()
        await refreshUpcomingItems()
    }

    func registerDefaultSettings() {
        settingsStore.registerDefaults()
    }

    func startObservers() {
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.reloadCurrentSettings()
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
        heartbeatCancellable = Timer.publish(
            every: CalendarMonitorCadence.heartbeatInterval,
            on: .main,
            in: .common
        )
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }

                tickCount += 1
                let now = fixedSecondNow()
                let settings = snapshotSettings()

                evaluateAlert(now: now, settings: settings)
                updateMenuBarState(now: now, settings: settings)
                evaluateSlackStatusSyncOnHeartbeatIfNeeded(now: now, settings: settings)
                scheduleHourlyAutomaticAstronomyLocationRefreshIfNeeded(now: now)

                let periodicRefreshInterval = CalendarMonitorCadence.periodicRefreshInterval
                if hasElapsed(since: lastPeriodicRefreshDate, now: now, interval: periodicRefreshInterval) {
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
