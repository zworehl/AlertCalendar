import Foundation

@MainActor
final class FootballLogoLoadingCoordinator {
    enum Kind: Hashable, Sendable { case team, competition }
    struct Key: Hashable, Sendable {
        let kind: Kind
        let id: String
    }
    struct Request: Sendable {
        let key: Key
        let remoteURL: URL
    }

    private let imageStore: FootballImageStore
    private let publish: @MainActor (Key, String) -> Void
    private let now: @MainActor () -> Date
    private var pending: [Key: URL] = [:]
    private var requested: [Key: URL] = [:]
    private var completed: [Key: (url: URL, checkedAt: Date)] = [:]
    private var inFlight: [Key: URL] = [:]
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(imageStore: FootballImageStore, now: @escaping @MainActor () -> Date = { Date() }, publish: @escaping @MainActor (Key, String) -> Void) {
        self.imageStore = imageStore
        self.now = now
        self.publish = publish
    }

    func enqueue(_ requests: [Request]) {
        for request in requests {
            let key = request.key
            requested[key] = request.remoteURL
            if let cached = completed[key], cached.url == request.remoteURL,
               now().timeIntervalSince(cached.checkedAt) >= 0,
               now().timeIntervalSince(cached.checkedAt) < 15 * 60 {
                pending[key] = nil
                continue
            }
            if pending[key] == request.remoteURL || inFlight[key] == request.remoteURL { continue }
            pending[key] = request.remoteURL
        }
        guard task == nil, !pending.isEmpty else { return }
        let generation = self.generation
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.generation == generation { task = nil } }
            while !pending.isEmpty, !Task.isCancelled, self.generation == generation {
                let batch = Array(pending.prefix(4)).map { Request(key: $0.key, remoteURL: $0.value) }
                for request in batch {
                    pending[request.key] = nil
                    inFlight[request.key] = request.remoteURL
                }
                let store = imageStore
                let results = await withTaskGroup(of: (Request, URL?).self) { group in
                    for request in batch {
                        group.addTask { (request, await store.localFileURL(for: request.remoteURL)) }
                    }
                    var values: [(Request, URL?)] = []
                    for await value in group { values.append(value) }
                    return values
                }
                guard !Task.isCancelled, self.generation == generation else { return }
                for (request, localURL) in results {
                    inFlight[request.key] = nil
                    guard !Task.isCancelled, requested[request.key] == request.remoteURL, let localURL else { continue }
                    guard await FootballLocalImageCache.loadImage(for: localURL.path) != nil,
                          !Task.isCancelled, self.generation == generation,
                          requested[request.key] == request.remoteURL else { continue }
                    completed[request.key] = (request.remoteURL, now())
                    publish(request.key, localURL.path)
                }
            }
        }
    }

    func resolveLocally(_ key: Key) {
        requested[key] = nil
        pending[key] = nil
        completed[key] = nil
    }

    func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        pending.removeAll()
        inFlight.removeAll()
        requested.removeAll()
    }
}

extension CalendarMonitor {
    func scheduleFootballLogoLoading(for matches: [FootballFixtureMatch]) {
        if footballState.logoLoadingCoordinator == nil {
            footballState.logoLoadingCoordinator = FootballLogoLoadingCoordinator(imageStore: footballImageStore) { [weak self] key, path in
                guard let self else { return }
                switch key.kind {
                case .team: footballLocalLogoPathsByTeamID[key.id] = path
                case .competition: footballLocalLogoPathsByCompetitionSlug[key.id] = path
                }
                updateMenuBarState(now: fixedSecondNow(), settings: snapshotSettings())
            }
        }
        var requests: [FootballLogoLoadingCoordinator.Request] = []
        let teams = matches.flatMap { [$0.homeTeam, $0.awayTeam] }
        for team in teams {
            if team.isNational, let flag = FootballNationalLogoResolver.localFlagImageURL(
                teamID: team.id, name: team.name, abbreviation: team.abbreviation, countryName: team.countryName
            ) {
                footballState.logoLoadingCoordinator?.resolveLocally(.init(kind: .team, id: team.id))
                footballLocalLogoPathsByTeamID[team.id] = flag.path
            } else if let url = team.logoURL {
                requests.append(.init(key: .init(kind: .team, id: team.id), remoteURL: url))
            }
        }
        for match in matches {
            if let url = match.competitionLogoURL {
                requests.append(.init(key: .init(kind: .competition, id: match.competitionSlug), remoteURL: url))
            }
        }
        footballState.logoLoadingCoordinator?.enqueue(requests)
    }
}
