import Foundation

enum FootballMatchOutcomeProbabilitySource: String, Codable, Hashable, Sendable {
    case marketOdds
    case liveMarketOdds
    case heuristic
    case finalResult
}

enum FootballMatchOutcomeProbabilityScope: String, Codable, Hashable, Sendable {
    case regulationTime
    case extraTimePossible
    case decisiveResult
}

struct FootballMatchOutcomeProbabilities: Codable, Hashable, Sendable {
    let homeWin: Double
    let draw: Double
    let awayWin: Double
    let source: FootballMatchOutcomeProbabilitySource
    let scope: FootballMatchOutcomeProbabilityScope
    let providerName: String?
    let observedAt: Date?
    let observedHomeScore: Int?
    let observedAwayScore: Int?
    let observedStatusPeriod: Int?

    init?(
        homeWin: Double,
        draw: Double,
        awayWin: Double,
        source: FootballMatchOutcomeProbabilitySource,
        scope: FootballMatchOutcomeProbabilityScope,
        providerName: String? = nil,
        observedAt: Date? = nil,
        observedHomeScore: Int? = nil,
        observedAwayScore: Int? = nil,
        observedStatusPeriod: Int? = nil
    ) {
        let values = [homeWin, draw, awayWin]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }

        let total = values.reduce(0, +)
        guard total > 0 else { return nil }

        self.homeWin = homeWin / total
        self.draw = draw / total
        self.awayWin = awayWin / total
        self.source = source
        self.scope = scope
        self.providerName = providerName
        self.observedAt = observedAt
        self.observedHomeScore = observedHomeScore
        self.observedAwayScore = observedAwayScore
        self.observedStatusPeriod = observedStatusPeriod
    }

    func replacing(
        source: FootballMatchOutcomeProbabilitySource? = nil,
        scope: FootballMatchOutcomeProbabilityScope? = nil
    ) -> FootballMatchOutcomeProbabilities {
        FootballMatchOutcomeProbabilities(
            homeWin: homeWin,
            draw: draw,
            awayWin: awayWin,
            source: source ?? self.source,
            scope: scope ?? self.scope,
            providerName: providerName,
            observedAt: observedAt,
            observedHomeScore: observedHomeScore,
            observedAwayScore: observedAwayScore,
            observedStatusPeriod: observedStatusPeriod
        ) ?? self
    }
}
