import AppKit
import Foundation

enum MeetingBrowserLauncher {
    @MainActor
    @discardableResult
    static func open(_ url: URL, route rawRoute: MeetingBrowserRoute) -> Bool {
        let route = rawRoute.normalized

        switch route.browser.profileFamily {
        case .chromium:
            return openChromiumBrowser(url, browser: route.browser, profileID: route.profileID)
        case .firefox:
            return openFirefoxBrowser(url, browser: route.browser, profileID: route.profileID)
        case .none:
            return open(url, with: route.browser)
        }
    }

    @MainActor
    private static func openChromiumBrowser(_ url: URL, browser: MeetingBrowserKind, profileID: String) -> Bool {
        guard let applicationURL = applicationURL(for: browser) else {
            return AlertCalendarWorkspace.open(url)
        }

        let executableURL = applicationURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(browser.executableName)

        if FileManager.default.isExecutableFile(atPath: executableURL.path) {
            if AlertCalendarProcessRunner.run(
                executableURL: executableURL,
                arguments: [
                    "--profile-directory=\(profileID)",
                    url.absoluteString,
                ]
            ) != nil {
                return true
            }

            return open(url, with: browser)
        }

        return open(url, with: browser)
    }

    @MainActor
    private static func openFirefoxBrowser(_ url: URL, browser: MeetingBrowserKind, profileID: String) -> Bool {
        guard let applicationURL = applicationURL(for: browser) else {
            return AlertCalendarWorkspace.open(url)
        }

        let executableURL = applicationURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(browser.executableName)

        if FileManager.default.isExecutableFile(atPath: executableURL.path) {
            if AlertCalendarProcessRunner.run(
                executableURL: executableURL,
                arguments: [
                    "-P",
                    profileID,
                    "-new-tab",
                    url.absoluteString,
                ]
            ) != nil {
                return true
            }

            return open(url, with: browser)
        }

        return open(url, with: browser)
    }

    @MainActor
    private static func open(_ url: URL, with browser: MeetingBrowserKind) -> Bool {
        guard let applicationURL = applicationURL(for: browser) else {
            return AlertCalendarWorkspace.open(url)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        AlertCalendarWorkspace.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: configuration,
            completionHandler: nil
        )
        return true
    }

    @MainActor
    private static func applicationURL(for browser: MeetingBrowserKind) -> URL? {
        MeetingBrowserCatalog.applicationURL(for: browser)
    }
}
