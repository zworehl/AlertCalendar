import Foundation

extension FootballDataAPIClient {
    static func cardCounts(from root: [String: Any]) -> (homeYellowCards: Int, awayYellowCards: Int, homeRedCards: Int, awayRedCards: Int) {
        let teams = ((root["boxscore"] as? [String: Any])?["teams"] as? [[String: Any]]) ?? []
        let home = teams.first(where: { stringValue($0["homeAway"])?.lowercased() == "home" })
        let away = teams.first(where: { stringValue($0["homeAway"])?.lowercased() == "away" })

        return (
            homeYellowCards: statisticValue(named: "yellowCards", from: home),
            awayYellowCards: statisticValue(named: "yellowCards", from: away),
            homeRedCards: statisticValue(named: "redCards", from: home),
            awayRedCards: statisticValue(named: "redCards", from: away)
        )
    }

    static func statisticValue(named name: String, from teamBoxscore: [String: Any]?) -> Int {
        let statistics = teamBoxscore?["statistics"] as? [[String: Any]] ?? []
        guard let entry = statistics.first(where: { stringValue($0["name"])?.caseInsensitiveCompare(name) == .orderedSame }) else {
            return 0
        }

        if let numericValue = intValue(entry["value"]) {
            return numericValue
        }

        return intValue(entry["displayValue"]) ?? 0
    }

    static func teamStatisticsMap(from entry: [String: Any]) -> [String: (label: String, value: String)] {
        let raw = entry["statistics"] as? [[String: Any]] ?? []
        var mapped: [String: (label: String, value: String)] = [:]
        for stat in raw {
            guard let name = stringValue(stat["name"])?.lowercased() else { continue }
            guard let value = stringValue(stat["displayValue"]) else { continue }
            let label = stringValue(stat["label"]) ?? name
            mapped[name] = (label: label, value: value)
        }
        return mapped
    }

    static func mergeStatistics(
        home: [String: (label: String, value: String)],
        away: [String: (label: String, value: String)],
        homeSubstitutions: Int,
        awaySubstitutions: Int
    ) -> [FootballMatchStatistic] {
        let preferred: [(name: String, label: String)] = [
            ("possessionpct", "Possession"),
            ("totalshots", "Shots"),
            ("shotsontarget", "Shots On Target"),
            ("woncorners", "Corner Kicks"),
            ("offsides", "Offsides"),
            ("foulscommitted", "Fouls"),
            ("yellowcards", "Yellow Cards"),
            ("redcards", "Red Cards"),
            ("saves", "Saves"),
        ]

        var merged: [FootballMatchStatistic] = []
        for item in preferred {
            let homeValue = formatStatisticValue(name: item.name, rawValue: home[item.name]?.value ?? "--")
            let awayValue = formatStatisticValue(name: item.name, rawValue: away[item.name]?.value ?? "--")
            merged.append(
                FootballMatchStatistic(
                    id: item.name,
                    label: item.label,
                    homeValue: homeValue,
                    awayValue: awayValue
                )
            )
        }

        merged.append(
            FootballMatchStatistic(
                id: "substitutions",
                label: "Substitutions",
                homeValue: "\(homeSubstitutions)",
                awayValue: "\(awaySubstitutions)"
            )
        )
        return merged
    }

    static func teamIdentifier(from entry: [String: Any]) -> String? {
        let team = entry["team"] as? [String: Any] ?? [:]
        return stringValue(team["id"])
    }

    static func substitutionCountsByTeam(from keyEvents: [[String: Any]]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for event in keyEvents {
            let type = ((event["type"] as? [String: Any])?["type"] as? String)?.lowercased() ?? ""
            guard type.contains("substitution") else { continue }
            guard let teamID = stringValue((event["team"] as? [String: Any])?["id"]) else { continue }
            counts[teamID, default: 0] += 1
        }
        return counts
    }

    static func formatStatisticValue(name: String, rawValue: String) -> String {
        if rawValue == "--" {
            return rawValue
        }
        if name == "possessionpct" {
            return rawValue.contains("%") ? rawValue : "\(rawValue)%"
        }
        return rawValue
    }
}
