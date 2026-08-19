import Foundation

struct AlertCalendarProcessResult: Sendable {
    let terminationStatus: Int32
    let output: Data
}

enum AlertCalendarProcessRunner {
    @discardableResult
    static func run(
        executableURL: URL,
        arguments: [String],
        waitUntilExit: Bool = false,
        redirectsOutputToNull: Bool = true
    ) -> Int32? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        if redirectsOutputToNull {
            let nullDevice = FileHandle(forWritingAtPath: "/dev/null")
            process.standardOutput = nullDevice
            process.standardError = nullDevice
        }

        do {
            try process.run()
            guard waitUntilExit else {
                // A running process has no termination status yet. Preserve the
                // existing non-nil success contract for fire-and-forget callers.
                return 0
            }

            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return nil
        }
    }

    static func runCapturingOutput(
        executableURL: URL,
        arguments: [String]
    ) -> AlertCalendarProcessResult? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            let capturedOutput = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return AlertCalendarProcessResult(
                terminationStatus: process.terminationStatus,
                output: capturedOutput
            )
        } catch {
            return nil
        }
    }
}
