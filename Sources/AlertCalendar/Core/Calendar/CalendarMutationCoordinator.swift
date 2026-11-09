import EventKit
import Foundation

/// Owns the staging/commit boundary. The body is synchronous so another main-actor
/// operation cannot commit, or reset, a half-finished batch across an await.
@MainActor
protocol CalendarEventMutationStore {
    func save(_ event: EKEvent, span: EKSpan, commit: Bool) throws
    func remove(_ event: EKEvent, span: EKSpan, commit: Bool) throws
    func commit() throws
    func reset()
}

@MainActor
struct EventKitCalendarMutationStore: CalendarEventMutationStore {
    let eventStore: EKEventStore

    func save(_ event: EKEvent, span: EKSpan, commit: Bool) throws {
        try eventStore.save(event, span: span, commit: commit)
    }

    func remove(_ event: EKEvent, span: EKSpan, commit: Bool) throws {
        try eventStore.remove(event, span: span, commit: commit)
    }

    func commit() throws { try eventStore.commit() }
    func reset() { eventStore.reset() }
}

@MainActor
final class CalendarMutationBatch {
    private let store: any CalendarEventMutationStore
    private(set) var mutationCount = 0

    fileprivate init(store: any CalendarEventMutationStore) { self.store = store }

    func save(_ event: EKEvent, span: EKSpan = .thisEvent) throws {
        try store.save(event, span: span, commit: false)
        mutationCount += 1
    }

    func remove(_ event: EKEvent, span: EKSpan = .thisEvent) throws {
        try store.remove(event, span: span, commit: false)
        mutationCount += 1
    }
}

@MainActor
final class CalendarMutationCoordinator {
    enum TransactionError: Error {
        case nestedTransaction
        case stagingFailed(Error)
        case commitFailed(Error)
    }
    private let store: any CalendarEventMutationStore
    private var isExecuting = false

    init(store: any CalendarEventMutationStore) { self.store = store }

    /// A returned value is safe to publish only after the staged events commit.
    /// Any staging or commit failure rolls back the whole batch first.
    func perform<Value>(_ operation: (CalendarMutationBatch) throws -> Value) throws -> Value {
        guard !isExecuting else { throw TransactionError.nestedTransaction }
        isExecuting = true
        defer { isExecuting = false }
        let batch = CalendarMutationBatch(store: store)
        let value: Value
        do { value = try operation(batch) }
        catch {
            store.reset()
            throw TransactionError.stagingFailed(error)
        }
        if batch.mutationCount > 0 {
            do { try store.commit() }
            catch {
                store.reset()
                throw TransactionError.commitFailed(error)
            }
        }
        return value
    }
}
