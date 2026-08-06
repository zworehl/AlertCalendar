import Foundation
import XCTest
@testable import AlertCalendar

final class MeetingBrowserRoutingTests: XCTestCase {
    func testRouteUsesFirstEnabledRuleForCalendarID() {
        let settings = MeetingBrowserRoutingSettings(
            defaultRoute: MeetingBrowserRoute(browser: .safari),
            rules: [
                CalendarMeetingBrowserRule(
                    name: "Disabled",
                    calendarIDs: ["work"],
                    route: MeetingBrowserRoute(browser: .chrome, profileID: "Profile 1"),
                    isEnabled: false
                ),
                CalendarMeetingBrowserRule(
                    name: "Work",
                    calendarIDs: ["work", "engineering"],
                    route: MeetingBrowserRoute(browser: .chrome, profileID: "Profile 3")
                ),
            ]
        )

        let route = MeetingBrowserRouting.route(for: "work", settings: settings)

        XCTAssertEqual(route.browser, .chrome)
        XCTAssertEqual(route.profileID, "Profile 3")
    }

    func testRouteFallsBackToDefaultRouteWhenNoRuleMatches() {
        let settings = MeetingBrowserRoutingSettings(
            defaultRoute: MeetingBrowserRoute(browser: .chrome, profileID: "Default"),
            rules: [
                CalendarMeetingBrowserRule(
                    name: "Clients",
                    calendarIDs: ["client"],
                    route: MeetingBrowserRoute(browser: .safari)
                ),
            ]
        )

        let route = MeetingBrowserRouting.route(for: "personal", settings: settings)

        XCTAssertEqual(route.browser, .chrome)
        XCTAssertEqual(route.profileID, "Default")
    }

    func testRoutingSettingsNormalizeRoutesAndAvailableCalendars() {
        let settings = MeetingBrowserRoutingSettings(
            defaultRoute: MeetingBrowserRoute(browser: .chrome, profileID: ""),
            rules: [
                CalendarMeetingBrowserRule(
                    name: "  Safari  ",
                    calendarIDs: ["cal-a", "missing"],
                    route: MeetingBrowserRoute(browser: .safari, profileID: "Work")
                ),
                CalendarMeetingBrowserRule(
                    name: "Missing",
                    calendarIDs: ["missing"],
                    route: MeetingBrowserRoute(browser: .chrome, profileID: "Profile 2")
                ),
            ]
        )

        let normalized = settings.normalized(availableCalendarIDs: ["cal-a"])

        XCTAssertEqual(normalized.defaultRoute.profileID, "Default")
        XCTAssertEqual(normalized.rules.map(\.name), ["Safari"])
        XCTAssertEqual(normalized.rules.first?.calendarIDs, Set(["cal-a"]))
        XCTAssertEqual(normalized.rules.first?.route.browser, .safari)
        XCTAssertEqual(normalized.rules.first?.route.profileID, MeetingBrowserRoute.automaticProfileID)
    }

    func testChromeProfilesParseLocalStateInfoCache() throws {
        let data = Data(
            """
            {
              "profile": {
                "info_cache": {
                  "Profile 3": {
                    "name": "Person 1",
                    "gaia_name": "Jonnathan",
                    "user_name": "jonn@example.com"
                  },
                  "Default": {
                    "name": "Your Chrome"
                  }
                }
              }
            }
            """.utf8
        )

        let profiles = MeetingBrowserProfileStore.chromiumProfiles(fromLocalStateData: data)

        XCTAssertEqual(profiles.map(\.id), ["Default", "Profile 3"])
        XCTAssertEqual(profiles.first?.displayName, "Your Chrome")
        XCTAssertEqual(profiles.last?.displayName, "Jonnathan")
        XCTAssertEqual(profiles.last?.detailText, "Profile 3 - jonn@example.com")
    }

    func testFirefoxProfilesParseProfilesIni() throws {
        let data = Data(
            """
            [Profile1]
            Name=default
            IsRelative=1
            Path=Profiles/v1u5dn7h.default
            Default=1

            [Profile0]
            Name=default-release
            IsRelative=1
            Path=Profiles/6thia7g6.default-release

            [General]
            StartWithLastProfile=1
            Version=2
            """.utf8
        )

        let profiles = MeetingBrowserProfileStore.firefoxProfiles(fromProfilesIniData: data)

        XCTAssertEqual(profiles.map(\.id), ["default", "default-release"])
        XCTAssertEqual(profiles.first?.isDefault, true)
        XCTAssertEqual(profiles.first?.detailText, "Profiles/v1u5dn7h.default")
    }

    func testProfileCatalogReportsMissingBrowserDataInsteadOfSilentlyFallingBack() throws {
        let homeDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: homeDirectoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: homeDirectoryURL) }

        let catalog = MeetingBrowserProfileStore.catalog(
            for: [.chrome],
            homeDirectoryURL: homeDirectoryURL
        )

        XCTAssertEqual(catalog.profilesByBrowser[.chrome]?.map(\.id), ["Default"])
        XCTAssertEqual(catalog.issuesByBrowser[.chrome]?.reason, .sourceMissing)
    }

    func testProfileCatalogLoadsProfilesWithoutAnIssueWhenSourceIsReadable() throws {
        let homeDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localStateURL = homeDirectoryURL
            .appendingPathComponent("Library/Application Support/Google/Chrome/Local State")
        try FileManager.default.createDirectory(
            at: localStateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(
            """
            {
              "profile": {
                "info_cache": {
                  "Default": {"name": "Personal"},
                  "Profile 3": {"name": "Work"}
                }
              }
            }
            """.utf8
        ).write(to: localStateURL)
        defer { try? FileManager.default.removeItem(at: homeDirectoryURL) }

        let catalog = MeetingBrowserProfileStore.catalog(
            for: [.chrome],
            homeDirectoryURL: homeDirectoryURL
        )

        XCTAssertEqual(catalog.profilesByBrowser[.chrome]?.map(\.id), ["Default", "Profile 3"])
        XCTAssertNil(catalog.issuesByBrowser[.chrome])
    }

    func testProfileCatalogUsesExplicitlyAuthorizedSourceURL() throws {
        let homeDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authorizedDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let authorizedSourceURL = authorizedDirectoryURL.appendingPathComponent("Local State")
        try FileManager.default.createDirectory(
            at: homeDirectoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: authorizedDirectoryURL,
            withIntermediateDirectories: true
        )
        try Data(
            """
            {
              "profile": {
                "info_cache": {
                  "Default": {"name": "Personal"},
                  "Profile 7": {"name": "Explicitly authorized"}
                }
              }
            }
            """.utf8
        ).write(to: authorizedSourceURL)
        defer {
            try? FileManager.default.removeItem(at: homeDirectoryURL)
            try? FileManager.default.removeItem(at: authorizedDirectoryURL)
        }

        let catalog = MeetingBrowserProfileStore.catalog(
            for: [.chrome],
            homeDirectoryURL: homeDirectoryURL,
            authorizedSourceURLs: [.chrome: authorizedSourceURL]
        )

        XCTAssertEqual(catalog.profilesByBrowser[.chrome]?.map(\.id), ["Default", "Profile 7"])
        XCTAssertNil(catalog.issuesByBrowser[.chrome])
    }

    func testExpectedProfileSourceURLMatchesBrowserFamily() {
        let homeDirectoryURL = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        XCTAssertEqual(
            MeetingBrowserProfileStore.expectedSourceURL(
                for: .chrome,
                homeDirectoryURL: homeDirectoryURL
            )?.path,
            "/Users/example/Library/Application Support/Google/Chrome/Local State"
        )
        XCTAssertEqual(
            MeetingBrowserProfileStore.expectedSourceURL(
                for: .firefox,
                homeDirectoryURL: homeDirectoryURL
            )?.path,
            "/Users/example/Library/Application Support/Firefox/profiles.ini"
        )
        XCTAssertNil(
            MeetingBrowserProfileStore.expectedSourceURL(
                for: .safari,
                homeDirectoryURL: homeDirectoryURL
            )
        )
    }
}
