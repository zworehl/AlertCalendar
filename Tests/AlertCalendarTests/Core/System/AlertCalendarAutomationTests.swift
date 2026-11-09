import Foundation
import XCTest
@testable import AlertCalendar

final class AlertCalendarAutomationTests: XCTestCase {
    func testHelperReturnsUnicodeTextAndStructuredMailRows() async throws {
        let runner = try Self.makeRunner()
        let text = try await runner.execute(.init(
            operation: .script, bundleIdentifier: "test.text", source: "return \"música 🎵\""
        ))
        XCTAssertEqual(text.value, "música 🎵")
        let rows = try await runner.execute(.init(
            operation: .script, bundleIdentifier: "test.rows",
            source: "return {{\"subject\", \"line 1\" & linefeed & \"line 2\"}, {\"second\", \"body\"}}"
        ))
        XCTAssertEqual(rows.rows, [["subject", "line 1\nline 2"], ["second", "body"]])
    }

    func testHelperReportsScriptErrorsWithoutCrashingHost() async throws {
        let response = try await Self.makeRunner().execute(.init(
            operation: .script, bundleIdentifier: "test.error", source: "error \"expected failure\" number -1234"
        ))
        XCTAssertEqual(response.errorNumber, -1234)
    }

    func testConcurrentRequestsToSameTargetDoNotAccumulate() async throws {
        let runner = try Self.makeRunner()
        let request = AlertCalendarAutomationRequest(
            operation: .script, bundleIdentifier: "test.busy", source: "delay 0.2\nreturn \"done\""
        )
        async let first = Self.attempt(runner, request: request)
        async let second = Self.attempt(runner, request: request)
        let responses = await [first, second]
        XCTAssertEqual(responses.filter { if case .success = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(responses.filter {
            if case .failure(let error) = $0, case AlertCalendarAutomationError.busy = error { true } else { false }
        }.count, 1)
    }

    func testHungTargetDoesNotBlockAnotherTargetAndCanRetry() async throws {
        let runner = try Self.makeRunner()
        let hung = AlertCalendarAutomationRequest(
            operation: .script, bundleIdentifier: "test.hung", source: "delay 30"
        )
        async let slow = Self.attempt(runner, request: hung, timeout: 0.2)
        let healthy = try await runner.execute(.init(
            operation: .script, bundleIdentifier: "test.healthy", source: "return \"healthy\""
        ))
        XCTAssertEqual(healthy.value, "healthy")
        if case .failure(let error) = await slow {
            XCTAssertEqual(error as? AlertCalendarProcessError, .timedOut)
        } else { XCTFail("Expected timeout") }
        let recovered = try await runner.execute(.init(
            operation: .script, bundleIdentifier: "test.hung", source: "return \"recovered\""
        ))
        XCTAssertEqual(recovered.value, "recovered")
    }

    private static func makeRunner() throws -> AlertCalendarAutomation {
        let binary = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("AlertCalendar")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path), "Missing helper executable: \(binary.path)")
        // Xcode's bare SwiftPM product has no app-bundle Frameworks rpath.
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_FRAMEWORK_PATH"] = binary.deletingLastPathComponent().path
        return AlertCalendarAutomation(executableURL: binary, environment: environment)
    }

    private static func attempt(
        _ runner: AlertCalendarAutomation, request: AlertCalendarAutomationRequest, timeout: TimeInterval = 3
    ) async -> Result<AlertCalendarAutomationResponse, any Error> {
        do { return .success(try await runner.execute(request, timeout: timeout)) }
        catch { return .failure(error) }
    }
}
