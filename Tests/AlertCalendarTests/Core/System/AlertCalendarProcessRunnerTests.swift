import Foundation
import XCTest
@testable import AlertCalendar

final class AlertCalendarProcessRunnerTests: XCTestCase {
    func testRunWithoutWaitingReturnsImmediatelyAfterSuccessfulLaunch() {
        let startDate = Date()

        let result = AlertCalendarProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["2"]
        )

        XCTAssertNotNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(startDate), 1)
    }

    func testRunWaitingForExitReturnsProcessTerminationStatus() {
        let result = AlertCalendarProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "exit 7"],
            waitUntilExit: true
        )

        XCTAssertEqual(result, 7)
    }
}
