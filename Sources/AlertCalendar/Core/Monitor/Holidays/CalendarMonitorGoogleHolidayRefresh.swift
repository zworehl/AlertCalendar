import EventKit
import Foundation

extension CalendarMonitor {
    func refreshGoogleHolidays(forceRefresh: Bool = false) async {
        guard !isSyncingGoogleHolidays else {
            queueGoogleHolidayRefresh(force: forceRefresh)
            return
        }
        let forceRefresh = forceRefresh || googleHolidayState.forceRefreshRequested
        googleHolidayState.refreshRequested = false
        googleHolidayState.forceRefreshRequested = false

        let settings = snapshotSettings()
        let countryIDs = GoogleHolidayCountry.normalizedCountryIDs(settings.googleHolidayCountryIDs)

        guard hasEventsAccess else {
            googleHolidaySyncErrorDescription = nil
            return
        }

        guard !countryIDs.isEmpty else {
            googleHolidaySyncErrorDescription = nil
            if forceRefresh || !managedGoogleHolidayEventRecords.isEmpty {
                isSyncingGoogleHolidays = true
                defer { finishGoogleHolidayRefresh() }
                await removeAllManagedGoogleHolidayEvents(expectedSettings: settings)
                defaults.set(
                    Self.currentGoogleHolidayIdentityVersion,
                    forKey: DefaultsKeys.googleHolidayIdentityVersion
                )
            }
            return
        }

        guard let targetCalendar = resolvedGoogleHolidayTargetCalendar(settings: settings) else {
            googleHolidaySyncErrorDescription = nil
            return
        }

        let now = fixedSecondNow()
        let calendar = holidayCalendar()
        let requiresIdentityMigration =
            defaults.integer(forKey: DefaultsKeys.googleHolidayIdentityVersion)
                < Self.currentGoogleHolidayIdentityVersion
            || managedGoogleHolidayEventRecords.contains { record in
                record.holiday.id != GoogleHolidayMerger.semanticKey(
                    title: record.holiday.title,
                    startDate: record.holiday.startDate,
                    calendar: calendar
                )
        }
        guard shouldRefreshGoogleHolidays(
            now: now,
            forceRefresh: forceRefresh || requiresIdentityMigration
        ) else {
            return
        }

        isSyncingGoogleHolidays = true
        defer { finishGoogleHolidayRefresh() }
        lastGoogleHolidayRefreshAttemptDate = now
        googleHolidaySyncErrorDescription = nil

        do {
            let result = try await googleHolidayClient.fetchHolidayLoadResult(
                countryIDs: countryIDs,
                now: now,
                forceRefresh: forceRefresh
            )
            try ensureGoogleHolidayRequestIsCurrent(settings)
            let sources = Self.preservingUnavailableHolidaySources(
                result.events, records: managedGoogleHolidayEventRecords, failedCountryIDs: result.failedCountryIDs
            )
            let inWindow = sources.filter { googleHolidaySyncWindowContains($0, now: now) }
            let merged = GoogleHolidayMerger.merge(inWindow, calendar: calendar)
            try await reconcileGoogleHolidayEvents(
                merged,
                targetCalendar: targetCalendar,
                allowsDeletion: result.isComplete,
                expectedSettings: settings
            )
            googleHolidayState.lastAttemptFailed = !result.isComplete
            googleHolidaySyncErrorDescription = result.warning
            for id in countryIDs.subtracting(result.failedCountryIDs) {
                await ExternalFeedMetrics.shared.recordAppliedData(source: "google-holidays.\(id.lowercased())", at: now)
            }
            ensureGoogleHolidayTargetCalendarIsSelected(targetCalendar.calendarIdentifier)
            if result.isComplete {
                markGoogleHolidaysRefreshed(at: now)
                defaults.set(now, forKey: DefaultsKeys.googleHolidayLastRefreshDate)
            }
            defaults.set(
                Self.currentGoogleHolidayIdentityVersion,
                forKey: DefaultsKeys.googleHolidayIdentityVersion
            )
        } catch is CancellationError {
            return
        } catch {
            googleHolidayState.lastAttemptFailed = true
            googleHolidaySyncErrorDescription = AlertCalendarLanguage.errorMessage(error)
        }
    }

    private func shouldRefreshGoogleHolidays(
        now: Date,
        forceRefresh: Bool
    ) -> Bool {
        GoogleHolidayRefreshPolicy.isDue(
            lastRefreshDate: googleHolidayLastRefreshDate,
            lastAttemptDate: lastGoogleHolidayRefreshAttemptDate,
            now: now,
            forceRefresh: forceRefresh,
            lastAttemptFailed: googleHolidayState.lastAttemptFailed
        )
    }

}
