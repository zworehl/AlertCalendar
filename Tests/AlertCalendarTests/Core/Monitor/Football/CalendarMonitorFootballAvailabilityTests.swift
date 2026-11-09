import Foundation
import XCTest
@testable import AlertCalendar

final class CalendarMonitorFootballAvailabilityTests: FootballDataAPIClientTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    func testInitialRefreshChecksEveryCompetitionAndReusesConfirmedEmptyResults() async throws {
        let requests = RequestLog()
        let session = makeMockSession { request in
            requests.record(try self.competitionSlug(in: request))
            return try self.jsonResponse(for: request, body: ["events": []])
        }
        defer { session.invalidateAndCancel() }
        let monitor = await makeMonitor(client: FootballDataAPIClient(session: session))

        await monitor.refreshFootballCompetitionAvailability(lookbackDays: 1, lookaheadDays: 1)

        let expectedSlugs = Set(FootballCompetitionPreset.menuPresets.map(\.slug))
        XCTAssertEqual(expectedSlugs.count, 28)
        XCTAssertEqual(Set(requests.slugs), expectedSlugs)
        XCTAssertEqual(requests.slugs.count, expectedSlugs.count)
        XCTAssertEqual(monitor.footballMenuSections.count, expectedSlugs.count)
        XCTAssertTrue(monitor.footballMenuSections.allSatisfy {
            $0.hasLoaded && !$0.isLoading && $0.errorMessage == nil && $0.matches.isEmpty && $0.checkedWindow != nil
        })
        XCTAssertTrue(visibleCompetitionSlugs(in: monitor).isEmpty)

        await monitor.refreshFootballCompetitionAvailability(lookbackDays: 1, lookaheadDays: 1)

        XCTAssertEqual(requests.slugs.count, expectedSlugs.count, "Confirmed empty windows must be cached too")
    }

    @MainActor
    func testDiskCacheRestoresAvailableAndHiddenCompetitionsBeforeAnotherRequest() async throws {
        let store = try makeStore()
        let activeCompetition = FootballCompetitionPreset.premierLeague
        let event = fixtureEvent(startDate: now.addingTimeInterval(3_600))
        let session = makeMockSession { request in
            let events: [[String: Any]] = try self.competitionSlug(in: request) == activeCompetition.slug ? [event] : []
            return try self.jsonResponse(for: request, body: ["events": events])
        }
        defer { session.invalidateAndCancel() }
        let original = await makeMonitor(client: FootballDataAPIClient(session: session), store: store)
        await original.refreshFootballCompetitionAvailability(lookbackDays: 1, lookaheadDays: 1)
        XCTAssertEqual(store.load(now: now).count, FootballCompetitionPreset.menuPresets.count)

        let unexpectedRequests = RequestLog()
        let restoredSession = makeMockSession { request in
            unexpectedRequests.record(try self.competitionSlug(in: request))
            throw URLError(.badURL)
        }
        defer { restoredSession.invalidateAndCancel() }
        let restored = await makeMonitor(client: FootballDataAPIClient(session: restoredSession), store: store)
        restored.ensureFootballCompetitionSections()

        XCTAssertEqual(visibleCompetitionSlugs(in: restored), [activeCompetition.slug])
        XCTAssertEqual(restored.footballMenuSections.filter { $0.matches.isEmpty && $0.hasLoaded }.count, 27)
        await restored.refreshFootballCompetitionAvailability(lookbackDays: 1, lookaheadDays: 1)
        XCTAssertTrue(unexpectedRequests.slugs.isEmpty, "A fresh disk snapshot should avoid refetching all competitions")
        XCTAssertEqual(visibleCompetitionSlugs(in: restored), [activeCompetition.slug])
    }

    @MainActor
    func testFailedCompetitionDoesNotPersistEmptyAndIsCheckedAgainAfterRelaunch() async throws {
        let store = try makeStore()
        let failedCompetition = FootballCompetitionPreset.worldCup
        let session = makeMockSession { request in
            if try self.competitionSlug(in: request) == failedCompetition.slug {
                throw URLError(.notConnectedToInternet)
            }
            return try self.jsonResponse(for: request, body: ["events": []])
        }
        defer { session.invalidateAndCancel() }
        let original = await makeMonitor(client: FootballDataAPIClient(session: session), store: store)
        await original.refreshFootballCompetitionAvailability(lookbackDays: 1, lookaheadDays: 1)

        XCTAssertNil(store.load(now: now)[failedCompetition.slug])
        XCTAssertEqual(store.load(now: now).count, 27)
        XCTAssertNotNil(original.footballMenuSections.first { $0.id == failedCompetition.id }?.errorMessage)
        XCTAssertEqual(visibleCompetitionSlugs(in: original), [failedCompetition.slug], "Failures must remain retryable")

        let retryRequests = RequestLog()
        let retrySession = makeMockSession { request in
            retryRequests.record(try self.competitionSlug(in: request))
            return try self.jsonResponse(for: request, body: ["events": []])
        }
        defer { retrySession.invalidateAndCancel() }
        let restored = await makeMonitor(client: FootballDataAPIClient(session: retrySession), store: store)
        await restored.refreshFootballCompetitionAvailability(lookbackDays: 1, lookaheadDays: 1)

        XCTAssertEqual(retryRequests.slugs, [failedCompetition.slug])
        XCTAssertEqual(store.load(now: now).count, 28)
        XCTAssertNotNil(store.load(now: now)[failedCompetition.slug])
        XCTAssertTrue(visibleCompetitionSlugs(in: restored).isEmpty)
    }

    @MainActor
    func testHealthRecoveryDoesNotExpandFailedAvailabilityIntoDetailedLoads() async throws {
        let requests = RequestLog()
        let session = makeMockSession { request in
            requests.record(request)
            throw URLError(.notConnectedToInternet)
        }
        defer { session.invalidateAndCancel() }
        let monitor = await makeMonitor(client: FootballDataAPIClient(session: session))
        await monitor.refreshFootballCompetitionAvailability(lookbackDays: 1, lookaheadDays: 1)
        XCTAssertTrue(monitor.footballMenuSections.allSatisfy { $0.errorMessage != nil })
        monitor.dataRefreshIssues = await DataRefreshHealth.shared.snapshot()
        let countBeforeRecovery = requests.urls.count

        await monitor.retryFailedFootballBrowseLoads()

        XCTAssertEqual(requests.urls.count, countBeforeRecovery,
                       "Availability errors must not trigger full-season browse requests")
        XCTAssertTrue(monitor.footballState.detailedCompetitionSlugs.isEmpty)
    }

    @MainActor
    func testForcedRefreshPreservesNarrowAvailabilityWindowWithoutLoadingAllDetails() async throws {
        let requests = RequestLog()
        let session = makeMockSession { request in
            requests.record(request)
            return try self.jsonResponse(for: request, body: ["events": []])
        }
        defer { session.invalidateAndCancel() }
        let monitor = await makeMonitor(client: FootballDataAPIClient(session: session))
        await monitor.refreshFootballCompetitionAvailability(lookbackDays: 1, lookaheadDays: 1)

        await monitor.refreshFootballDataIfNeeded(now: now, force: true, reason: .manual)

        let window = FootballCompetitionAvailabilityWindow(now: now, lookbackDays: 1, lookaheadDays: 1)
        let expectedURL = try XCTUnwrap(FootballDataAPIClient.scoreboardURL(
            slug: FootballCompetitionPreset.premierLeague.slug, dateRange: (window.start, window.end)
        ))
        let expectedDates = URLComponents(url: expectedURL, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
        XCTAssertEqual(requests.urls.count, 2 * FootballCompetitionPreset.menuPresets.count,
                       "Manual refresh should repeat discovery, without loading 182-day detail windows")
        XCTAssertTrue(requests.urls.allSatisfy {
            $0.lastPathComponent == "scoreboard"
                && URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == expectedDates
        })
        XCTAssertTrue(monitor.footballState.detailedCompetitionSlugs.isEmpty)
    }

    @MainActor
    func testAvailabilityHealthRetainsEarlierChunkFailureAfterLaterChunkSucceeds() async throws {
        let failedCompetition = FootballCompetitionPreset.worldCup
        let window = FootballCompetitionAvailabilityWindow(now: now, lookbackDays: 1, lookaheadDays: 20)
        let firstRange = try XCTUnwrap(FootballDataAPIClient.scoreboardDateRanges(
            start: window.start, end: window.end, calendar: .autoupdatingCurrent
        ).first)
        let failedURL = FootballDataAPIClient.scoreboardURL(
            slug: failedCompetition.slug, dateRange: firstRange
        )
        let session = makeMockSession { request in
            if request.url == failedURL { throw URLError(.notConnectedToInternet) }
            return try self.jsonResponse(for: request, body: ["events": []])
        }
        defer { session.invalidateAndCancel() }
        let monitor = await makeMonitor(client: FootballDataAPIClient(session: session))

        await monitor.refreshFootballCompetitionAvailability(lookbackDays: 1, lookaheadDays: 20)

        let issues = await DataRefreshHealth.shared.snapshot()
        XCTAssertNotNil(issues.first { $0.id == "football.availability.\(failedCompetition.slug)" },
                        "A successful later chunk must not clear an earlier failed date range")
        XCTAssertNotNil(monitor.footballMenuSections.first { $0.id == failedCompetition.id }?.errorMessage)
        XCTAssertNil(monitor.footballState.availabilityBySlug[failedCompetition.slug])
    }

    @MainActor
    private func makeMonitor(
        client: FootballDataAPIClient,
        store: FootballCompetitionAvailabilityStore? = nil
    ) async -> CalendarMonitor {
        let suite = "CalendarMonitorFootballAvailabilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let monitor = CalendarMonitor(
            defaults: defaults, footballClient: client, clock: FixedClock(value: now),
            footballCompetitionAvailabilityStore: store, startServices: false
        )
        await monitor.restorePersistentCachesIfNeeded()
        return monitor
    }

    private func makeStore() throws -> FootballCompetitionAvailabilityStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return FootballCompetitionAvailabilityStore(fileURL: directory.appendingPathComponent("availability.json"))
    }

    @MainActor
    private func visibleCompetitionSlugs(in monitor: CalendarMonitor) -> [String] {
        SettingsFootballFixturesSectionView.browsableCompetitionSectionsByRegion(
            from: monitor.footballMenuSections, now: now, lookbackDays: 1, lookaheadDays: 1
        ).flatMap(\.sections).map(\.competition.slug)
    }

    private func competitionSlug(in request: URLRequest) throws -> String {
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.lastPathComponent, "scoreboard", "Discovery must not enrich team details or download images")
        return url.deletingLastPathComponent().lastPathComponent
    }

    private func fixtureEvent(startDate: Date) -> [String: Any] {
        [
            "id": "availability-fixture",
            "date": ISO8601DateFormatter().string(from: startDate),
            "competitions": [[
                "status": ["type": ["state": "pre", "shortDetail": "Scheduled", "detail": "Scheduled"]],
                "competitors": [
                    ["homeAway": "home", "score": "0", "team": ["id": "360", "displayName": "Manchester United", "abbreviation": "MAN"]],
                    ["homeAway": "away", "score": "0", "team": ["id": "382", "displayName": "Manchester City", "abbreviation": "MNC"]],
                ],
            ]],
        ]
    }

    private struct FixedClock: AlertCalendarClockProviding {
        let value: Date
        func nowRoundedToSecond() -> Date { value }
    }

    private final class RequestLog: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedSlugs: [String] = []
        private var recordedURLs: [URL] = []

        var urls: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return recordedURLs
        }

        var slugs: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recordedSlugs
        }

        func record(_ slug: String) {
            lock.lock()
            defer { lock.unlock() }
            recordedSlugs.append(slug)
        }

        func record(_ request: URLRequest) {
            lock.lock()
            defer { lock.unlock() }
            if let url = request.url { recordedURLs.append(url) }
        }
    }
}
