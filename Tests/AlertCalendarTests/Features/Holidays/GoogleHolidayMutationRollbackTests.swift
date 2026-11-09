import EventKit
import XCTest
@testable import AlertCalendar

final class GoogleHolidayMutationRollbackTests: XCTestCase {
    @MainActor
    func testStagingFailureCannotLeakHolidayWritesIntoNextCalendarTransaction() throws {
        let store = Store()
        let eventStore = EKEventStore()
        let first = EKEvent(eventStore: eventStore)
        first.title = "first holiday"
        let second = EKEvent(eventStore: eventStore)
        second.title = "failing holiday"
        try CalendarMonitor.withGoogleHolidayRollback({ try store.save(first, span: .thisEvent, commit: false) }, rollback: { store.reset() })
        store.failSave = true
        XCTAssertThrowsError(try CalendarMonitor.withGoogleHolidayRollback({
            try store.save(second, span: .thisEvent, commit: false)
        }, rollback: { store.reset() }))
        store.failSave = false
        let alert = EKEvent(eventStore: eventStore)
        alert.title = "calendar alert"
        try CalendarMutationCoordinator(store: store).perform { try $0.save(alert) }
        XCTAssertEqual(store.committed, [["calendar alert"]])
        XCTAssertEqual(store.resets, 1)
    }

    @MainActor
    func testCommitFailureDiscardsItsBatchBeforeAnotherWriterStarts() throws {
        let store = Store()
        let eventStore = EKEventStore()
        let holiday = EKEvent(eventStore: eventStore)
        holiday.title = "holiday"
        try store.save(holiday, span: .thisEvent, commit: false)
        store.failCommit = true
        XCTAssertThrowsError(try CalendarMonitor.withGoogleHolidayRollback({ try store.commit() }, rollback: { store.reset() }))
        store.failCommit = false
        let next = EKEvent(eventStore: eventStore)
        next.title = "next writer"
        try CalendarMutationCoordinator(store: store).perform { try $0.save(next) }
        XCTAssertEqual(store.committed, [["next writer"]])
        XCTAssertEqual(store.resets, 1)
    }

    @MainActor
    private final class Store: CalendarEventMutationStore {
        enum Failure: Error { case injected }
        var pending: [String] = []
        var committed: [[String]] = []
        var failSave = false
        var failCommit = false
        var resets = 0
        func save(_ event: EKEvent, span: EKSpan, commit: Bool) throws {
            pending.append(event.title ?? "")
            if failSave { throw Failure.injected }
        }
        func remove(_ event: EKEvent, span: EKSpan, commit: Bool) throws { }
        func commit() throws {
            if failCommit { throw Failure.injected }
            committed.append(pending)
            pending.removeAll()
        }
        func reset() { resets += 1; pending.removeAll() }
    }
}
