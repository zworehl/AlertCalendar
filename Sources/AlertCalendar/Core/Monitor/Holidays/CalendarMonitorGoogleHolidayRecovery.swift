import Foundation

extension CalendarMonitor {
    /// Staging and commit stay synchronous on the main actor. On failure the
    /// current uncommitted batch is discarded before another writer can run.
    nonisolated static func withGoogleHolidayRollback<Value>(
        _ operation: () throws -> Value, rollback: () -> Void
    ) throws -> Value {
        do { return try operation() }
        catch { rollback(); throw error }
    }

    func queueGoogleHolidayRefresh(force: Bool) {
        googleHolidayState.refreshRequested = true
        googleHolidayState.forceRefreshRequested = googleHolidayState.forceRefreshRequested || force
    }

    func finishGoogleHolidayRefresh() {
        isSyncingGoogleHolidays = false
        guard googleHolidayState.refreshRequested else { return }
        let force = googleHolidayState.forceRefreshRequested
        googleHolidayState.refreshRequested = false
        googleHolidayState.forceRefreshRequested = false
        Task { @MainActor [weak self] in await self?.refreshGoogleHolidays(forceRefresh: force) }
    }

    func ensureGoogleHolidayRequestIsCurrent(_ settings: AppSettings) throws {
        try Task.checkCancellation()
        guard hasEventsAccess, Self.googleHolidayRequestMatchesSettings(settings, current: snapshotSettings()) else {
            queueGoogleHolidayRefresh(force: true)
            throw CancellationError()
        }
    }

    nonisolated static func googleHolidayRequestMatchesSettings(_ captured: AppSettings, current: AppSettings) -> Bool {
        captured.googleHolidayTargetCalendarID == current.googleHolidayTargetCalendarID
            && GoogleHolidayCountry.normalizedCountryIDs(captured.googleHolidayCountryIDs)
                == GoogleHolidayCountry.normalizedCountryIDs(current.googleHolidayCountryIDs)
    }

    /// Recover the last applied representation when a failed country has no
    /// downloadable cache (for example after upgrading or losing the cache file).
    nonisolated static func preservingUnavailableHolidaySources(
        _ fetched: [GoogleHolidaySourceEvent], records: [ManagedGoogleHolidayEventRecord], failedCountryIDs: Set<String>
    ) -> [GoogleHolidaySourceEvent] {
        fetched + records.flatMap { record in
            record.holiday.countryIDs.filter { failedCountryIDs.contains($0) }.map { id in
                GoogleHolidaySourceEvent(
                    sourceUID: record.holiday.sourceUIDs.first ?? record.holiday.id,
                    countryID: id, title: record.holiday.title,
                    startDate: record.holiday.startDate, endDateExclusive: record.holiday.endDateExclusive
                )
            }
        }
    }
}
