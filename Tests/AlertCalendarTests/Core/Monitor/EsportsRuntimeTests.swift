import EventKit
import Foundation
import XCTest
@testable import AlertCalendar

private final class EsportsTestTokenStore: EsportsTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    private var accessCount = 0
    init(token: String? = nil) { value = token }
    var calls: Int { lock.withLock { accessCount } }
    func loadToken() throws -> String? { lock.withLock { accessCount += 1; return value } }
    func saveToken(_ token: String) throws { lock.withLock { accessCount += 1; value = token } }
    func removeToken() throws { lock.withLock { accessCount += 1; value = nil } }
}

private actor EsportsTestProvider: EsportsProviding {
    var result = EsportsLoadResult(matches: [], isComplete: true, issues: [], fetchedAt: Date())
    var calls = 0
    var paused = false
    var continuation: CheckedContinuation<EsportsLoadResult, Never>?
    var started: CheckedContinuation<Void, Never>?
    func set(_ result: EsportsLoadResult, paused: Bool = false) { self.result = result; self.paused = paused }
    func waitForRequest() async {
        if calls > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func resume() { continuation?.resume(returning: result); continuation = nil }
    func load(game: EsportsGame, from: Date, to: Date, token: String, trackedIDs: [Int]) async throws -> EsportsLoadResult {
        calls += 1; started?.resume(); started = nil
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

    func testSmokeConstructionAndDisabledRefreshDoNotAccessCalendarKeychainNetworkOrDisk() async {
        let tokens = EsportsTestTokenStore(token: "secret")
        let provider = EsportsTestProvider()
        let cache = EsportsTestCache()
        let (runtime, calendar, _) = makeRuntime(tokens: tokens, provider: provider, cache: cache, startsServices: false)
        await runtime.refresh(force: true)
        XCTAssertEqual(tokens.calls, 0)
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
        let (runtime, calendar, _) = makeRuntime(tokens: EsportsTestTokenStore(token: "secret"), provider: provider, cache: cache)
        await runtime.refresh(force: true)
        XCTAssertEqual(Set(runtime.providerMatches.map(\.id)), [first.id, second.id])
        XCTAssertNil(runtime.lastValidatedAt)
        XCTAssertEqual(calendar.commits, 0)
        XCTAssertNotNil(runtime.errorMessage)
        await runtime.prepareForTermination()
    }

    func testLateResponseAfterDisconnectCannotPublishOrAutoAdd() async {
        let item = match()
        let provider = EsportsTestProvider()
        await provider.set(EsportsLoadResult(matches: [item], isComplete: true, issues: [], fetchedAt: reference), paused: true)
        let (runtime, calendar, _) = makeRuntime(tokens: EsportsTestTokenStore(token: "secret"), provider: provider)
        var settings = configuredSettings(); settings.autoAddCompetitionIDs = [EsportsRuntime.competitionKey(for: item)!]
        runtime.configure(settings: settings, selectedCalendarIDs: ["target"], hasEventsAccess: true)
        let task = Task { await runtime.refresh(force: true) }
        await provider.waitForRequest()
        await runtime.disconnect()
        await provider.resume()
        await task.value
        XCTAssertFalse(runtime.isConnected)
        XCTAssertTrue(runtime.providerMatches.isEmpty)
        XCTAssertEqual(calendar.commits, 0)
    }

    func testManualForceDuringRefreshRunsOneCoalescedFollowUp() async {
        let provider = EsportsTestProvider()
        let result = EsportsLoadResult(matches: [match()], isComplete: true, issues: [], fetchedAt: reference)
        await provider.set(result, paused: true)
        let (runtime, _, _) = makeRuntime(tokens: EsportsTestTokenStore(token: "secret"), provider: provider)
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

    func testCredentialVaultRejectsLateOldSaveAfterDisconnectAndTermination() async throws {
        let tokens = EsportsTestTokenStore()
        let vault = EsportsCredentialVault(store: tokens)
        let saved = try await vault.save("first", revision: 1)
        let removed = try await vault.remove(revision: 3)
        let obsolete = try await vault.save("obsolete", revision: 2)
        XCTAssertTrue(saved); XCTAssertTrue(removed); XCTAssertFalse(obsolete)
        let current = try await vault.load()
        XCTAssertNil(current)
        await vault.finish(revision: 10)
        let afterTermination = try await vault.save("late", revision: 9)
        XCTAssertFalse(afterTermination)
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

    private func makeRuntime(tokens: EsportsTestTokenStore = EsportsTestTokenStore(),
                             provider: EsportsTestProvider = EsportsTestProvider(),
                             cache: EsportsTestCache? = nil,
                             startsServices: Bool = true) -> (EsportsRuntime, EsportsTestCalendar, UserDefaults) {
        let suite = "EsportsRuntimeTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        let eventStore = EKEventStore(), reference = reference
        let calendar = EsportsTestCalendar(store: eventStore)
        let runtime = EsportsRuntime(eventStore: eventStore, mutations: CalendarMutationCoordinator(store: calendar), defaults: defaults,
            client: provider, tokenStore: tokens, cacheStore: cache, startsServices: startsServices, calendarSource: calendar, now: { reference })
        runtime.configure(settings: configuredSettings(), selectedCalendarIDs: ["target"], hasEventsAccess: true)
        return (runtime, calendar, defaults)
    }
}
