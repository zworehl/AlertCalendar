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
        return keys
    }
}
