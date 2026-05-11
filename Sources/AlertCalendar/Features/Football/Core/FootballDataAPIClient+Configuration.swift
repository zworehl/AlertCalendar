import Foundation

extension FootballDataAPIClient {
    static let requestTimeout: TimeInterval = 8
    static let resourceTimeout: TimeInterval = 20
    static let scoreboardPageCacheTTL: TimeInterval = 45
    static let scoreboardPageCacheLimit = 160
    static let teamCacheTTL: TimeInterval = 30 * 24 * 60 * 60
    static let summaryRootCacheTTL: TimeInterval = 15
    static let summaryRootCacheLimit = 120
    static let summaryPreBufferBeforeKickoff: TimeInterval = 15 * 60
    static let summaryPreBufferAfterKickoff: TimeInterval = 3 * 60 * 60
    static let delayedLiveDataWarningAfterKickoff: TimeInterval = 15 * 60

    static let clubCountryByLeaguePrefix: [String: String] = [
        "arg": "Argentina",
        "aut": "Austria",
        "bel": "Belgium",
        "bra": "Brazil",
        "col": "Colombia",
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
