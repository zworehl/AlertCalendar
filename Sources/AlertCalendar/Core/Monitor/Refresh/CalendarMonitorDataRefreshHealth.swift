import Foundation

struct CalendarMonitorDataRefreshHealthState {
    var lastCheckDate: Date?
    var isChecking = false
    var locationError: String?
    var reminderError: String?
    var titleRewriteError: String?
}

extension CalendarMonitor {
    nonisolated static let dataRefreshNotificationID = "data-refresh.health"

    func checkDataRefreshHealthIfNeeded(now: Date) {
        guard !isInitialLoadInProgress, !dataRefreshHealthState.isChecking,
              CalendarMonitorTime.hasElapsed(since: dataRefreshHealthState.lastCheckDate, now: now, interval: 60) else { return }
        dataRefreshHealthState.isChecking = true
        dataRefreshHealthState.lastCheckDate = now
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { dataRefreshHealthState.isChecking = false }
            // Cached sales keep the UI populated during an outage, but still need
            // recovery checks between the regular fifteen-minute refresh passes.
            if await gameSalesClient.hasPendingRefreshFailures {
                await refreshGameSales()
            }
            await updateDataRefreshHealth(now: now)
            // Only failed browse loads retry; the client enforces per-page backoff.
            let failedBrowseIDs = Set(dataRefreshIssues.filter { $0.id.hasPrefix("football.browse.") }.map(\.id))
            for section in footballMenuSections where !section.isLoading && (
                section.errorMessage != nil || failedBrowseIDs.contains("football.browse.\(section.competition.slug)")
            ) {
                await loadFootballCompetitionSection(section.competition, force: false)
            }
            if footballLiveAndNextDaySection.errorMessage != nil {
                await loadFootballLiveAndNextDaySection(force: false)
            }
        }
    }

    func updateDataRefreshHealth(now: Date) async {
        let settings = snapshotSettings()
        let health = DataRefreshHealth.shared
        let states: [(String, String, String?)] = [
            ("calendar.access", "Calendar", (settings.includeEvents || settings.includeAllDayEvents) && !hasEventsAccess
                ? "Calendar access is unavailable. Check macOS permissions." : nil),
            ("reminders", "Reminders", settings.includeReminders
                ? (hasRemindersAccess ? dataRefreshHealthState.reminderError : "Reminders access is unavailable. Check macOS permissions.") : nil),
            ("location", "Astronomy location", settings.useAutomaticAstronomyLocation ? dataRefreshHealthState.locationError : nil),
            ("slack", "Slack", settings.slackConnections.isEmpty ? nil : slackStatusSyncErrorDescription),
            ("holidays.sync", "Holidays", settings.googleHolidayCountryIDs.isEmpty ? nil : googleHolidaySyncErrorDescription),
            ("agenda-summary", "Agenda summary", agendaSummaryGenerationErrorDescription),
            ("title-rewrite", "Event title summaries", settings.rewriteEventTitlesWithAppleIntelligence
                ? dataRefreshHealthState.titleRewriteError : nil)
        ]
        for (source, title, error) in states {
            await health.observe(source: source, title: title, error: error, at: now)
        }
        await health.removeSources(
            withPrefix: "google-holidays.",
            except: Set(settings.googleHolidayCountryIDs.map { "google-holidays.\($0.lowercased())" })
        )
        await health.removeSources(
            withPrefix: "football.auto-add.",
            except: Set(footballAutoAddCompetitionSlugs().map { "football.auto-add.\($0)" })
        )
        await health.removeSources(
            withPrefix: "football.tracked.",
            except: Set(managedFootballEventRecords.map { "football.tracked.\($0.competitionSlug)" })
        )
        let issues = await health.snapshot()
        if dataRefreshIssues != issues { dataRefreshIssues = issues }
        externalFeedDiagnostics = await ExternalFeedMetrics.shared.snapshot()

        let policy = DataRefreshNotificationPolicy(lastNotificationDate: defaults.object(
            forKey: DefaultsKeys.lastDataRefreshNotificationDate
        ) as? Date)
        guard let body = policy.notificationBody(issues: issues, now: now) else {
            if issues.isEmpty { AlertCalendarUserNotifier.removeDeliveredRequests(withIdentifiers: [Self.dataRefreshNotificationID]) }
            return
        }
        if await AlertCalendarUserNotifier.deliver(
            identifier: Self.dataRefreshNotificationID, title: "Some information could not be updated", body: body
        ) {
            defaults.set(now, forKey: DefaultsKeys.lastDataRefreshNotificationDate)
        }
    }
}
