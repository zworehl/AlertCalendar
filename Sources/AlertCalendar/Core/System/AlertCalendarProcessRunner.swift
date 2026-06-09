import Foundation

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
            if waitUntilExit {
                process.waitUntilExit()
            }
            return process.terminationStatus
        } catch {
            return nil
        }
    }
}
