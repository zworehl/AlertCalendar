import Foundation

enum FootballFixtureStatusState: String, Hashable {
    case scheduled
    case inProgress
    case finished
    case unknown
}

enum FootballFixtureStatusReliability: String, Hashable {
    case reported
    case awaitingLiveData
    case delayedLiveData
}

enum FootballCompetitionCategory: String, CaseIterable, Identifiable {
    case clubCompetitions
    case nationalTeams

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clubCompetitions:
            return "Club Competitions"
        case .nationalTeams:
            return "National Teams"
        }
    }
}

struct FootballCompetitionPreset: Identifiable, Hashable {
    let slug: String
    let title: String
    let lookbackDays: Int
    let lookaheadDays: Int
    let category: FootballCompetitionCategory

    var id: String { slug }

    private static let suggestionWindowDays = 30

    init(
        slug: String,
        title: String,
        lookbackDays: Int,
        lookaheadDays: Int,
        category: FootballCompetitionCategory = .clubCompetitions
    ) {
        self.slug = slug
        self.title = title
        self.lookbackDays = lookbackDays
        self.lookaheadDays = lookaheadDays
        self.category = category
    }

    static let premierLeague = FootballCompetitionPreset(
        slug: "eng.1",
        title: "Premier League",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let laLiga = FootballCompetitionPreset(
        slug: "esp.1",
        title: "LaLiga",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let brasileiraoSerieA = FootballCompetitionPreset(
        slug: "bra.1",
        title: "Brasileirao Serie A",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let serieA = FootballCompetitionPreset(
        slug: "ita.1",
        title: "Serie A",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let bundesliga = FootballCompetitionPreset(
        slug: "ger.1",
        title: "Bundesliga",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let ligue1 = FootballCompetitionPreset(
        slug: "fra.1",
        title: "Ligue 1",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let primeiraLiga = FootballCompetitionPreset(
        slug: "por.1",
        title: "Primeira Liga",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let ligaProfesionalArgentina = FootballCompetitionPreset(
        slug: "arg.1",
        title: "Liga Argentina",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let eredivisie = FootballCompetitionPreset(
        slug: "ned.1",
        title: "Eredivisie",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let primeraA = FootballCompetitionPreset(
        slug: "col.1",
        title: "Primera A",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let majorLeagueSoccer = FootballCompetitionPreset(
        slug: "usa.1",
        title: "MLS",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let worldCup = FootballCompetitionPreset(
        slug: "fifa.world",
        title: "FIFA World Cup",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays,
        category: .nationalTeams
    )

    static let fifaFriendlies = FootballCompetitionPreset(
        slug: "fifa.friendly",
        title: "FIFA Friendlies",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays,
        category: .nationalTeams
    )

    static let championsLeague = FootballCompetitionPreset(
        slug: "uefa.champions",
        title: "UEFA Champions League",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let europaLeague = FootballCompetitionPreset(
        slug: "uefa.europa",
        title: "UEFA Europa League",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let superCup = FootballCompetitionPreset(
        slug: "uefa.super_cup",
        title: "UEFA Super Cup",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let europeanChampionship = FootballCompetitionPreset(
        slug: "uefa.euro",
        title: "UEFA European Championship",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays,
        category: .nationalTeams
    )

    static let copaAmerica = FootballCompetitionPreset(
        slug: "conmebol.america",
        title: "Copa America",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays,
        category: .nationalTeams
    )

    static let libertadores = FootballCompetitionPreset(
        slug: "conmebol.libertadores",
        title: "CONMEBOL Libertadores",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let clubWorldCup = FootballCompetitionPreset(
        slug: "fifa.cwc",
        title: "FIFA Club World Cup",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays
    )

    static let goldCup = FootballCompetitionPreset(
        slug: "concacaf.gold",
        title: "Concacaf Gold Cup",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays,
        category: .nationalTeams
    )

    static let africaCupOfNations = FootballCompetitionPreset(
        slug: "caf.nations",
        title: "Africa Cup of Nations",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays,
        category: .nationalTeams
    )

    static let asianCup = FootballCompetitionPreset(
        slug: "afc.asian.cup",
        title: "AFC Asian Cup",
        lookbackDays: Self.suggestionWindowDays,
        lookaheadDays: Self.suggestionWindowDays,
        category: .nationalTeams
    )

    static let menuPresets: [FootballCompetitionPreset] = [
        .premierLeague,
        .laLiga,
        .brasileiraoSerieA,
        .serieA,
        .bundesliga,
        .ligue1,
        .primeiraLiga,
        .ligaProfesionalArgentina,
        .eredivisie,
        .primeraA,
        .majorLeagueSoccer,
        .worldCup,
        .fifaFriendlies,
        .championsLeague,
        .europaLeague,
        .superCup,
        .europeanChampionship,
        .copaAmerica,
        .libertadores,
        .clubWorldCup,
        .goldCup,
        .africaCupOfNations,
        .asianCup,
    ]

    static func category(forCompetitionSlug slug: String) -> FootballCompetitionCategory {
        menuPresets.first(where: { $0.slug == slug })?.category ?? .clubCompetitions
    }
}

struct FootballTeamSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let abbreviation: String
    let logoURL: URL?
    let countryName: String?
    let isNational: Bool

    func withResolvedDetails(countryName: String?, isNational: Bool, logoURL: URL?) -> FootballTeamSummary {
        FootballTeamSummary(
            id: id,
            name: name,
            abbreviation: abbreviation,
            logoURL: logoURL ?? self.logoURL,
            countryName: countryName ?? self.countryName,
            isNational: isNational || self.isNational
        )
    }
}

struct FootballFixtureMatch: Identifiable, Hashable {
    let id: String
    let competitionSlug: String
    let competitionName: String
    let competitionStage: String?
    let seasonSlug: String?
    let competitionNote: String?
    let competitionLogoURL: URL?
    let locationText: String?
    let startDate: Date
    let actualStartDate: Date?
    let statusState: FootballFixtureStatusState
    let statusText: String
    let statusDetailText: String?
    let statusPeriod: Int?
    let statusReliability: FootballFixtureStatusReliability
    let homeTeam: FootballTeamSummary
    let awayTeam: FootballTeamSummary
    let homeScore: String
    let awayScore: String
    let homeYellowCards: Int
    let awayYellowCards: Int
    let homeRedCards: Int
    let awayRedCards: Int

    init(
        id: String,
        competitionSlug: String,
        competitionName: String,
        competitionStage: String?,
        seasonSlug: String? = nil,
        competitionNote: String? = nil,
        competitionLogoURL: URL?,
        locationText: String?,
        startDate: Date,
        actualStartDate: Date? = nil,
        statusState: FootballFixtureStatusState,
        statusText: String,
        statusDetailText: String? = nil,
        statusPeriod: Int? = nil,
        statusReliability: FootballFixtureStatusReliability = .reported,
        homeTeam: FootballTeamSummary,
        awayTeam: FootballTeamSummary,
        homeScore: String,
        awayScore: String,
        homeYellowCards: Int = 0,
        awayYellowCards: Int = 0,
        homeRedCards: Int = 0,
        awayRedCards: Int = 0
    ) {
        self.id = id
        self.competitionSlug = competitionSlug
        self.competitionName = competitionName
        self.competitionStage = competitionStage
        self.seasonSlug = seasonSlug
        self.competitionNote = competitionNote
        self.competitionLogoURL = competitionLogoURL
        self.locationText = locationText
        self.startDate = startDate
        self.actualStartDate = actualStartDate
        self.statusState = statusState
        self.statusText = statusText
        self.statusDetailText = statusDetailText
        self.statusPeriod = statusPeriod
        self.statusReliability = statusReliability
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.homeYellowCards = homeYellowCards
        self.awayYellowCards = awayYellowCards
        self.homeRedCards = homeRedCards
        self.awayRedCards = awayRedCards
    }

    var hasInterruptedStatus: Bool {
        let normalizedStatus = statusText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()

        let interruptionTokens = [
            "ABN",
            "ABANDONED",
            "SUSP",
            "SUSPENDED",
            "POSTP",
            "POSTPONED",
            "DELAY",
            "DELAYED",
            "CANCELED",
            "CANCELLED",
        ]

        return interruptionTokens.contains { normalizedStatus.contains($0) }
    }

    var hasVisibleScore: Bool {
        if hasInterruptedStatus {
            return false
        }

        switch statusState {
        case .scheduled:
            return false
        case .inProgress, .finished, .unknown:
            return true
        }
    }

    var homeGoals: Int {
        Int(homeScore) ?? 0
    }

    var awayGoals: Int {
        Int(awayScore) ?? 0
    }

    var totalGoals: Int {
        max(0, homeGoals) + max(0, awayGoals)
    }

    var competitionCategory: FootballCompetitionCategory {
        FootballCompetitionPreset.category(forCompetitionSlug: competitionSlug)
    }
}

struct FootballMenuCompetitionSection: Identifiable, Equatable {
    let competition: FootballCompetitionPreset
    let matches: [FootballFixtureMatch]
    let errorMessage: String?
    let isLoading: Bool
    let hasLoaded: Bool

    var id: String { competition.id }

    static func placeholder(for competition: FootballCompetitionPreset) -> FootballMenuCompetitionSection {
        FootballMenuCompetitionSection(
            competition: competition,
            matches: [],
            errorMessage: nil,
            isLoading: false,
            hasLoaded: false
        )
    }
}

struct FootballMatchesOverviewSection: Equatable {
    let title: String
    let matches: [FootballFixtureMatch]
    let errorMessage: String?
    let isLoading: Bool
    let hasLoaded: Bool

    static func placeholder(title: String) -> FootballMatchesOverviewSection {
        FootballMatchesOverviewSection(
            title: title,
            matches: [],
            errorMessage: nil,
            isLoading: false,
            hasLoaded: false
        )
    }
}

enum FootballScoreSide: String, Equatable {
    case home
    case away
}

struct FootballMenuBarDisplay: Equatable {
    let accessibilityText: String
    let competitionName: String
    let competitionStage: String?
    let homeAbbreviation: String
    let awayAbbreviation: String
    let showsScore: Bool
    let homeScore: String
    let awayScore: String
    let competitionLocalLogoPath: String?
    let homeLocalLogoPath: String?
    let awayLocalLogoPath: String?
}

struct FootballMatchGoalScorer: Identifiable, Hashable {
    let id: String
    let name: String
    let minute: String?
}

struct FootballMatchGoalScorers: Hashable {
    let home: [FootballMatchGoalScorer]
    let away: [FootballMatchGoalScorer]
}

struct FootballMatchStatistic: Identifiable, Hashable {
    let id: String
    let label: String
    let homeValue: String
    let awayValue: String
}

struct FootballGoalHighlight: Equatable {
    let matchID: String
    let scoringSide: FootballScoreSide
    var hasBeenShownInMenuBar: Bool = false
}

struct ManagedFootballFixtureReference: Hashable {
    static let scheme = "alertcalendar-football"
    static let host = "fixture"

    let matchID: String
    let competitionSlug: String

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.queryItems = [
            URLQueryItem(name: "matchID", value: matchID),
            URLQueryItem(name: "competition", value: competitionSlug),
        ]
        return components.url
    }

    static func parse(from url: URL?) -> ManagedFootballFixtureReference? {
        guard let url,
              url.scheme == Self.scheme,
              url.host == Self.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard let matchID = values["matchID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !matchID.isEmpty,
              let competitionSlug = values["competition"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !competitionSlug.isEmpty else {
            return nil
        }

        return ManagedFootballFixtureReference(
            matchID: matchID,
            competitionSlug: competitionSlug
        )
    }
}

struct ManagedFootballEventRecord: Codable, Hashable {
    let matchID: String
    let competitionSlug: String
    let calendarIdentifier: String
    let eventIdentifier: String?
    let eventUID: String?
    let startDate: Date

    var reference: ManagedFootballFixtureReference {
        ManagedFootballFixtureReference(
            matchID: matchID,
            competitionSlug: competitionSlug
        )
    }
}

enum FootballCalendarAlertOption: String, CaseIterable, Identifiable {
    case none
    case atTimeOfEvent
    case fiveMinutesBefore
    case tenMinutesBefore
    case fifteenMinutesBefore
    case thirtyMinutesBefore
    case oneHourBefore
    case twoHoursBefore
    case oneDayBefore
    case twoDaysBefore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "None"
        case .atTimeOfEvent:
            return "At time of event"
        case .fiveMinutesBefore:
            return "5 minutes before"
        case .tenMinutesBefore:
            return "10 minutes before"
        case .fifteenMinutesBefore:
            return "15 minutes before"
        case .thirtyMinutesBefore:
            return "30 minutes before"
        case .oneHourBefore:
            return "1 hour before"
        case .twoHoursBefore:
            return "2 hours before"
        case .oneDayBefore:
            return "1 day before"
        case .twoDaysBefore:
            return "2 days before"
        }
    }

    func relativeOffset() -> TimeInterval? {
        switch self {
        case .none:
            return nil
        case .atTimeOfEvent:
            return 0
        case .fiveMinutesBefore:
            return -5 * 60
        case .tenMinutesBefore:
            return -10 * 60
        case .fifteenMinutesBefore:
            return -15 * 60
        case .thirtyMinutesBefore:
            return -30 * 60
        case .oneHourBefore:
            return -60 * 60
        case .twoHoursBefore:
            return -2 * 60 * 60
        case .oneDayBefore:
            return -24 * 60 * 60
        case .twoDaysBefore:
            return -2 * 24 * 60 * 60
        }
    }
}
