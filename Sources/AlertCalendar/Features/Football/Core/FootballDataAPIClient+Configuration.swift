import Foundation

extension FootballDataAPIClient {
    static let requestTimeout: TimeInterval = 8
    static let resourceTimeout: TimeInterval = 20
    static let scoreboardDateRangeChunkDays = 14
    static let scoreboardCurrentDayCacheTTL: TimeInterval = 5 * 60
    static let scoreboardDistantCacheTTL: TimeInterval = 60 * 60
    static let scoreboardPageCacheLimit = 320
    static let teamCacheTTL: TimeInterval = 30 * 24 * 60 * 60
    static let summaryRootCacheTTL: TimeInterval = 15
    static let summaryRootCacheLimit = 120
    static let summaryPreBufferBeforeKickoff: TimeInterval = 15 * 60
    static let summaryPreBufferAfterKickoff: TimeInterval = 3 * 60 * 60
    static let delayedLiveDataWarningAfterKickoff: TimeInterval = 15 * 60

    static func scoreboardPageCacheTTL(for url: URL, now: Date = Date()) -> TimeInterval {
        guard let dates = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "dates" })?
            .value else {
            return scoreboardCurrentDayCacheTTL
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyyMMdd"
        let today = formatter.string(from: now)
        let bounds = dates.split(separator: "-", maxSplits: 1).map(String.init)
        guard bounds.count == 2,
              let start = bounds.first,
              let end = bounds.last else {
            return scoreboardCurrentDayCacheTTL
        }

        return start <= today && today <= end
            ? scoreboardCurrentDayCacheTTL
            : scoreboardDistantCacheTTL
    }

    static let clubCountryByLeaguePrefix: [String: String] = [
        "arg": "Argentina",
        "aut": "Austria",
        "bel": "Belgium",
        "bra": "Brazil",
        "col": "Colombia",
        "crc": "Costa Rica",
        "cze": "Czech Republic",
        "den": "Denmark",
        "eng": "England",
        "esp": "Spain",
        "fra": "France",
        "ger": "Germany",
        "gre": "Greece",
        "irl": "Republic of Ireland",
        "ita": "Italy",
        "jpn": "Japan",
        "mex": "Mexico",
        "ned": "Netherlands",
        "nir": "Northern Ireland",
        "nor": "Norway",
        "pol": "Poland",
        "por": "Portugal",
        "rou": "Romania",
        "sco": "Scotland",
        "srb": "Serbia",
        "sui": "Switzerland",
        "swe": "Sweden",
        "tur": "Turkey",
        "ukr": "Ukraine",
        "usa": "United States",
        "wal": "Wales",
    ]

    static let britishFootballCountries: Set<String> = [
        "england",
        "scotland",
        "wales",
        "northern ireland",
        "united kingdom",
        "great britain",
    ]

    static let countryIdentityAliases: [String: String] = [
        "usa": "united states",
        "us": "united states",
        "u s a": "united states",
        "turkiye": "turkey",
        "great britain": "united kingdom",
    ]

    static let recognizedCountryLookupKeys: Set<String> = {
        let locale = Locale(identifier: "en_US_POSIX")
        var values = Set<String>()
        for regionCode in Locale.Region.isoRegions.map(\.identifier) {
            guard let name = locale.localizedString(forRegionCode: regionCode) else { continue }
            values.insert(normalizedLookupKey(name))
        }
        return values
    }()

    static let genericClubIdentityTokens: Set<String> = [
        "ac",
        "afc",
        "as",
        "athletic",
        "atletico",
        "cf",
        "city",
        "club",
        "de",
        "del",
        "fc",
        "if",
        "inter",
        "real",
        "sc",
        "sporting",
        "sv",
        "the",
        "united",
    ]
}
