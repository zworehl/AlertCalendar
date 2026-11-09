import EventKit
import Foundation

struct ManagedFootballCleanupResult {
    let records: [ManagedFootballEventRecord]
    let removedCount: Int
}

/// Builds ownership changes inside the same transaction as the Calendar changes.
/// The monitor publishes the returned records only when the commit succeeds.
@MainActor
enum ManagedFootballMutationCoordinator {
    static func removeExpired(
        records: [ManagedFootballEventRecord],
        now: Date,
        mutations: CalendarMutationCoordinator,
        resolve: (ManagedFootballEventRecord) -> EKEvent?,
        refreshedRecord: (EKEvent, ManagedFootballFixtureReference) -> ManagedFootballEventRecord?
    ) throws -> ManagedFootballCleanupResult {
        try mutations.perform { batch in
            var survivors: [ManagedFootballEventRecord] = []
            var removedCount = 0
            for record in records {
                guard let event = resolve(record) else {
                    // A temporary provider/read failure is not proof of deletion.
                    survivors.append(record)
                    continue
                }
                let start = event.startDate ?? record.startDate
                if CalendarMonitor.isManagedFootballEventWithinSuggestionWindow(startDate: start, now: now) {
                    survivors.append(refreshedRecord(event, record.reference) ?? record)
                } else {
                    try batch.remove(event)
                    removedCount += 1
                }
            }
            return ManagedFootballCleanupResult(records: survivors, removedCount: removedCount)
        }
    }

    static func reconcileGroups(
        _ groups: [[ManagedFootballEventSnapshot]],
        records: [ManagedFootballEventRecord],
        clearLegacyURLs: Bool,
        replaceExistingRecords: Bool = true,
        mutations: CalendarMutationCoordinator,
        refreshedRecord: (EKEvent, ManagedFootballFixtureReference) -> ManagedFootballEventRecord?
    ) throws -> [ManagedFootballEventRecord] {
        let keepers = try mutations.perform { batch in
            var keepers: [ManagedFootballEventSnapshot] = []
            for group in groups {
                guard let keeper = group.first else { continue }
                if clearLegacyURLs, keeper.event.url != nil {
                    keeper.event.url = nil
                    try batch.save(keeper.event)
                }
                keepers.append(keeper)
                for duplicate in group.dropFirst() { try batch.remove(duplicate.event) }
            }
            return keepers
        }
        var byReference = Dictionary(records.map { ($0.reference, $0) }, uniquingKeysWith: { _, newer in newer })
        for keeper in keepers where replaceExistingRecords || byReference[keeper.reference] == nil {
            // EventKit can finalize identifiers during commit. Keep the original
            // known association if the refreshed object cannot be read yet.
            byReference[keeper.reference] = refreshedRecord(keeper.event, keeper.reference) ?? keeper.record
        }
        return Array(byReference.values)
    }
}

extension CalendarMonitor {
    func reportFootballCalendarMutation(source: String, error: Error?) {
        let detail: String?
        if let error {
            footballState.managedRefreshFailed = true
            invalidateManagedFootballSnapshotCache()
            detail = L10n.text("Calendar changes could not be saved. Existing managed events are still tracked.")
            calendarAccessDescription = detail ?? ""
            CalendarMonitorLog.football.error("Football calendar mutation failed: \(String(describing: error), privacy: .private)")
        } else {
            detail = nil
        }
        Task {
            await DataRefreshHealth.shared.record(
                source: source, title: L10n.text("Football calendar updates"), error: detail
            )
        }
    }
}
