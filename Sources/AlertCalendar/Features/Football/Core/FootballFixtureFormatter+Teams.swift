import Foundation

extension FootballFixtureFormatter {
    static func teamDisplayName(for team: FootballTeamSummary) -> String {
        guard !isUnknownTeam(team) else { return "TBD" }
        let name = team.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? teamDisplayIdentifier(for: team) : name
    }

    static func calendarIdentityKeys(for match: FootballFixtureMatch) -> Set<String> {
        // Keep recognizing calendar events created with the original three-letter titles.
        var keys: Set<String> = [calendarIdentityKey(for: match)]
        let teams = [match.homeTeam, match.awayTeam]
        keys.insert(teams.map { String(teamDisplayIdentifier(for: $0).prefix(3)) }.joined(separator: "|"))
        keys.insert(teams.map { compactIdentifier(teamDisplayName(for: $0)) }.joined(separator: "|"))
        let providerIdentifiers = teams.map { team in
            let code = compactIdentifier(team.abbreviation)
            return code.isEmpty ? compactIdentifier(team.name) : code
        }
        keys.insert(providerIdentifiers.joined(separator: "|"))
        keys.insert(providerIdentifiers.map { String($0.prefix(3)) }.joined(separator: "|"))
        for homeCode in FootballTeamBroadcastCode.calendarRecoveryIdentifiers(for: match.homeTeam) {
            for awayCode in FootballTeamBroadcastCode.calendarRecoveryIdentifiers(for: match.awayTeam) {
                keys.insert("\(homeCode)|\(awayCode)")
            }
        }
        return keys
    }
}
