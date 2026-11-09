import Foundation
import XCTest
@testable import AlertCalendar

@MainActor
final class CalendarAlertFullSyncCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testPerEventFailureCheckpointsOtherWindowsAndRetriesOnlyFailedWindowAfterRelaunch() async {
        let defaults = makeDefaults()
        let first = CalendarAlertFullSyncCoordinator(defaults: defaults)
        var attempted: [Int] = []
        let initial = await first.run(fingerprint: "rules", windowCount: 3, now: { now }) { index in
            attempted.append(index)
            return index == 1 ? .init(failureCount: 1) : .init(updatedCount: 1)
        }

        XCTAssertFalse(initial.isComplete)
        XCTAssertEqual(attempted, [0, 1, 2])
        XCTAssertFalse(first.isComplete(fingerprint: "rules"))
        XCTAssertEqual(first.checkpoint(fingerprint: "rules", windowCount: 3).completedWindows, [0, 2])
        XCTAssertEqual(initial.nextRetryAt, now.addingTimeInterval(60))

        let restored = CalendarAlertFullSyncCoordinator(defaults: defaults)
        attempted = []
        let recovered = await restored.run(fingerprint: "rules", windowCount: 3, now: { now.addingTimeInterval(60) }) {
            attempted.append($0)
            return .init(updatedCount: 1)
        }
        XCTAssertEqual(attempted, [1])
        XCTAssertTrue(recovered.isComplete)
        XCTAssertTrue(restored.isComplete(fingerprint: "rules"))
        XCTAssertNil(defaults.data(forKey: CalendarAlertFullSyncCoordinator.checkpointKey))
    }

    func testCommitFailureStopsPassWithoutCompletingFailedOrUnvisitedWindows() async {
        let coordinator = CalendarAlertFullSyncCoordinator(defaults: makeDefaults())
        var attempted: [Int] = []
        let initial = await coordinator.run(fingerprint: "rules", windowCount: 3, now: { now }) { index in
            attempted.append(index)
            return index == 1 ? .init(failureCount: 1, commitFailed: true) : .init()
        }
        XCTAssertEqual(attempted, [0, 1])
        XCTAssertTrue(initial.changes.commitFailed)
        XCTAssertEqual(coordinator.checkpoint(fingerprint: "rules", windowCount: 3).completedWindows, [0])

        attempted = []
        _ = await coordinator.run(fingerprint: "rules", windowCount: 3, now: { now.addingTimeInterval(60) }) {
            attempted.append($0)
            return .init()
        }
        XCTAssertEqual(attempted, [1, 2])
    }

    func testRetryBackoffIsRespectedAndCappedAtOneHour() async {
        let coordinator = CalendarAlertFullSyncCoordinator(defaults: makeDefaults())
        var time = now
        var requests = 0
        for expectedDelay in [60.0, 120, 240, 480, 960, 1_920, 3_600, 3_600] {
            let result = await coordinator.run(fingerprint: "rules", windowCount: 1, now: { time }) { _ in
                requests += 1
                return .init(failureCount: 1)
            }
            XCTAssertEqual(result.nextRetryAt, time.addingTimeInterval(expectedDelay))
            let count = requests
            _ = await coordinator.run(fingerprint: "rules", windowCount: 1, now: { time.addingTimeInterval(expectedDelay - 1) }) { _ in
                requests += 1
                return .init()
            }
            XCTAssertEqual(requests, count)
            time += expectedDelay
        }
    }

    func testCancellationRetainsCompletedWindowWithoutSettingSuccessMarker() async {
        let defaults = makeDefaults()
        let coordinator = CalendarAlertFullSyncCoordinator(defaults: defaults)
        let task = Task {
            await coordinator.run(
                fingerprint: "rules", windowCount: 3, now: { self.now },
                applyWindow: { _ in .init() },
                progress: { completed, _ in
                    if completed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                }
            )
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertFalse(coordinator.isComplete(fingerprint: "rules"))
        XCTAssertEqual(coordinator.checkpoint(fingerprint: "rules", windowCount: 3).completedWindows, [0])
        var attempted: [Int] = []
        let resumed = await coordinator.run(fingerprint: "rules", windowCount: 3, now: { now }) {
            attempted.append($0)
            return .init()
        }
        XCTAssertEqual(attempted, [1, 2])
        XCTAssertTrue(resumed.isComplete)
    }

    func testPartiallyAppliedNewConfigurationInvalidatesPreviousSuccessWhenReverted() async {
        let coordinator = CalendarAlertFullSyncCoordinator(defaults: makeDefaults())
        _ = await coordinator.run(fingerprint: "old", windowCount: 2, now: { now }) { _ in .init() }
        XCTAssertTrue(coordinator.isComplete(fingerprint: "old"))
        _ = await coordinator.run(fingerprint: "new", windowCount: 2, now: { now }) { index in
            .init(failureCount: index == 0 ? 1 : 0)
        }
        XCTAssertFalse(coordinator.isComplete(fingerprint: "old"))
        var attempted: [Int] = []
        _ = await coordinator.run(fingerprint: "old", windowCount: 2, now: { now }) {
            attempted.append($0)
            return .init()
        }
        XCTAssertEqual(attempted, [0, 1])
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "CalendarAlertFullSyncCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}
