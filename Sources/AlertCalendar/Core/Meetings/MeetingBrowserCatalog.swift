import AppKit
import Foundation

enum MeetingBrowserCatalog {
    static func installedBrowsers() -> [MeetingBrowserKind] {
        MeetingBrowserKind.allCases.filter { applicationURL(for: $0) != nil }
    }

    static func applicationURL(for browser: MeetingBrowserKind) -> URL? {
        if let url = AlertCalendarWorkspace.applicationURL(forBundleIdentifier: browser.bundleIdentifier) {
            return url
        }

        let fallbackURL = URL(fileURLWithPath: browser.fallbackApplicationPath)
        if FileManager.default.fileExists(atPath: fallbackURL.path) {
            return fallbackURL
        }

        let userFallbackURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
            .appendingPathComponent(URL(fileURLWithPath: browser.fallbackApplicationPath).lastPathComponent)
        guard FileManager.default.fileExists(atPath: userFallbackURL.path) else { return nil }
        return userFallbackURL
    }
}
