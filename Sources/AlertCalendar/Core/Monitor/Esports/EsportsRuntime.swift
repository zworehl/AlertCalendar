import Combine
import EventKit
import Foundation

enum EsportsMatchPresence: Equatable, Sendable { case absent, external, managed }

/// Independent feature runtime. Construction/configuration never touch Calendar,
/// network, or disk, including the settings smoke environment.
@MainActor
final class EsportsRuntime: ObservableObject {
    @Published var localEvents: [LocalGamingCalendarEvent] = []
    @Published var providerMatches: [EsportsMatch] = []
    @Published var isRefreshing = false
    @Published var lastValidatedAt: Date?
    @Published var errorMessage: String?
    @Published var managedMatchIDs: Set<String> = []
    var onCalendarAdded: ((String) -> Void)?

    let eventStore: EKEventStore
    let mutations: CalendarMutationCoordinator
    let defaults: UserDefaults
    let calendarSource: any EsportsCalendarReading
    let client: any EsportsProviding
    let cacheStore: (any EsportsCaching)?
    let startsServices: Bool
    let now: @Sendable () -> Date
    var settings = EsportsSettings.defaults
    var selectedCalendarIDs: Set<String> = []
    var hasEventsAccess = false
    var records: [String: ManagedEsportsEventRecord] = [:]
    var dismissedMatchIDs: Set<String> = []
    var matchesByID: [String: EsportsMatch] = [:]
    var didRestore = false
    var didRestoreRecords = false
    var generation = 0
    var stopped = false
    var lastLocalRefresh: Date?
    var lastProviderFetch: [EsportsGame: Date] = [:]
    var validatedAtByGame: [EsportsGame: Date] = [:]
    var providerRetryAt: [EsportsGame: Date] = [:]
    var refreshTask: Task<Void, Never>?
    var forceRefreshRequested = false
    var cacheWriteTask: Task<Void, Never>?
    var openTask: Task<Void, Never>?
    static let recordsKey = "esports.managedEvents.v1"
    static let dismissedKey = "esports.dismissedMatches.v1"

    init(eventStore: EKEventStore, mutations: CalendarMutationCoordinator, defaults: UserDefaults,
         client: any EsportsProviding = PublicEsportsCalendarClient(),
         cacheStore: (any EsportsCaching)? = nil,
         startsServices: Bool = true,
         calendarSource: (any EsportsCalendarReading)? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.eventStore = eventStore; self.mutations = mutations; self.defaults = defaults
        self.client = client
        self.cacheStore = cacheStore ?? (startsServices && defaults === UserDefaults.standard ? EsportsCacheStore() : nil)
        self.startsServices = startsServices
        self.calendarSource = calendarSource ?? EventKitEsportsCalendarSource(eventStore: eventStore)
        self.now = now
    }

    func configure(settings: EsportsSettings, selectedCalendarIDs: Set<String>, hasEventsAccess: Bool) {
        let normalized = settings.normalized
        guard self.settings != normalized || self.selectedCalendarIDs != selectedCalendarIDs || self.hasEventsAccess != hasEventsAccess else { return }
        let fetchScopeChanged = self.settings.providerGames != normalized.providerGames
            || self.settings.lookbackDays != normalized.lookbackDays || self.settings.lookaheadDays != normalized.lookaheadDays
        invalidate()
        self.settings = normalized; self.selectedCalendarIDs = selectedCalendarIDs; self.hasEventsAccess = hasEventsAccess
        if fetchScopeChanged {
            lastProviderFetch = [:]; validatedAtByGame = [:]; lastValidatedAt = nil
        }
        lastLocalRefresh = nil
        // Never display a prior Focus selection while its replacement is read.
        if !hasEventsAccess || selectedCalendarIDs.isEmpty { if !localEvents.isEmpty { localEvents = [] } }
        else { localEvents = localEvents.filter { selectedCalendarIDs.contains($0.calendarID) && EsportsCatalog.supports($0.game) } }
        publishMatches()
    }

    func refresh(force: Bool = false) async {
        guard startsServices, !stopped else { return }
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

    func stop() {
        stopped = true; invalidate(); openTask?.cancel(); openTask = nil
    }

    func prepareForTermination() async {
        let active = refreshTask
        stop()
        await active?.value
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
        switch error as? EsportsFeedError {
        case .rateLimited, .requestBudget, .retryDeferred: L10n.text("Esports calendar requests are paused. Cached events remain available.")
        default: L10n.text("Could not refresh the esports calendar. Cached events remain available.")
        }
    }
}
