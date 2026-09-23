import AppKit
import Combine
import EventKit
import Foundation

extension CalendarMonitor {
    func bootstrap() async {
        await refreshFocusCalendarFilterStateFromSystem()
        await requestCalendarAccess()
        await refreshUpcomingItems(reason: .launchSnapshot)

        let settings = snapshotSettings()
        let hasEnabledCalendarSourceAccess =
            (hasEventsAccess && (settings.includeEvents || settings.includeAllDayEvents))
            || (hasRemindersAccess && settings.includeReminders)
        let shouldConfirmMenuBarSnapshot = Self.shouldConfirmInitialMenuBarSnapshot(
            hasEnabledCalendarSourceAccess: hasEnabledCalendarSourceAccess,
            menuBarQueueIsEmpty: unifiedMenuBarQueue(
                now: fixedSecondNow(),
                settings: settings
            ).isEmpty
        )
        let initialReminderTask = reminderRefreshTask

        if shouldConfirmMenuBarSnapshot {
            await initialReminderTask?.value
            eventStore.refreshSourcesIfNecessary()
            await refreshUpcomingItems(reason: .launchConfirmation)
            await refreshCoordinator.waitForCurrentTask()
        }
        finishInitialLoad()
        startDeferredLaunchServices()
    }

    nonisolated static func shouldConfirmInitialMenuBarSnapshot(
        hasEnabledCalendarSourceAccess: Bool,
        menuBarQueueIsEmpty: Bool
    ) -> Bool {
        hasEnabledCalendarSourceAccess && menuBarQueueIsEmpty
    }

    func startDeferredLaunchServices() {
        let settings = snapshotSettings()
        startGameSalesConnectivityRecovery()
        prepareNotificationAuthorizationIfNeeded(settings: settings)
        updateWiFiNetworkMonitoring(isEnabled: settings.useAutomaticAstronomyLocation)

        if settings.useAutomaticAstronomyLocation {
            scheduleAutomaticAstronomyLocationRefresh(trigger: .launch)
        } else {
            astronomyLocationStatus = "Manual coordinates"
        }
        enqueueRefresh(reason: .launch)
    }

    func finishInitialLoad() {
        guard isInitialLoadInProgress else { return }
        isInitialLoadInProgress = false
        let now = fixedSecondNow()
        updateMenuBarState(now: now, settings: snapshotSettings())
    }

    func registerDefaultSettings() {
        settingsStore.registerDefaults()
    }

    func startObservers() {
        startFocusFilterObserver()
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshFocusCalendarFilterStateFromDefaults()
                let settings = self.settingsStore.load()
                guard settings != self.currentSettings else { return }
                self.reloadCurrentSettings(settings)
                self.enqueueRefresh(reason: .settingsChanged)
            }

        eventStoreObserver = NotificationCenter.default.publisher(
            for: .EKEventStoreChanged,
            object: eventStore
        )
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.invalidateManagedFootballSnapshotCache(markEventStoreChanged: true)
                self.synchronizeCalendarState(reason: .eventStoreChanged)
            }

        appActivationObserver = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleFocusFilterRefresh()
                self.synchronizeCalendarStateIfNeeded()
                self.scheduleAutomaticAstronomyLocationRefresh(trigger: .appActivation)
            }

        workspaceResumeObserver = Publishers.Merge3(
            AlertCalendarWorkspace.notificationPublisher(for: NSWorkspace.didWakeNotification),
            AlertCalendarWorkspace.notificationPublisher(for: NSWorkspace.screensDidWakeNotification),
            AlertCalendarWorkspace.notificationPublisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
        )
        .debounce(for: .milliseconds(750), scheduler: RunLoop.main)
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.handleWorkspaceResume()
        }

        terminationObserver = NotificationCenter.default.publisher(
            for: NSApplication.willTerminateNotification
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.flushFootballMatchCache()
        }

    }

    func handleWorkspaceResume() {
        refreshFocusCalendarFilterStateFromDefaults()
        scheduleFocusFilterRefresh()
        reloadCurrentSettings()
        refreshAgendaSummaryAvailability()
        let settings = snapshotSettings()
        let now = fixedSecondNow()
        CalendarMonitorLog.refresh.info("Workspace resumed; refreshing calendar state")
        evaluateAlert(now: now, settings: settings)
        updateMenuBarState(now: now, settings: settings)
        scheduleAutomaticAstronomyLocationRefresh(trigger: .appActivation)
        enqueueRefresh(reason: .workspaceResumed)
    }

    func startHeartbeat() {
        let now = fixedSecondNow()
        lastCalendarStateRefreshDate = lastCalendarStateRefreshDate ?? now
        lastPeriodicRefreshDate = lastPeriodicRefreshDate ?? now
        lastAgendaSummaryAvailabilityCheckDate = lastAgendaSummaryAvailabilityCheckDate ?? now
        restartHeartbeatTask()
    }

    func rescheduleHeartbeat() {
        guard heartbeatTask != nil else { return }
        restartHeartbeatTask()
    }

    private func restartHeartbeatTask() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let now = fixedSecondNow()
                let settings = snapshotSettings()
                let delay = nextHeartbeatInterval(now: now, settings: settings)

                do {
                    try await Task.sleep(nanoseconds: CalendarMonitorTime.nanoseconds(forDelay: delay))
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                performHeartbeat(now: fixedSecondNow(), settings: snapshotSettings())
            }
        }
    }

    private func performHeartbeat(now: Date, settings: AppSettings) {
        checkDataRefreshHealthIfNeeded(now: now)
        if CalendarMonitorTime.hasElapsed(
            since: lastAgendaSummaryAvailabilityCheckDate,
            now: now,
            interval: CalendarMonitorCadence.agendaSummaryAvailabilityRefreshInterval
        ) {
            lastAgendaSummaryAvailabilityCheckDate = now
            refreshAgendaSummaryAvailability()
        }

        evaluateAlert(now: now, settings: settings)
        updateMenuBarState(now: now, settings: settings)
        evaluateSlackStatusSyncOnHeartbeatIfNeeded(now: now, settings: settings)
        scheduleHourlyAutomaticAstronomyLocationRefreshIfNeeded(now: now)

        if CalendarMonitorTime.hasElapsed(
            since: lastCalendarStateRefreshDate,
            now: now,
            interval: CalendarMonitorCadence.calendarStateRefreshInterval
        ) {
            synchronizeCalendarState()
        }

        if CalendarMonitorTime.hasElapsed(
            since: lastPeriodicRefreshDate,
            now: now,
            interval: CalendarMonitorCadence.periodicRefreshInterval
        ) {
            lastPeriodicRefreshDate = now
            enqueueRefresh(reason: .periodic)
        } else if shouldRefreshFootballOnHeartbeat(now: now) {
            enqueueRefresh(reason: .footballHeartbeat)
        }
    }

    func nextHeartbeatInterval(now: Date, settings: AppSettings) -> TimeInterval {
        var delay = nextPresentationRefreshInterval(now: now, settings: settings)

        func includeDeadline(lastDate: Date?, interval: TimeInterval) {
            guard let lastDate else {
                delay = CalendarMonitorCadence.minimumHeartbeatInterval
                return
            }
            let remaining = interval - now.timeIntervalSince(lastDate)
            delay = min(delay, max(CalendarMonitorCadence.minimumHeartbeatInterval, remaining))
        }

        includeDeadline(
            lastDate: lastAgendaSummaryAvailabilityCheckDate,
            interval: CalendarMonitorCadence.agendaSummaryAvailabilityRefreshInterval
        )
        includeDeadline(
            lastDate: lastCalendarStateRefreshDate,
            interval: CalendarMonitorCadence.calendarStateRefreshInterval
        )
        includeDeadline(
            lastDate: lastPeriodicRefreshDate,
            interval: CalendarMonitorCadence.periodicRefreshInterval
        )

        if !managedFootballMatchIDs.isEmpty {
            let trackedMatches = managedFootballMatchIDs.compactMap { footballMatchesByID[$0] }
            let footballInterval = Self.footballManagedRefreshInterval(
                for: trackedMatches,
                hasMissingTrackedMatches: trackedMatches.count < managedFootballMatchIDs.count,
                now: now
            )
            includeDeadline(lastDate: lastFootballManagedSyncDate, interval: footballInterval)
        }

        if settings.appleMusicStatus.isEnabled && !settings.appleMusicStatus.connectionIDs.isEmpty {
            includeDeadline(
                lastDate: lastSlackStatusSyncEvaluationDate,
                interval: CalendarMonitorCadence.appleMusicStatusHeartbeatInterval
            )
        }

        return min(
            max(delay, CalendarMonitorCadence.minimumHeartbeatInterval),
            CalendarMonitorCadence.maximumHeartbeatInterval
        )
    }

    func nextPresentationRefreshInterval(now: Date, settings: AppSettings) -> TimeInterval {
        var delay = CalendarMonitorCadence.maximumHeartbeatInterval
        let secondInMinute = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        delay = min(delay, secondInMinute == 0 ? 60 : 60 - secondInMinute)

        if activeFootballGoalHighlight != nil {
            return CalendarMonitorCadence.minimumHeartbeatInterval
        }

        let alertLeadSeconds = TimeInterval(max(1, settings.alertLeadMinutes) * 60)
        let menuBarWindowSeconds = TimeInterval(max(5, settings.menuBarRotationWindowMinutes) * 60)
        var needsProgressRefresh = false

        for item in upcomingItems + allDayEventItems {
            let travelStart = Self.travelStartDate(for: item)
            let transitionDates = [
                item.date.addingTimeInterval(-alertLeadSeconds),
                item.date.addingTimeInterval(-menuBarWindowSeconds),
                travelStart,
                item.date,
                item.date.addingTimeInterval(Self.timedEventStartAlertDuration),
                item.endDate
            ].compactMap { $0 }

            for transitionDate in transitionDates {
                let remaining = transitionDate.timeIntervalSince(now)
                if remaining > 0 {
                    delay = min(delay, remaining)
                }
            }

            let countdownTargets = [travelStart, item.date, item.endDate].compactMap { $0 }
            if countdownTargets.contains(where: { abs($0.timeIntervalSince(now)) < 60 }) {
                return CalendarMonitorCadence.minimumHeartbeatInterval
            }

            let hasActiveEventProgress = Self.isActiveTimedEvent(item, now: now)
            let hasActiveTravelProgress = travelStart.map { $0 <= now && now < item.date } == true
            needsProgressRefresh = needsProgressRefresh || hasActiveEventProgress || hasActiveTravelProgress
        }

        if needsProgressRefresh {
            delay = min(delay, CalendarMonitorCadence.activeProgressRefreshInterval)
        }

        if let rotationStartedAt = menuBarRotationState.startedAt {
            let rotationInterval = TimeInterval(max(5, settings.concurrentEventRotationSeconds))
            let remaining = rotationInterval - now.timeIntervalSince(rotationStartedAt)
            delay = min(delay, max(CalendarMonitorCadence.minimumHeartbeatInterval, remaining))
        }

        return min(
            max(delay, CalendarMonitorCadence.minimumHeartbeatInterval),
            CalendarMonitorCadence.maximumHeartbeatInterval
        )
    }

    func synchronizeCalendarState(reason: CalendarMonitorRefreshReason = .calendarSync) {
        guard hasEventsAccess || hasRemindersAccess else { return }

        eventStore.refreshSourcesIfNecessary()
        lastCalendarStateRefreshDate = fixedSecondNow()
        enqueueRefresh(reason: reason)
    }

    func synchronizeCalendarStateIfNeeded(
        minimumInterval: TimeInterval = CalendarMonitorCadence.agendaSummaryAvailabilityRefreshInterval
    ) {
        let now = fixedSecondNow()
        guard CalendarMonitorTime.hasElapsed(
            since: lastCalendarStateRefreshDate,
            now: now,
            interval: minimumInterval
        ) else {
            return
        }
        synchronizeCalendarState()
    }

    func setMenuBarAlertAnimationEnabled(_ isEnabled: Bool) {
        if isEnabled {
            guard menuBarAnimationCancellable == nil else { return }
            menuBarAnimationCancellable = Timer.publish(
                every: CalendarMonitorCadence.menuBarAnimationInterval,
                on: .main,
                in: .common
            )
                .autoconnect()
                .sink { [weak self] now in
                    self?.updateMenuBarAlertAnimation(now: now)
                }
            updateMenuBarAlertAnimation(now: Date())
            return
        }

        menuBarAnimationCancellable?.cancel()
        menuBarAnimationCancellable = nil
    }

    func updateMenuBarAlertAnimation(now: Date) {
        guard currentSettings.enableBlinkAlert,
              combinedMenuBarAlertedSegmentIndex != nil
        else {
            setMenuBarAlertAnimationEnabled(false)
            setIfChanged(\.combinedMenuBarAlertTextOpacity, to: 0)
            menuBarPresentationModel.setAlertTextOpacity(0)
            return
        }

        let opacity = Self.alertBlinkTextOpacity(now: now)
        setIfChanged(\.combinedMenuBarAlertTextOpacity, to: opacity)
        menuBarPresentationModel.setAlertTextOpacity(opacity)
    }

    func requestCalendarAccess() async {
        hasEventsAccess = await requestEventsAccess()
        hasRemindersAccess = await requestRemindersAccess()
        updateAccessDescription()
    }

    func requestEventsAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if Self.hasFullEventKitAccess(status) {
            return true
        }
        guard status == .notDetermined || Self.hasWriteOnlyEventKitAccess(status) else {
            return false
        }
        CalendarMonitorLog.refresh.info(
            "Requesting Calendar access from status \(status.rawValue, privacy: .public)"
        )
        return await withCheckedContinuation { continuation in
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
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if Self.hasFullEventKitAccess(status) {
            return true
        }
        guard status == .notDetermined else {
            return false
        }
        CalendarMonitorLog.refresh.info(
            "Requesting Reminders access from status \(status.rawValue, privacy: .public)"
        )
        return await withCheckedContinuation { continuation in
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

    nonisolated static func hasFullEventKitAccess(_ status: EKAuthorizationStatus) -> Bool {
        if status == .authorized {
            return true
        }
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        }
        return false
    }

    nonisolated static func hasWriteOnlyEventKitAccess(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .writeOnly
        }
        return false
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
