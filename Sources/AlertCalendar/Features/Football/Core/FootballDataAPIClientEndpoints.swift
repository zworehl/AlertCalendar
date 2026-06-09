import Foundation

extension FootballDataAPIClient {
    static func goalScorersCacheKey(for match: FootballFixtureMatch) -> String {
        let statusDetail = match.statusDetailText ?? ""
        let statusPeriod = match.statusPeriod.map(String.init) ?? "n/a"
        return "\(match.id)|\(match.homeScore)|\(match.awayScore)|\(match.statusText)|\(statusDetail)|\(statusPeriod)"
    }

    static func statisticsCacheKey(for match: FootballFixtureMatch) -> String {
        let statusPeriod = match.statusPeriod.map(String.init) ?? "n/a"
        return "\(match.id)|\(match.homeScore)|\(match.awayScore)|\(match.statusText)|\(statusPeriod)"
    }

    static func summaryRootCacheKey(url: URL, match: FootballFixtureMatch) -> String {
        let statusDetail = match.statusDetailText ?? ""
        let statusPeriod = match.statusPeriod.map(String.init) ?? "n/a"
        return "\(url.absoluteString)|\(match.id)|\(match.homeScore)|\(match.awayScore)|\(match.statusText)|\(match.statusState.rawValue)|\(statusDetail)|\(statusPeriod)"
    }

    static func summaryURLs(for match: FootballFixtureMatch) -> [URL] {
        var urls: [URL] = []

        let leagueSlug = match.competitionSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leagueSlug.isEmpty,
           var components = URLComponents(
               url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/\(leagueSlug)/summary")!,
               resolvingAgainstBaseURL: false
           ) {
            components.queryItems = [URLQueryItem(name: "event", value: match.id)]
            if let url = components.url {
                urls.append(url)
            }
        }

        if var allComponents = URLComponents(
            url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/all/summary")!,
            resolvingAgainstBaseURL: false
        ) {
            allComponents.queryItems = [URLQueryItem(name: "event", value: match.id)]
            if let allURL = allComponents.url, !urls.contains(allURL) {
                urls.append(allURL)
            }
        }

        return urls
    }

    static func scoreboardURL(
        slug: String,
        dateRange: (Date, Date)?
    ) -> URL? {
        var components = URLComponents(
            url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/\(slug)/scoreboard")!,
            resolvingAgainstBaseURL: false
        )

        if let dateRange {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .autoupdatingCurrent
            formatter.dateFormat = "yyyyMMdd"
            components?.queryItems = [
                URLQueryItem(
                    name: "dates",
                    value: "\(formatter.string(from: dateRange.0))-\(formatter.string(from: dateRange.1))"
                ),
            ]
        }

        return components?.url
    }
}
