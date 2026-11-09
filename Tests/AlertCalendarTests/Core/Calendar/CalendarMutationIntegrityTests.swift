import EventKit
import Foundation
import XCTest
@testable import AlertCalendar

@MainActor
private final class FailingCalendarMutationStore: CalendarEventMutationStore {
    enum Failure: Error { case save, remove, commit }
    var failSaveAt: Int?
    var failRemoveAt: Int?
    var failCommit = false
    var saveCount = 0
    var removeCount = 0
    var commitCount = 0
    var resetCount = 0
    var pending: [String] = []
    var committed: [String] = []

    func save(_ event: EKEvent, span: EKSpan, commit: Bool) throws {
        XCTAssertFalse(commit, "The coordinator owns the commit boundary")
        saveCount += 1
        if failSaveAt == saveCount { throw Failure.save }
        pending.append("save:\(event.title ?? "")")
    }
    func remove(_ event: EKEvent, span: EKSpan, commit: Bool) throws {
        XCTAssertFalse(commit)
        removeCount += 1
        if failRemoveAt == removeCount { throw Failure.remove }
        pending.append("remove:\(event.title ?? "")")
    }
    func commit() throws {
        commitCount += 1
        if failCommit { throw Failure.commit }
        committed += pending
        pending = []
    }
    func reset() { resetCount += 1; pending = [] }
}

@MainActor
final class CalendarMutationIntegrityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let eventStore = EKEventStore()

    func testFailedSecondRemovalRollsBackFirstAndRetainsAllOwnershipRecords() {
        let store = FailingCalendarMutationStore()
        store.failRemoveAt = 2
        let records = [record("first", age: -200), record("second", age: -200)]
        let events = Dictionary(uniqueKeysWithValues: records.map { ($0.matchID, event(for: $0)) })
        var published = records

        XCTAssertThrowsError(try {
            let result = try cleanup(records, events: events, store: store)
            published = result.records
        }())

        XCTAssertEqual(published, records)
        XCTAssertTrue(store.committed.isEmpty)
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(store.commitCount, 0)
        XCTAssertEqual(store.resetCount, 1)
    }

    func testFailedCommitNeverPublishesSuccessfulLookingCleanup() {
        let store = FailingCalendarMutationStore()
        store.failCommit = true
        let records = [record("expired", age: -200), record("active", age: 1)]
        let events = Dictionary(uniqueKeysWithValues: records.map { ($0.matchID, event(for: $0)) })
        var published = records

        XCTAssertThrowsError(try {
            published = try cleanup(records, events: events, store: store).records
        }())

        XCTAssertEqual(published, records)
        XCTAssertTrue(store.committed.isEmpty)
        XCTAssertTrue(store.pending.isEmpty)
        XCTAssertEqual(store.commitCount, 1)
        XCTAssertEqual(store.resetCount, 1)
    }

    func testSuccessfulCleanupPublishesOnlyCommittedRemovalsAndRetainsUnresolvedEvents() throws {
        let store = FailingCalendarMutationStore()
        let expired = record("expired", age: -200)
        let active = record("active", age: 1)
        let temporarilyMissing = record("missing", age: -200)
        let result = try cleanup(
            [expired, active, temporarilyMissing],
            events: [expired.matchID: event(for: expired), active.matchID: event(for: active)], store: store
        )

        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.records, [active, temporarilyMissing])
        XCTAssertEqual(store.committed, ["remove:expired"])
        XCTAssertEqual(store.commitCount, 1)
        XCTAssertEqual(store.resetCount, 0)
    }

    func testMigrationCannotPublishNewKeeperWhenSaveOrCommitFails() {
        for failDuringSave in [true, false] {
            let store = FailingCalendarMutationStore()
            store.failSaveAt = failDuringSave ? 1 : nil
            store.failCommit = !failDuringSave
            let original = record("migrating", age: 1)
            let keeper = event(for: original)
            keeper.url = original.reference.url
            let duplicate = event(for: original)
            duplicate.title = "duplicate"
            let groups = [[
                ManagedFootballEventSnapshot(event: keeper, reference: original.reference, record: original),
                ManagedFootballEventSnapshot(event: duplicate, reference: original.reference, record: original)
            ]]
            var published = [original]

            XCTAssertThrowsError(try {
                published = try ManagedFootballMutationCoordinator.reconcileGroups(
                    groups, records: [original], clearLegacyURLs: true,
                    mutations: CalendarMutationCoordinator(store: store),
                    refreshedRecord: { _, _ in
                        ManagedFootballEventRecord(
                            matchID: original.matchID, competitionSlug: original.competitionSlug,
                            calendarIdentifier: "new-calendar", eventIdentifier: "new-identifier",
                            eventUID: "new-uid", startDate: original.startDate
                        )
                    }
                )
            }())

            XCTAssertEqual(published, [original])
            XCTAssertTrue(store.committed.isEmpty)
            XCTAssertTrue(store.pending.isEmpty)
            XCTAssertEqual(store.resetCount, 1)
        }
    }

    func testReadOnlyCleanupDoesNotCommitUnrelatedChanges() throws {
        let store = FailingCalendarMutationStore()
        let active = record("active", age: 0)
        let result = try cleanup([active], events: [active.matchID: event(for: active)], store: store)
        XCTAssertEqual(result.records, [active])
        XCTAssertEqual(store.commitCount, 0)
        XCTAssertEqual(store.resetCount, 0)
    }

    func testMigrationReadsFinalIdentifiersAfterCommitAndRetainsKnownAssociationWhenUnavailable() throws {
        let store = FailingCalendarMutationStore()
        let original = record("legacy", age: 1)
        let keeper = event(for: original)
        keeper.url = original.reference.url
        let snapshot = ManagedFootballEventSnapshot(event: keeper, reference: original.reference, record: original)
        let records = try ManagedFootballMutationCoordinator.reconcileGroups(
            [[snapshot]], records: [], clearLegacyURLs: true,
            mutations: CalendarMutationCoordinator(store: store), refreshedRecord: { _, _ in
                XCTAssertEqual(store.commitCount, 1, "Read provider identifiers after the commit")
                return nil
            }
        )
        XCTAssertEqual(records, [original])
        XCTAssertEqual(store.committed, ["save:legacy"])
    }

    private func cleanup(
        _ records: [ManagedFootballEventRecord], events: [String: EKEvent], store: FailingCalendarMutationStore
    ) throws -> ManagedFootballCleanupResult {
        try ManagedFootballMutationCoordinator.removeExpired(
            records: records, now: now, mutations: CalendarMutationCoordinator(store: store),
            resolve: { events[$0.matchID] },
            refreshedRecord: { _, reference in records.first { $0.reference == reference } }
        )
    }

    private func record(_ id: String, age: Int) -> ManagedFootballEventRecord {
        ManagedFootballEventRecord(
            matchID: id, competitionSlug: "eng.1", calendarIdentifier: "fixtures",
            eventIdentifier: "event-\(id)", eventUID: "uid-\(id)", startDate: now.addingTimeInterval(Double(age) * 86_400)
        )
    }

    private func event(for record: ManagedFootballEventRecord) -> EKEvent {
        let event = EKEvent(eventStore: eventStore)
        event.title = record.matchID
        event.startDate = record.startDate
        event.endDate = record.startDate.addingTimeInterval(7_200)
        return event
    }
}
