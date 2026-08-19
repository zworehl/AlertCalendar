import Foundation
import XCTest
@testable import AlertCalendar

final class SettingsPollingFreshnessTests: XCTestCase {
    func testPollingFreshnessUsesOnlySecondsBelowOneMinute() {
        XCTAssertEqual(elapsedText(seconds: 53), "53s")
    }

    func testPollingFreshnessUsesOnlyMinutesBelowOneHour() {
        XCTAssertEqual(elapsedText(seconds: (53 * 60) + 32), "53m")
    }

    func testPollingFreshnessUsesOnlyHoursBelowOneDay() {
        XCTAssertEqual(elapsedText(seconds: (7 * 3_600) + (24 * 60)), "7h")
    }

    func testPollingFreshnessUsesOnlyDaysAfterOneDay() {
        XCTAssertEqual(elapsedText(seconds: (3 * 86_400) + (7 * 3_600)), "3d")
    }

    func testPollingFreshnessUsesSharedDetailedFormatWhenSimplificationIsDisabled() {
        XCTAssertEqual(elapsedText(seconds: (7 * 3_600) + (24 * 60), simplified: false), "7h 24m")
    }

    private func elapsedText(seconds: TimeInterval, simplified: Bool = true) -> String {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        return SettingsView.pollingFreshnessElapsedText(
            from: date,
            to: date.addingTimeInterval(seconds),
            simplified: simplified
        )
    }
}
