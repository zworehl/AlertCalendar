import Foundation

struct EsportsSettings: Codable, Equatable, Sendable {
    var providerGames: Set<EsportsGame> = [.leagueOfLegends]
    var targetCalendarID = ""
    var autoAddCompetitionIDs: Set<String> = []
    var alertLeadMinutes = 15
    var lookbackDays = 90
    var lookaheadDays = 90

    static let defaults = EsportsSettings()

    var normalized: Self {
        var result = self
        result.providerGames = Set(providerGames.filter { $0.providerSlug != nil })
        result.targetCalendarID = targetCalendarID.trimmingCharacters(in: .whitespacesAndNewlines)
        result.autoAddCompetitionIDs = Set(autoAddCompetitionIDs.compactMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        })
        result.alertLeadMinutes = min(max(alertLeadMinutes, 0), 10_080)
        result.lookbackDays = min(max(lookbackDays, 0), 365)
        result.lookaheadDays = min(max(lookaheadDays, 1), 180)
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case providerGames, targetCalendarID, autoAddCompetitionIDs
        case alertLeadMinutes, lookbackDays, lookaheadDays
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if let games = try values.decodeIfPresent([String].self, forKey: .providerGames) {
            providerGames = Set(games.compactMap(EsportsGame.init(rawValue:)))
        }
        targetCalendarID = try values.decodeIfPresent(String.self, forKey: .targetCalendarID) ?? ""
        autoAddCompetitionIDs = Set(try values.decodeIfPresent([String].self, forKey: .autoAddCompetitionIDs) ?? [])
        alertLeadMinutes = try values.decodeIfPresent(Int.self, forKey: .alertLeadMinutes) ?? 15
        lookbackDays = try values.decodeIfPresent(Int.self, forKey: .lookbackDays) ?? 90
        lookaheadDays = try values.decodeIfPresent(Int.self, forKey: .lookaheadDays) ?? 90
        self = normalized
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        let settings = normalized
        try values.encode(settings.providerGames.map(\.rawValue).sorted(), forKey: .providerGames)
        try values.encode(settings.targetCalendarID, forKey: .targetCalendarID)
        try values.encode(settings.autoAddCompetitionIDs.sorted(), forKey: .autoAddCompetitionIDs)
        try values.encode(settings.alertLeadMinutes, forKey: .alertLeadMinutes)
        try values.encode(settings.lookbackDays, forKey: .lookbackDays)
        try values.encode(settings.lookaheadDays, forKey: .lookaheadDays)
    }
}

extension AppSettingsStore {
    func esportsSettings() -> EsportsSettings {
        guard let data = defaults.data(forKey: DefaultsKeys.esportsSettings),
              let settings = try? JSONDecoder().decode(EsportsSettings.self, from: data) else { return .defaults }
        return settings.normalized
    }

    func saveEsportsSettings(_ settings: EsportsSettings) {
        if let data = try? JSONEncoder().encode(settings.normalized) {
            defaults.set(data, forKey: DefaultsKeys.esportsSettings)
        }
    }
}
