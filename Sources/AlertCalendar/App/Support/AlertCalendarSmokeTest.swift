import AppKit
import Foundation
import SwiftUI

/// Runs inside the packaged executable before normal startup. Dependencies and
/// defaults are isolated; UI lifecycle checks cannot contact a live integration.
@MainActor
enum AlertCalendarSmokeTest {
    struct Check: Codable {
        let name: String
        let passed: Bool
        var details: String? = nil
    }
    struct Report: Codable {
        let passed: Bool
        let checks: [Check]
    }

    static func run(arguments: [String]) -> Int32 {
        guard let index = arguments.firstIndex(of: "--report"), arguments.indices.contains(index + 1) else { return 2 }
        let reportURL = URL(fileURLWithPath: arguments[index + 1])
        var checks: [Check] = []
        let suite = "com.zworehl.alertcalendar.smoke.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return 2 }
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SmokeOfflineURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        SmokeOfflineURLProtocol.reset()

        var settings = AppSettings.defaults
        settings.showAgendaSummary = false
        settings.rewriteEventTitlesWithAppleIntelligence = false
        settings.useAutomaticAstronomyLocation = false
        settings.googleHolidayCountryIDs = []
        settings.footballAutoAddCompetitionSlugs = []
        settings.gameSaleAutoAddStores = []
        settings.slackConnections = []
        settings.appleMusicStatus.isEnabled = false
        let store = AppSettingsStore(defaults: defaults)
        store.registerDefaults()
        store.save(settings)
        defaults.set(SettingsView.SettingsTab.general.rawValue, forKey: SettingsNavigationPersistence.selectedTabKey)
        let monitor = CalendarMonitor(
            defaults: defaults,
            footballClient: FootballDataAPIClient(session: session),
            footballImageStore: FootballImageStore(session: session),
            gameSalesClient: GameSalesFeedClient(session: session),
            googleHolidayClient: GoogleHolidayFeedClient(session: session),
            slackClient: SlackAPIClient(session: session),
            startServices: false
        )
        monitor.isInitialLoadInProgress = false
        checks.append(Check(name: "isolated-services-disabled", passed: monitor.heartbeatTask == nil && !monitor.startsBackgroundServices))
        checks.append(Check(name: "packaged-resources", passed: Bundle.module.bundleURL.resolvingSymlinksInPath().path.hasPrefix(Bundle.main.bundleURL.resolvingSymlinksInPath().path)))

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.finishLaunching()
        let controller = MenuBarController(presentation: monitor.menuBarPresentationModel, persistsPosition: false)
        controller.setContent(AnyView(MenuContentView(kindFilter: nil, headerTitle: "Alert Calendar").environmentObject(monitor)))
        advanceLayout()
        controller.present()
        advanceLayout()
        checks.append(Check(name: "menu-opens", passed: controller.isPresented))
        controller.dismiss()
        checks.append(Check(name: "menu-dismisses", passed: !controller.isPresented))
        controller.stop()

        let oldLanguage = AlertCalendarLanguage.current
        for language in AppLanguage.allCases {
            AlertCalendarLanguage.current = language
            for width: CGFloat in [980, 1_240, 1_920] {
                let window = makeSettingsWindow(monitor: monitor, defaults: defaults, language: language, width: width)
                advanceLayout()
                let size = window.contentView?.bounds.size ?? .zero
                checks.append(Check(name: "settings-\(language.rawValue)-\(Int(width))", passed: size.width.isFinite && size.height.isFinite && abs(size.width - width) < 2 && size.height >= 700,
                    details: "content=\(Int(size.width))x\(Int(size.height)), requested width=\(Int(width))"))
                window.orderOut(nil)
                window.contentView = nil
            }
        }
        // Exercise the actual esports pane with isolated in-memory examples.
        // This runtime is constructed with startsServices=false, so opening the
        // view cannot read the user's calendars, provider cache or network.
        let esports = monitor.esportsRuntime
        let sampleDate = Date().addingTimeInterval(3_600)
        esports.providerMatches = [EsportsMatch(
            providerID: 42, game: .leagueOfLegends, name: "Blue vs Red",
            competitionName: "Sample tournament", status: .scheduled, scheduledAt: sampleDate,
            feedSourceURL: URL(string: "https://www.esport-calendar.com/calendar.ics?games=league-of-legends"),
            feedSourceAttribution: "Source: Esports Calendar · Data: PandaScore", feedCompetitionKey: "esports-calendar:leagueOfLegends:sample"
        )]
        esports.localEvents = [.init(
            id: "smoke-local", game: .leagueOfLegends, title: "League of Legends Worlds Final",
            startDate: sampleDate, endDate: sampleDate.addingTimeInterval(7_200), isAllDay: false,
            calendarID: "smoke", calendarName: "Sample calendar", sourceURL: nil,
            eventIdentifier: nil, eventUID: nil, kind: .competitive, providerMatchID: nil
        )]
        defaults.set(SettingsView.SettingsTab.feeds.rawValue, forKey: SettingsNavigationPersistence.selectedTabKey)
        defaults.set(SettingsView.FeedsSubsection.esports.rawValue, forKey: SettingsNavigationPersistence.selectedFeedsSubsectionKey)
        for language in AppLanguage.allCases {
            AlertCalendarLanguage.current = language
            for width: CGFloat in [980, 1_240, 1_920] {
                let window = makeSettingsWindow(monitor: monitor, defaults: defaults, language: language, width: width)
                advanceLayout()
                let size = window.contentView?.bounds.size ?? .zero
                checks.append(Check(name: "esports-\(language.rawValue)-\(Int(width))",
                    passed: abs(size.width - width) < 2 && size.height >= 700,
                    details: "content=\(Int(size.width))x\(Int(size.height))"))
                window.orderOut(nil)
                window.contentView = nil
            }
        }
        checks.append(Check(name: "esports-services-disabled", passed: !esports.startsServices && esports.refreshTask == nil))
        esports.providerMatches = []
        esports.localEvents = []
        AlertCalendarLanguage.current = oldLanguage
        defaults.set(SettingsView.SettingsTab.access.rawValue, forKey: SettingsNavigationPersistence.selectedTabKey)
        monitor.dataRefreshIssues = [.init(id: "smoke.offline", title: "Calendar", detail: "Offline", firstFailedAt: Date(), lastFailedAt: Date())]
        let deniedWindow = makeSettingsWindow(monitor: monitor, defaults: defaults, language: .english, width: 1_240)
        advanceLayout()
        checks.append(Check(name: "offline-denied-settings", passed: !monitor.hasEventsAccess && !monitor.hasRemindersAccess && deniedWindow.contentView != nil))
        deniedWindow.orderOut(nil)
        deniedWindow.contentView = nil

        var draft = SettingsDraft(settings: settings)
        draft.alertLeadMinutes = settings.alertLeadMinutes == 10 ? 15 : 10
        let applied = draft.applied(to: settings, availableEventCalendarIDs: [])
        checks.append(Check(name: "draft-apply", passed: applied.alertLeadMinutes == draft.alertLeadMinutes && settings.alertLeadMinutes != applied.alertLeadMinutes))
        draft = SettingsDraft(settings: settings)
        checks.append(Check(name: "draft-revert", passed: draft.alertLeadMinutes == settings.alertLeadMinutes))
        checks.append(Check(name: "no-live-network", passed: SmokeOfflineURLProtocol.requestCount == 0))

        let report = Report(passed: checks.allSatisfy(\.passed), checks: checks)
        do {
            try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(report).write(to: reportURL, options: .atomic)
        } catch { return 2 }
        return report.passed ? 0 : 1
    }

    private static func makeSettingsWindow(monitor: CalendarMonitor, defaults: UserDefaults, language: AppLanguage, width: CGFloat) -> NSWindow {
        let window = SmokeSettingsWindow(contentRect: NSRect(x: 40, y: 40, width: width, height: 840), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(monitor: monitor, runsLiveServices: false)
            .environment(\.locale, language.locale).defaultAppStorage(defaults))
        window.orderFront(nil)
        window.setContentSize(NSSize(width: width, height: 840))
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    private static func advanceLayout() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    }
}

/// A layout probe must exercise wide content even on a smaller CI display.
@MainActor
private final class SmokeSettingsWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class SmokeOfflineURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0
    static var requestCount: Int { lock.withLock { count } }
    static func reset() { lock.withLock { count = 0 } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.count += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
