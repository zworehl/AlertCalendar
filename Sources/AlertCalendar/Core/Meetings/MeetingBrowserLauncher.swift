import AppKit
import Foundation

enum MeetingBrowserLauncher {
    @discardableResult
    static func open(_ url: URL, route rawRoute: MeetingBrowserRoute) async -> Bool {
        let route = rawRoute.normalized

        switch route.browser.profileFamily {
        case .chromium:
            return await openChromiumBrowser(url, browser: route.browser, profileID: route.profileID)
        case .firefox:
            return await openFirefoxBrowser(url, browser: route.browser, profileID: route.profileID)
        case .none:
            return await open(url, with: route.browser)
        }
    }

    private static func openChromiumBrowser(_ url: URL, browser: MeetingBrowserKind, profileID: String) async -> Bool {
        guard let applicationURL = await applicationURL(for: browser) else {
            return await openWithDefaultApplication(url)
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

            return await open(url, with: browser)
        }

        return await open(url, with: browser)
    }

    private static func openFirefoxBrowser(_ url: URL, browser: MeetingBrowserKind, profileID: String) async -> Bool {
        guard let applicationURL = await applicationURL(for: browser) else {
            return await openWithDefaultApplication(url)
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

            return await open(url, with: browser)
        }

        return await open(url, with: browser)
    }

    private static func open(_ url: URL, with browser: MeetingBrowserKind) async -> Bool {
        guard let applicationURL = await applicationURL(for: browser) else {
            return await openWithDefaultApplication(url)
        }

        return await open(url, withApplicationAt: applicationURL)
    }

    @MainActor
    private static func openWithDefaultApplication(_ url: URL) -> Bool {
        AlertCalendarWorkspace.open(url)
    }

    @MainActor
    private static func open(_ url: URL, withApplicationAt applicationURL: URL) -> Bool {
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
