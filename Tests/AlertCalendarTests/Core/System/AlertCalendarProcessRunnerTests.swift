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

    func testRunCapturingOutputAvoidsPipeBackpressure() throws {
        let result = try XCTUnwrap(
            AlertCalendarProcessRunner.runCapturingOutput(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf output; printf error >&2; exit 4"]
            )
        )

        XCTAssertEqual(result.terminationStatus, 4)
        XCTAssertEqual(String(decoding: result.output, as: UTF8.self), "outputerror")
    }
}
