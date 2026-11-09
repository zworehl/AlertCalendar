import Foundation
import XCTest
@testable import AlertCalendar

final class AlertCalendarProcessRunnerTests: XCTestCase {
    func testRunWithoutWaitingReturnsImmediatelyAfterSuccessfulLaunch() {
        let startDate = Date()
        let result = AlertCalendarProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["0.1"]
        )
        XCTAssertNotNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(startDate), 1)
    }

    func testCapturesStdoutAndStderrSeparatelyAndPreservesExitStatus() async throws {
        let result = try await Self.run("printf output; printf error >&2; exit 4")
        XCTAssertEqual(result.terminationStatus, 4)
        XCTAssertEqual(String(decoding: result.output, as: UTF8.self), "output")
        XCTAssertEqual(String(decoding: result.errorOutput, as: UTF8.self), "error")
    }

    func testDrainsOutputLargerThanPipeCapacity() async throws {
        let result = try await Self.run("/usr/bin/awk 'BEGIN {for(i=0;i<200000;i++) printf \"a\"}'")
        XCTAssertEqual(result.output.count, 200_000)
        XCTAssertEqual(result.terminationStatus, 0)
    }

    func testSuppliesInputAndClosesStdin() async throws {
        let input = Data(repeating: 65, count: 200_000)
        let result = try await AlertCalendarProcessRunner.runCapturingOutput(
            executableURL: URL(fileURLWithPath: "/bin/cat"), arguments: [], input: input
        )
        XCTAssertEqual(result.output, input)
    }

    func testDeadlineKillsChildIgnoringTerminationAndNextRunSucceeds() async throws {
        let pidURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: pidURL) }
        do {
            _ = try await Self.run("echo $$ > '\(pidURL.path)'; trap '' TERM; exec /bin/sleep 30", timeout: 0.2)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? AlertCalendarProcessError, .timedOut)
        }
        try await Self.assertChildExited(pidURL)
        let result = try await Self.run("printf recovered")
        XCTAssertEqual(String(decoding: result.output, as: UTF8.self), "recovered")
    }

    func testCancellationKillsRunningChild() async throws {
        let pidURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: pidURL) }
        let task = Task { try await Self.run("echo $$ > '\(pidURL.path)'; exec /bin/sleep 30") }
        for _ in 0 ..< 100 {
            if FileManager.default.fileExists(atPath: pidURL.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        try await Self.assertChildExited(pidURL)
    }

    func testDeadlineStillWorksWhenChildNeverReadsLargeInput() async throws {
        do {
            _ = try await AlertCalendarProcessRunner.runCapturingOutput(
                executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"],
                input: Data(repeating: 65, count: 1_000_000), timeout: 0.1
            )
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? AlertCalendarProcessError, .timedOut) }
    }

    func testBoundsExcessiveOutput() async throws {
        do {
            _ = try await AlertCalendarProcessRunner.runCapturingOutput(
                executableURL: URL(fileURLWithPath: "/usr/bin/yes"), arguments: [],
                maximumOutputBytes: 100_000
            )
            XCTFail("Expected output limit")
        } catch { XCTAssertEqual(error as? AlertCalendarProcessError, .outputLimitExceeded) }
    }

    @MainActor
    func testMainActorRemainsResponsiveDuringProcessExecution() async throws {
        let task = Task { try await Self.run("exec /bin/sleep 0.3") }
        let start = Date()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.25)
        _ = try await task.value
    }

    private static func run(_ source: String, timeout: TimeInterval = 3) async throws -> AlertCalendarProcessResult {
        try await AlertCalendarProcessRunner.runCapturingOutput(
            executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", source], timeout: timeout
        )
    }

    private static func assertChildExited(_ pidURL: URL) async throws {
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        for _ in 0 ..< 100 {
            if kill(pid, 0) != 0 { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Child process survived cancellation/deadline")
    }
}
