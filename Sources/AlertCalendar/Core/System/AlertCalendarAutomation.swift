import AppKit
import ApplicationServices
import Foundation

struct AlertCalendarAutomationRequest: Codable, Sendable {
    enum Operation: String, Codable, Sendable { case permission, script }
    let operation: Operation
    let bundleIdentifier: String
    var source: String = ""
    var asksForPermission = false
}

struct AlertCalendarAutomationResponse: Codable, Sendable {
    var permissionStatus: Int32?
    var value: String?
    var rows: [[String]]?
    var errorNumber: Int?
}

enum AlertCalendarAutomationError: Error { case busy, invalidResponse, processExited(Int32) }

// One child per target, with no waiting queue. A hung Mail query cannot prevent
// Music, browsers, or Calendar from completing. The child uses this app's signed
// executable, preserving its automation identity rather than delegating to a shell.
actor AlertCalendarAutomation {
    static let shared = AlertCalendarAutomation(executableURL: applicationExecutableURL)
    private var activeTargets: Set<String> = []
    private let executableURL: URL?
    private let environment: [String: String]?

    private static var applicationExecutableURL: URL? {
        guard let url = Bundle.main.executableURL, url.lastPathComponent == "AlertCalendar" else { return nil }
        return url
    }

    init(executableURL: URL? = Bundle.main.executableURL, environment: [String: String]? = nil) {
        self.executableURL = executableURL
        self.environment = environment
    }

    func execute(
        _ request: AlertCalendarAutomationRequest,
        timeout: TimeInterval = 5
    ) async throws -> AlertCalendarAutomationResponse {
        try Task.checkCancellation()
        guard let executableURL else { throw AlertCalendarAutomationError.invalidResponse }
        guard activeTargets.insert(request.bundleIdentifier).inserted else {
            throw AlertCalendarAutomationError.busy
        }
        defer { activeTargets.remove(request.bundleIdentifier) }
        let result = try await AlertCalendarProcessRunner.runCapturingOutput(
            executableURL: executableURL,
            arguments: [AlertCalendarAutomationHelper.argument],
            input: JSONEncoder().encode(request), environment: environment, timeout: timeout
        )
        try Task.checkCancellation()
        guard result.terminationStatus == 0 else {
            throw AlertCalendarAutomationError.processExited(result.terminationStatus)
        }
        return try JSONDecoder().decode(AlertCalendarAutomationResponse.self, from: result.output)
    }
}

enum AlertCalendarAutomationHelper {
    static let argument = "--alertcalendar-automation-helper"

    // Invoked before SwiftUI, the monitor, timers, or application delegates exist.
    // A synchronous macOS call may block this disposable child, never the UI.
    @MainActor
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.dropFirst().first == argument else { return false }
        // AppleScript initializes AppKit and registers this executable with
        // Launch Services. It must never become another Dock application.
        _ = NSApplication.shared.setActivationPolicy(.prohibited)
        let response: AlertCalendarAutomationResponse
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            let request = try JSONDecoder().decode(AlertCalendarAutomationRequest.self, from: input)
            response = autoreleasepool { execute(request) }
        } catch {
            response = AlertCalendarAutomationResponse(errorNumber: -1)
        }
        if let data = try? JSONEncoder().encode(response) {
            try? FileHandle.standardOutput.write(contentsOf: data)
        }
        return true
    }

    private static func execute(_ request: AlertCalendarAutomationRequest) -> AlertCalendarAutomationResponse {
        if request.operation == .permission {
            var target = AEAddressDesc()
            let created = request.bundleIdentifier.utf8CString.withUnsafeBytes { bytes in
                AECreateDesc(DescType(typeApplicationBundleID), bytes.baseAddress,
                             request.bundleIdentifier.utf8.count, &target)
            }
            guard created == noErr else { return .init(permissionStatus: Int32(created)) }
            defer { AEDisposeDesc(&target) }
            return .init(permissionStatus: AEDeterminePermissionToAutomateTarget(
                &target, AEEventClass(typeWildCard), AEEventID(typeWildCard), request.asksForPermission
            ))
        }
        guard let script = NSAppleScript(source: request.source) else { return .init(errorNumber: -1) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else {
            return .init(errorNumber: error?[NSAppleScript.errorNumber] as? Int ?? -1)
        }
        var rows: [[String]] = []
        if result.numberOfItems > 0 {
            for index in 1 ... result.numberOfItems {
                guard let row = result.atIndex(index), row.numberOfItems > 0 else { continue }
                rows.append((1 ... row.numberOfItems).compactMap { row.atIndex($0)?.stringValue })
            }
        }
        return .init(value: result.stringValue, rows: rows)
    }
}
