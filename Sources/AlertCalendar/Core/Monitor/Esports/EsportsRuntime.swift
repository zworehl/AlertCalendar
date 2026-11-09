import Combine
import EventKit
import Foundation

enum EsportsMatchPresence: Equatable, Sendable { case absent, external, managed }

actor EsportsCredentialVault {
    private let store: any EsportsTokenStoring
    private var latestRevision = 0
    init(store: any EsportsTokenStoring) { self.store = store }
    func load() throws -> String? { try store.loadToken() }
    func save(_ token: String, revision: Int) throws -> Bool {
        guard revision >= latestRevision else { return false }
        latestRevision = revision; try store.saveToken(token); return true
    }
    func remove(revision: Int) throws -> Bool {
        guard revision >= latestRevision else { return false }
        latestRevision = revision; try store.removeToken(); return true
    }
    func finish(revision: Int) { latestRevision = max(latestRevision, revision) }
}

/// Independent feature runtime. Construction/configuration never touch Calendar,
/// Keychain, network, or disk, including the settings smoke environment.
@MainActor
final class EsportsRuntime: ObservableObject {
    @Published var localEvents: [LocalGamingCalendarEvent] = []
    @Published var providerMatches: [EsportsMatch] = []
    @Published var isRefreshing = false
    @Published var isConnected = false
    @Published var lastValidatedAt: Date?
    @Published var errorMessage: String?
    @Published var managedMatchIDs: Set<String> = []
    var onCalendarAdded: ((String) -> Void)?

    let eventStore: EKEventStore
    let mutations: CalendarMutationCoordinator
    let defaults: UserDefaults
    let calendarSource: any EsportsCalendarReading
    let client: any EsportsProviding
    let credentials: EsportsCredentialVault
    let cacheStore: (any EsportsCaching)?
    let startsServices: Bool
    let now: @Sendable () -> Date
    var settings = EsportsSettings.defaults
    var selectedCalendarIDs: Set<String> = []
    var hasEventsAccess = false
    var records: [String: ManagedEsportsEventRecord] = [:]
    var dismissedMatchIDs: Set<String> = []
    var matchesByID: [String: EsportsMatch] = [:]
    var token: String?
    var connectionRevision: Int?
    var didRestore = false
    var didRestoreRecords = false
    var generation = 0
    var stopped = false
    var lastLocalRefresh: Date?
    var lastProviderFetch: [EsportsGame: Date] = [:]
    var providerRetryAt: [EsportsGame: Date] = [:]
    var refreshTask: Task<Void, Never>?
    var forceRefreshRequested = false
    var cacheWriteTask: Task<Void, Never>?
    var openTask: Task<Void, Never>?
    static let recordsKey = "esports.managedEvents.v1"
    static let dismissedKey = "esports.dismissedMatches.v1"

    init(eventStore: EKEventStore, mutations: CalendarMutationCoordinator, defaults: UserDefaults,
         client: any EsportsProviding = PandaScoreClient(),
         tokenStore: any EsportsTokenStoring = PandaScoreTokenKeychainStore(),
         cacheStore: (any EsportsCaching)? = nil,
         startsServices: Bool = true,
         calendarSource: (any EsportsCalendarReading)? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.eventStore = eventStore; self.mutations = mutations; self.defaults = defaults
        self.client = client; self.credentials = EsportsCredentialVault(store: tokenStore)
        self.cacheStore = cacheStore ?? (startsServices && defaults === UserDefaults.standard ? EsportsCacheStore() : nil)
        self.startsServices = startsServices
        self.calendarSource = calendarSource ?? EventKitEsportsCalendarSource(eventStore: eventStore)
        self.now = now
    }

    func configure(settings: EsportsSettings, selectedCalendarIDs: Set<String>, hasEventsAccess: Bool) {
        let normalized = settings.normalized
        guard self.settings != normalized || self.selectedCalendarIDs != selectedCalendarIDs || self.hasEventsAccess != hasEventsAccess else { return }
        invalidate()
        self.settings = normalized; self.selectedCalendarIDs = selectedCalendarIDs; self.hasEventsAccess = hasEventsAccess
        lastLocalRefresh = nil
        // Never display a prior Focus selection while its replacement is read.
        if !hasEventsAccess || selectedCalendarIDs.isEmpty { if !localEvents.isEmpty { localEvents = [] } }
        else { localEvents = localEvents.filter { selectedCalendarIDs.contains($0.calendarID) && EsportsCatalog.supports($0.game) } }
        publishMatches()
    }

    func refresh(force: Bool = false) async {
        guard startsServices, !stopped, connectionRevision == nil else { return }
        if let refreshTask {
            forceRefreshRequested = forceRefreshRequested || force
            await refreshTask.value; return
        }
        let revision = generation
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            self.forceRefreshRequested = false
            await self.performRefresh(force: force, revision: revision)
            if self.forceRefreshRequested, self.current(revision) {
                self.forceRefreshRequested = false
                await self.performRefresh(force: true, revision: revision)
            }
        }
        refreshTask = task
        await task.value
        if revision == generation { refreshTask = nil; isRefreshing = false }
    }

    func connect(token candidate: String) async {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PandaScoreTokenKeychainStore.isValid(candidate), !stopped else {
            errorMessage = L10n.text("Enter a valid PandaScore token."); return
        }
        invalidate()
        let revision = generation
        connectionRevision = revision
        isRefreshing = true
        defer {
            if connectionRevision == revision { connectionRevision = nil }
            if revision == generation { isRefreshing = false }
        }
        let game = settings.providerGames.sorted { $0.rawValue < $1.rawValue }.first ?? .leagueOfLegends
        let window = dateWindow()
        do {
            let result = try await client.load(game: game, from: window.0, to: window.1, token: candidate, trackedIDs: [])
            guard current(revision) else { return }
            guard !result.issues.contains(where: { $0.kind == .unauthorized || $0.kind == .requestFailed || $0.kind == .unavailable || $0.kind == .rateLimited || $0.kind == .requestBudget }) else {
                errorMessage = L10n.text("Could not validate the PandaScore connection. Try again later."); return
            }
            guard try await credentials.save(candidate, revision: revision) else { return }
            guard current(revision) else { didRestore = false; return }
            token = candidate; isConnected = true; errorMessage = nil
            merge(result.matches); publishMatches(); scheduleCacheSave()
            lastProviderFetch[game] = now()
            if result.isComplete { lastValidatedAt = result.fetchedAt }
        } catch {
            guard current(revision) else { return }
            errorMessage = safeError(error)
        }
    }

    func disconnect() async {
        invalidate()
        let revision = generation
        connectionRevision = revision
        token = nil; isConnected = false
        defer { if connectionRevision == revision { connectionRevision = nil } }
        do {
            guard try await credentials.remove(revision: revision) else { return }
            guard current(revision) else { return }
            token = nil; isConnected = false; errorMessage = nil
            lastProviderFetch = [:]; providerRetryAt = [:]
        } catch {
            guard current(revision) else { return }
            errorMessage = L10n.text("Could not remove the PandaScore token from Keychain.")
        }
    }

    func stop() {
        stopped = true; invalidate(); openTask?.cancel(); openTask = nil
    }

    func prepareForTermination() async {
        let active = refreshTask
        stop()
        await active?.value
        await credentials.finish(revision: generation)
        await cacheWriteTask?.value
    }

    func current(_ revision: Int) -> Bool { !stopped && !Task.isCancelled && revision == generation }

    func invalidate() {
        generation += 1; refreshTask?.cancel(); refreshTask = nil; isRefreshing = false; forceRefreshRequested = false
    }

    func dateWindow() -> (Date, Date) {
        let reference = now()
        return (reference.addingTimeInterval(-Double(settings.lookbackDays) * 86_400),
                reference.addingTimeInterval(Double(settings.lookaheadDays) * 86_400))
    }

    func merge(_ matches: [EsportsMatch]) {
        for match in matches where match.providerID > 0 && match.game.providerSlug != nil {
            if let previous = matchesByID[match.id], previous.fetchedAt > match.fetchedAt { continue }
            matchesByID[match.id] = match
        }
    }

    func publishMatches() {
        let window = dateWindow()
        let values = matchesByID.values.filter { match in
            if records[match.id] != nil { return true }
            guard settings.providerGames.contains(match.game) else { return false }
            if match.status == .postponed { return true }
            guard let start = match.beginAt ?? match.scheduledAt else { return true }
            return start >= window.0 && start <= window.1
        }.sorted {
            let first = $0.beginAt ?? $0.scheduledAt ?? .distantFuture
            let second = $1.beginAt ?? $1.scheduledAt ?? .distantFuture
            return first == second ? $0.id < $1.id : first < second
        }
        if providerMatches != values { providerMatches = values }
        let ids = Set(records.keys)
        if managedMatchIDs != ids { managedMatchIDs = ids }
    }

    func scheduleCacheSave() {
        guard let cacheStore, !stopped else { return }
        let previous = cacheWriteTask
        let snapshot = Array(matchesByID.values)
        cacheWriteTask = Task {
            await previous?.value
            try? await cacheStore.save(matches: snapshot)
        }
    }

    func safeError(_ error: any Error) -> String {
        switch error as? PandaScoreError {
        case .unauthorized: L10n.text("PandaScore rejected the token. Check your connection settings.")
        case .rateLimited, .requestBudget, .retryDeferred: L10n.text("PandaScore requests are paused. Cached events remain available.")
        default: L10n.text("Could not refresh PandaScore. Cached events remain available.")
        }
    }
}
