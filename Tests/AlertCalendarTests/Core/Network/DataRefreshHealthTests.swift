import Foundation
import XCTest
@testable import AlertCalendar

final class DataRefreshHealthTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    func testRestoredFailurePreservesOutageAgeWithoutOverwritingANewerAttempt() async {
        let health = DataRefreshHealth()
        let persisted = DataRefreshIssue(id: "feed", title: "Feed", detail: "Offline",
                                         firstFailedAt: start, lastFailedAt: start.addingTimeInterval(60))
        await health.restore(persisted)
        let restored = await health.snapshot()
        XCTAssertEqual(restored, [persisted])
        await health.record(source: "feed", title: "Feed", error: "Timeout", at: start.addingTimeInterval(120))
        await health.restore(persisted)
        let newer = await health.snapshot()
        XCTAssertEqual(newer.first?.detail, "Timeout")
        XCTAssertEqual(newer.first?.firstFailedAt, start)
        XCTAssertEqual(newer.first?.lastFailedAt, start.addingTimeInterval(120))
    }

    func testShortFailureDoesNotNotifyAndRecoveryClearsIt() async {
        let health = DataRefreshHealth()
        await health.record(source: "football", title: "Football", error: "Timeout", at: start)
        let failed = await health.snapshot()
        XCTAssertNil(DataRefreshNotificationPolicy().notificationBody(issues: failed, now: start.addingTimeInterval(299)))
        XCTAssertNotNil(DataRefreshNotificationPolicy().notificationBody(issues: failed, now: start.addingTimeInterval(300)))
        await health.record(source: "football", title: "Football", error: nil, at: start.addingTimeInterval(60))
        let recovered = await health.snapshot()
        XCTAssertTrue(recovered.isEmpty)
        XCTAssertNil(DataRefreshNotificationPolicy().notificationBody(issues: recovered, now: start.addingTimeInterval(3_600)))
    }

    func testRepeatedFailuresKeepOutageStartAndObservingDoesNotInventAttempts() async {
        let health = DataRefreshHealth()
        await health.record(source: "one", title: "One", error: "Timeout", at: start)
        await health.record(source: "one", title: "One", error: "Offline", at: start.addingTimeInterval(60))
        await health.observe(source: "one", title: "One", error: "Offline", at: start.addingTimeInterval(120))
        let issues = await health.snapshot()
        XCTAssertEqual(issues.first?.firstFailedAt, start)
        XCTAssertEqual(issues.first?.lastFailedAt, start.addingTimeInterval(60))
    }

    func testHourlyCooldownAppliesAcrossSourcesAndCanBeRestoredAfterRelaunch() async {
        let health = DataRefreshHealth()
        await health.record(source: "one", title: "One", error: "Offline", at: start)
        await health.record(source: "two", title: "Two", error: "Offline", at: start)
        let issues = await health.snapshot()
        let notifiedAt = start.addingTimeInterval(300)
        let policy = DataRefreshNotificationPolicy(lastNotificationDate: notifiedAt)
        XCTAssertNil(policy.notificationBody(issues: issues, now: notifiedAt.addingTimeInterval(3_599)))
        let body = policy.notificationBody(issues: issues, now: notifiedAt.addingTimeInterval(3_600))
        XCTAssertTrue(body?.contains("One, Two") == true)
    }

    func testRecoveryOfOneSourceDoesNotClearOthersAndDisabledSourcesAreRemoved() async {
        let health = DataRefreshHealth()
        await health.record(source: "holiday.cr", title: "Costa Rica", error: "Offline", at: start)
        await health.record(source: "holiday.us", title: "USA", error: "Offline", at: start)
        await health.record(source: "football", title: "Football", error: "Offline", at: start)
        await health.record(source: "football", title: "Football", error: nil, at: start)
        await health.removeSources(withPrefix: "holiday.", except: ["holiday.cr"])
        let remaining = await health.snapshot()
        XCTAssertEqual(remaining.map(\.id), ["holiday.cr"])
    }

    func testNewOutageAfterRecoveryReceivesANewGracePeriod() async {
        let health = DataRefreshHealth()
        await health.record(source: "feed", title: "Feed", error: "Offline", at: start)
        await health.record(source: "feed", title: "Feed", error: nil, at: start.addingTimeInterval(100))
        await health.record(source: "feed", title: "Feed", error: "Offline", at: start.addingTimeInterval(500))
        let issues = await health.snapshot()
        XCTAssertEqual(issues.first?.firstFailedAt, start.addingTimeInterval(500))
        XCTAssertNil(DataRefreshNotificationPolicy().notificationBody(issues: issues, now: start.addingTimeInterval(501)))
    }
}
