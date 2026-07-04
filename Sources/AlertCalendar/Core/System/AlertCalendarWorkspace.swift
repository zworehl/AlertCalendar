import AppKit
import Combine
import Foundation

enum AlertCalendarWorkspace {
    @discardableResult
    @MainActor
    static func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func open(
        _ urls: [URL],
        withApplicationAt applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completionHandler: (@Sendable (NSRunningApplication?, Error?) -> Void)? = nil
    ) {
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: configuration,
            completionHandler: completionHandler
        )
    }

    @MainActor
    static func openApplication(
        at applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completionHandler: (@Sendable (NSRunningApplication?, Error?) -> Void)? = nil
    ) {
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: configuration,
            completionHandler: completionHandler
        )
    }

    static func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    static func icon(forFile path: String, size: NSSize? = nil) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: path)
        image.isTemplate = false
        if let size {
            image.size = size
        }
        return image
    }

    static func notificationPublisher(for name: Notification.Name) -> NotificationCenter.Publisher {
        NSWorkspace.shared.notificationCenter.publisher(for: name)
    }
}
