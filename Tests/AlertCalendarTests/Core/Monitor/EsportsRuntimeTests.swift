import EventKit
import Foundation
import XCTest
@testable import AlertCalendar

private final class EsportsTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date
    init(_ instant: Date) { self.instant = instant }
    var date: Date { lock.withLock { instant } }
    func advance(_ interval: TimeInterval) { lock.withLock { instant = instant.addingTimeInterval(interval) } }
}

private actor EsportsTestProvider: EsportsProviding {
    var result = EsportsLoadResult(matches: [], isComplete: true, issues: [], fetchedAt: Date())
    var calls = 0
    var paused = false
    var failure: EsportsFeedError?
    var continuation: CheckedContinuation<EsportsLoadResult, Never>?
    var started: CheckedContinuation<Void, Never>?
    func set(_ result: EsportsLoadResult, paused: Bool = false) { self.result = result; self.paused = paused; failure = nil }
    func fail(_ error: EsportsFeedError) { failure = error }
    func waitForRequest() async {
        if calls > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func resume() { continuation?.resume(returning: result); continuation = nil }
    func load(game: EsportsGame, from: Date, to: Date, trackedIDs: [Int]) async throws -> EsportsLoadResult {
        calls += 1; started?.resume(); started = nil
        if let failure { throw failure }
        if paused { return await withCheckedContinuation { continuation = $0 } }
        return result
    }
}

private actor EsportsTestCache: EsportsCaching {
    var values: [EsportsMatch]
    var reads = 0
    var writes = 0
    init(_ values: [EsportsMatch] = []) { self.values = values }
    func load() -> [EsportsMatch] { reads += 1; return values }
    func save(matches: [EsportsMatch]) { writes += 1; values = matches }
}

@MainActor
private final class EsportsTestCalendar: EsportsCalendarReading, CalendarEventMutationStore {
    enum Failure: Error { case commit }
    let store: EKEventStore
    let calendar: EKCalendar
    var eventsByMatchID: [String: EKEvent] = [:]
    var selectedIDs: [Set<String>] = []
    var pendingSave: [EKEvent] = []
    var pendingRemove: [EKEvent] = []
    var commits = 0
    var removals = 0
    var resets = 0
    var failCommit = false
    init(store: EKEventStore) { self.store = store; calendar = EKCalendar(for: .event, eventStore: store) }
    func events(from: Date, to: Date, calendarIDs: Set<String>) -> [EKEvent] { selectedIDs.append(calendarIDs); return [] }
    func writableCalendar(id: String) -> EKCalendar? { id == "target" ? calendar : nil }
    func event(for record: ManagedEsportsEventRecord) -> EKEvent? { eventsByMatchID[record.matchID] }
    func save(_ event: EKEvent, span: EKSpan, commit: Bool) throws { pendingSave.append(event) }
    func remove(_ event: EKEvent, span: EKSpan, commit: Bool) throws { removals += 1; pendingRemove.append(event) }
    func commit() throws {
        commits += 1
        if failCommit { throw Failure.commit }
        for event in pendingSave {
            if let id = GamingCalendarClassifier.providerReference(in: event.notes) { eventsByMatchID[id] = event }
        }
        for event in pendingRemove {
            if let id = GamingCalendarClassifier.providerReference(in: event.notes) { eventsByMatchID[id] = nil }
        }
        pendingSave = []; pendingRemove = []
    }
    func reset() { resets += 1; pendingSave = []; pendingRemove = [] }
}

@MainActor
final class EsportsRuntimeTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_800_000_000)

    func testSmokeConstructionAndDisabledRefreshDoNotAccessCalendarNetworkOrDisk() async {
        let provider = EsportsTestProvider()
        let cache = EsportsTestCache()
        let (runtime, calendar, _) = makeRuntime(provider: provider, cache: cache, startsServices: false)
        await runtime.refresh(force: true)
        XCTAssertTrue(calendar.selectedIDs.isEmpty)
        let requests = await provider.calls, reads = await cache.reads
        XCTAssertEqual(requests, 0); XCTAssertEqual(reads, 0)
    }

    func testEmptyFocusSelectionNeverQueriesAllCalendars() async {
        let (runtime, calendar, _) = makeRuntime()
        runtime.configure(settings: configuredSettings(), selectedCalendarIDs: [], hasEventsAccess: true)
        await runtime.refresh(force: true)
        XCTAssertTrue(calendar.selectedIDs.isEmpty)
        runtime.configure(settings: configuredSettings(), selectedCalendarIDs: ["visible-only"], hasEventsAccess: true)
        await runtime.refresh(force: true)
        XCTAssertEqual(calendar.selectedIDs, [["visible-only"]])
    }

    func testFailedAddCommitNeverPublishesOrPersistsOwnership() async {
        let (runtime, calendar, defaults) = makeRuntime()
        calendar.failCommit = true
        let succeeded = await runtime.addMatch(match())
        XCTAssertFalse(succeeded)
        XCTAssertTrue(runtime.managedMatchIDs.isEmpty)
        XCTAssertNil(defaults.data(forKey: EsportsRuntime.recordsKey))
        XCTAssertEqual(calendar.resets, 1)
    }

    func testFailedRemoveCommitAndMissingLookupRetainOwnership() async {
        let (runtime, calendar, defaults) = makeRuntime()
        let item = match()
        XCTAssertTrue(awaitAdd(runtime, item))
        let original = defaults.data(forKey: EsportsRuntime.recordsKey)
        calendar.failCommit = true
        XCTAssertFalse(runtime.removeMatch(item))
        XCTAssertTrue(runtime.managedMatchIDs.contains(item.id))
        XCTAssertEqual(defaults.data(forKey: EsportsRuntime.recordsKey), original)
        calendar.eventsByMatchID = [:]
        XCTAssertFalse(runtime.removeMatch(item))
        XCTAssertTrue(runtime.managedMatchIDs.contains(item.id))
    }

    func testSuccessfulAddSelectsCalendarOnlyAfterCommitAndManualEditsArePreserved() async {
        let (runtime, calendar, _) = makeRuntime()
        var callbackCount = 0
        runtime.onCalendarAdded = { id in XCTAssertEqual(id, "target"); XCTAssertEqual(calendar.commits, 1); callbackCount += 1 }
        let item = match()
        XCTAssertTrue(awaitAdd(runtime, item))
        XCTAssertEqual(callbackCount, 1)
        let event = calendar.eventsByMatchID[item.id]!
        event.title = "User customized title"
        var updated = item; updated.scheduledAt = reference.addingTimeInterval(9_000)
        runtime.synchronizeManagedMatches([updated])
        XCTAssertEqual(event.title, "User customized title")
        XCTAssertEqual(calendar.commits, 1)
    }

    func testAbsenceNeverDeletesAndExplicitRemovalSuppressesAutoAdd() async {
        let (runtime, calendar, _) = makeRuntime()
        let item = match()
        XCTAssertTrue(awaitAdd(runtime, item))
        runtime.synchronizeManagedMatches([])
        XCTAssertTrue(runtime.managedMatchIDs.contains(item.id))
        XCTAssertEqual(calendar.removals, 0)
        XCTAssertTrue(runtime.removeMatch(item))
        var settings = configuredSettings(); settings.autoAddCompetitionIDs = [EsportsRuntime.competitionKey(for: item)!]
        runtime.configure(settings: settings, selectedCalendarIDs: ["target"], hasEventsAccess: true)
        runtime.autoAdd([item])
        XCTAssertFalse(runtime.managedMatchIDs.contains(item.id))
        XCTAssertEqual(calendar.commits, 2)
    }

    func testCacheRestoreNeverAutoAddsAndPartialRefreshMergesWithoutErasingCachedMatches() async {
        let first = match(), second = match(id: 2)
        let provider = EsportsTestProvider()
        await provider.set(EsportsLoadResult(matches: [second], isComplete: false, issues: [.init(kind: .paginationLimit)], fetchedAt: reference))
        let cache = EsportsTestCache([first])
        let (runtime, calendar, _) = makeRuntime(provider: provider, cache: cache)
        await runtime.refresh(force: true)
        XCTAssertEqual(Set(runtime.providerMatches.map(\.id)), [first.id, second.id])
        XCTAssertNil(runtime.lastValidatedAt)
        XCTAssertEqual(calendar.commits, 0)
        XCTAssertNotNil(runtime.errorMessage)
        await runtime.prepareForTermination()
    }

    func testUnavailablePublicFeedKeepsCachedCardsAndDoesNotWriteCalendar() async {
        let provider = EsportsTestProvider(), item = match()
        await provider.fail(.networkUnavailable)
        let (runtime, calendar, _) = makeRuntime(provider: provider, cache: EsportsTestCache([item]))
        await runtime.refresh(force: true)
        XCTAssertEqual(runtime.providerMatches.map(\.id), [item.id])
        XCTAssertNotNil(runtime.errorMessage)
        XCTAssertNil(runtime.lastValidatedAt)
        XCTAssertEqual(calendar.commits, 0)
        await runtime.prepareForTermination()
    }

    func testLateResponseAfterConfigurationChangeCannotPublishOrAutoAdd() async {
        let item = match()
        let provider = EsportsTestProvider()
        await provider.set(EsportsLoadResult(matches: [item], isComplete: true, issues: [], fetchedAt: reference), paused: true)
        let (runtime, calendar, _) = makeRuntime(provider: provider)
        var settings = configuredSettings(); settings.autoAddCompetitionIDs = [EsportsRuntime.competitionKey(for: item)!]
        runtime.configure(settings: settings, selectedCalendarIDs: ["target"], hasEventsAccess: true)
        let task = Task { await runtime.refresh(force: true) }
        await provider.waitForRequest()
        settings.providerGames = []
        runtime.configure(settings: settings, selectedCalendarIDs: ["target"], hasEventsAccess: true)
        await provider.resume()
        await task.value
        XCTAssertTrue(runtime.providerMatches.isEmpty)
        XCTAssertEqual(calendar.commits, 0)
    }

    func testManualForceDuringRefreshRunsOneCoalescedFollowUp() async {
        let provider = EsportsTestProvider()
        let result = EsportsLoadResult(matches: [match()], isComplete: true, issues: [], fetchedAt: reference)
        await provider.set(result, paused: true)
        let (runtime, _, _) = makeRuntime(provider: provider)
        let initial = Task { await runtime.refresh(force: false) }
        await provider.waitForRequest()
        let forced = Task { await runtime.refresh(force: true) }
        for _ in 0..<100 where !runtime.forceRefreshRequested { await Task.yield() }
        await provider.set(result, paused: false)
        await provider.resume()
        await initial.value; await forced.value
        let calls = await provider.calls
        XCTAssertEqual(calls, 2)
    }

    func testPublicProviderStartsWithoutCredentialsAndUsesTwoHourCadenceWithManualForce() async {
        let clock = EsportsTestClock(reference), provider = EsportsTestProvider()
        let verified = reference.addingTimeInterval(-60)
        await provider.set(EsportsLoadResult(matches: [match()], isComplete: true, issues: [], fetchedAt: verified))
        let (runtime, _, _) = makeRuntime(provider: provider, clock: clock)
        await runtime.refresh()
        XCTAssertEqual(runtime.providerMatches.map(\.id), [match().id])
        XCTAssertEqual(runtime.lastValidatedAt, verified, "The source's validation date must not be replaced by the wall clock")
        clock.advance(7_199)
        await runtime.refresh()
        let beforeDeadline = await provider.calls
        XCTAssertEqual(beforeDeadline, 1)
        clock.advance(1)
        await runtime.refresh()
        let atDeadline = await provider.calls
        XCTAssertEqual(atDeadline, 2)
        await runtime.refresh(force: true)
        let afterManualRefresh = await provider.calls
        XCTAssertEqual(afterManualRefresh, 3)
    }

    func testFailedPublicLoadRetriesAfterBackoffBeforeTheNormalTwoHourDeadline() async {
        let clock = EsportsTestClock(reference), provider = EsportsTestProvider()
        await provider.set(EsportsLoadResult(matches: [], isComplete: false,
            issues: [.init(kind: .requestFailed)], fetchedAt: reference))
        let (runtime, _, _) = makeRuntime(provider: provider, clock: clock)
        await runtime.refresh()
        XCTAssertNotNil(runtime.errorMessage)
        clock.advance(301)
        await provider.set(EsportsLoadResult(matches: [match()], isComplete: true, issues: [], fetchedAt: clock.date))
        await runtime.refresh()
        let calls = await provider.calls
        XCTAssertEqual(calls, 2)
        XCTAssertNil(runtime.errorMessage)
        XCTAssertEqual(runtime.providerMatches.map(\.id), [match().id])
    }

    func testOnlyFetchScopeChangesResetProviderCadenceAndExistingCardsStayVisible() async {
        let provider = EsportsTestProvider()
        await provider.set(EsportsLoadResult(matches: [match()], isComplete: true, issues: [], fetchedAt: reference))
        let (runtime, _, _) = makeRuntime(provider: provider)
        await runtime.refresh()
        var settings = configuredSettings(); settings.alertLeadMinutes = 30
        runtime.configure(settings: settings, selectedCalendarIDs: ["target"], hasEventsAccess: true)
        await runtime.refresh()
        let afterAlertChange = await provider.calls
        XCTAssertEqual(afterAlertChange, 1)
        settings.lookaheadDays += 1
        runtime.configure(settings: settings, selectedCalendarIDs: ["target"], hasEventsAccess: true)
        XCTAssertEqual(runtime.providerMatches.map(\.id), [match().id])
        await runtime.refresh()
        let afterWindowChange = await provider.calls
        XCTAssertEqual(afterWindowChange, 2)
    }

    func testUnknownDatesAndPostponementsCannotBeAddedAndCompetitionIdentityIncludesGame() {
        let (runtime, _, _) = makeRuntime()
        var item = match(); item.scheduledAt = nil
        XCTAssertFalse(runtime.canAddMatch(item))
        item.scheduledAt = reference; item.status = .postponed
        XCTAssertFalse(runtime.canAddMatch(item))
        XCTAssertEqual(EsportsRuntime.competitionKey(for: item), "leagueOfLegends:10")
    }

    func testManualCalendarCandidateBlocksDuplicateWithoutAdoptingOrWriting() async {
        let (runtime, calendar, defaults) = makeRuntime()
        let item = match()
        runtime.localEvents = [local(game: .leagueOfLegends, start: item.scheduledAt!)]
        XCTAssertEqual(runtime.presence(of: item), .external)
        let satisfied = await runtime.addMatch(item)
        XCTAssertTrue(satisfied)
        XCTAssertEqual(calendar.commits, 0)
        XCTAssertTrue(runtime.managedMatchIDs.isEmpty)
        XCTAssertNil(defaults.data(forKey: EsportsRuntime.recordsKey))
        runtime.localEvents = [local(game: .rocketLeague, start: item.scheduledAt!)]
        XCTAssertEqual(runtime.presence(of: item), .absent)
        runtime.localEvents = [local(game: .leagueOfLegends, start: item.scheduledAt!.addingTimeInterval(86_400))]
        XCTAssertEqual(runtime.presence(of: item), .absent)
    }

    func testConfigurationDiscardsUnsupportedLocalProjectionWithoutWritingCalendar() {
        let (runtime, calendar, defaults) = makeRuntime()
        let supported = local(game: .leagueOfLegends, start: reference)
        let unsupported = [EsportsGame.ageOfEmpires2, .geoGuessr, .granTurismo7].map { local(game: $0, start: reference) }
        runtime.localEvents = [supported] + unsupported
        var settings = configuredSettings(); settings.lookbackDays = 30
        runtime.configure(settings: settings, selectedCalendarIDs: ["target"], hasEventsAccess: true)
        XCTAssertEqual(runtime.localEvents, [supported])
        XCTAssertEqual(calendar.commits, 0)
        XCTAssertEqual(calendar.removals, 0)
        XCTAssertTrue(calendar.pendingSave.isEmpty)
        XCTAssertNil(defaults.data(forKey: EsportsRuntime.recordsKey))
    }

    func testCancelingOrPostponingManagedMatchKeepsEventAndRemovesAlarm() {
        let (runtime, calendar, _) = makeRuntime()
        var item = match()
        XCTAssertTrue(awaitAdd(runtime, item))
        item.status = .postponed
        runtime.synchronizeManagedMatches([item])
        XCTAssertTrue(runtime.managedMatchIDs.contains(item.id))
        XCTAssertTrue(calendar.eventsByMatchID[item.id]?.alarms?.isEmpty ?? true)
        XCTAssertEqual(calendar.removals, 0)
    }

    func testTrackedMatchesStayVisibleWhenWindowOrEnabledGamesChanges() {
        let (runtime, _, _) = makeRuntime()
        let item = match()
        XCTAssertTrue(awaitAdd(runtime, item))
        runtime.merge([item])
        var settings = configuredSettings(); settings.providerGames = [.rocketLeague]
        runtime.configure(settings: settings, selectedCalendarIDs: ["target"], hasEventsAccess: true)
        XCTAssertTrue(runtime.providerMatches.contains(where: { $0.id == item.id }))
    }

    func testLegacyMatchDecodesWithoutFeedFieldsAndPublicMetadataPreservesIdentity() throws {
        let data = Data(#"{"providerID":1711021,"game":"leagueOfLegends","name":"Legacy final","competitionID":10,"competitionName":"Worlds","opponents":[],"results":[],"status":"finished","rescheduled":false,"forfeit":false,"fetchedAt":100}"#.utf8)
        var item = try JSONDecoder().decode(EsportsMatch.self, from: data)
        XCTAssertEqual(item.id, "pandascore:leagueOfLegends:1711021")
        XCTAssertEqual(item.sourceAttributionText, "Source: PandaScore")
        XCTAssertEqual(item.competitionKey, "leagueOfLegends:10")
        item.feedSourceURL = URL(string: "https://www.esport-calendar.com/")
        item.feedSourceAttribution = "Source: Esports Calendar · Data: PandaScore"
        item.feedCompetitionKey = "esport-calendar:leagueOfLegends:Worlds"
        let restored = try JSONDecoder().decode(EsportsMatch.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(restored.id, "pandascore:leagueOfLegends:1711021")
        XCTAssertEqual(restored.competitionKey, item.feedCompetitionKey)
        XCTAssertEqual(restored.sourceAttributionText, item.feedSourceAttribution)
        XCTAssertEqual(restored.feedSourceURL, item.feedSourceURL)
    }

    private func local(game: EsportsGame, start: Date) -> LocalGamingCalendarEvent {
        LocalGamingCalendarEvent(id: "manual", game: game, title: "Worlds final", startDate: start,
            endDate: start.addingTimeInterval(7_200), isAllDay: false, calendarID: "target", calendarName: "Events",
            sourceURL: nil, eventIdentifier: "manual-id", eventUID: "manual-uid", kind: .competitive, providerMatchID: nil)
    }

    // Uses the same synchronous transaction as the public async Apply action.
    private func awaitAdd(_ runtime: EsportsRuntime, _ item: EsportsMatch) -> Bool { runtime.addMatchNow(item) }

    private func configuredSettings() -> EsportsSettings {
        var settings = EsportsSettings(); settings.targetCalendarID = "target"; return settings
    }

    private func match(id: Int = 1) -> EsportsMatch {
        EsportsMatch(providerID: id, game: .leagueOfLegends, name: "T1 vs GEN", competitionID: 10,
                     competitionName: "LCK", status: .scheduled, scheduledAt: reference.addingTimeInterval(3_600), fetchedAt: reference)
    }

    private func makeRuntime(provider: EsportsTestProvider = EsportsTestProvider(),
                             cache: EsportsTestCache? = nil,
                             startsServices: Bool = true,
                             clock: EsportsTestClock? = nil) -> (EsportsRuntime, EsportsTestCalendar, UserDefaults) {
        let suite = "EsportsRuntimeTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        let eventStore = EKEventStore(), clock = clock ?? EsportsTestClock(reference)
        let calendar = EsportsTestCalendar(store: eventStore)
        let runtime = EsportsRuntime(eventStore: eventStore, mutations: CalendarMutationCoordinator(store: calendar), defaults: defaults,
            client: provider, cacheStore: cache, startsServices: startsServices, calendarSource: calendar, now: { clock.date })
        runtime.configure(settings: configuredSettings(), selectedCalendarIDs: ["target"], hasEventsAccess: true)
        return (runtime, calendar, defaults)
    }
}
