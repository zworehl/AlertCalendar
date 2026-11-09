import AppKit
import Darwin

@main
enum AlertCalendarEntryPoint {
    @MainActor
    static func main() {
        guard !AlertCalendarAutomationHelper.runIfRequested() else { return }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            exit(AlertCalendarSmokeTest.run(arguments: ProcessInfo.processInfo.arguments))
        }
        // Also covers direct executable launches, which bypass Launch Services'
        // LSMultipleInstancesProhibited protection.
        _ = NSApplication.shared.setActivationPolicy(.accessory)
        do {
            guard try AlertCalendarInstanceLock.shared.acquire() else {
                DistributedNotificationCenter.default().postNotificationName(
                    .alertCalendarReopenRequested, object: nil, deliverImmediately: true
                )
                return
            }
        } catch {
            try? FileHandle.standardError.write(contentsOf:
                Data("Unable to acquire AlertCalendar instance lock: \(error)\n".utf8)
            )
            return
        }
        let appDelegate = AppDelegate()
        NSApplication.shared.delegate = appDelegate
        withExtendedLifetime(appDelegate) {
            NSApplication.shared.run()
        }
    }
}
