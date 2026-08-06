import Foundation

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

enum FootballCompetitionRegion: String, CaseIterable, Identifiable {
    case northAmerica
    case southAmerica
    case europe
    case global

    var id: String { rawValue }

    var title: String {
        switch self {
        case .northAmerica:
            return "North America"
        case .southAmerica:
            return "South America"
        case .europe:
            return "Europe"
        case .global:
            return "Global"
        }
    }
}

struct FootballCompetitionPreset: Identifiable, Hashable {
    let slug: String
    let title: String
    let lookbackDays: Int
    let lookaheadDays: Int
    let category: FootballCompetitionCategory
    let region: FootballCompetitionRegion

    var id: String { slug }

    static let suggestionWindowLookbackDays = 45
    static let suggestionWindowLookaheadDays = 90

    static var suggestionWindowDescription: String {
        "last \(suggestionWindowLookbackDays) days and next \(suggestionWindowLookaheadDays) days"
    }

    init(
        slug: String,
        title: String,
        lookbackDays: Int,
        lookaheadDays: Int,
        category: FootballCompetitionCategory = .clubCompetitions,
        region: FootballCompetitionRegion = .global
    ) {
        self.slug = slug
        self.title = title
        self.lookbackDays = lookbackDays
        self.lookaheadDays = lookaheadDays
        self.category = category
        self.region = region
    }

    static let costaRicanPrimeraDivision = club(
        "crc.1",
        "Costa Rican Primera Division",
        region: .northAmerica
    )
    static let ligaMX = club("mex.1", "Liga MX", region: .northAmerica)
    static let majorLeagueSoccer = club("usa.1", "MLS", region: .northAmerica)
    static let centralAmericanCup = club(
        "concacaf.central.american.cup",
        "Concacaf Central American Cup",
        region: .northAmerica
    )
    static let goldCup = national("concacaf.gold", "Concacaf Gold Cup", region: .northAmerica)
    static let brasileiraoSerieA = club("bra.1", "Brasileirao Serie A", region: .southAmerica)
    static let ligaProfesionalArgentina = club("arg.1", "Liga Argentina", region: .southAmerica)
    static let primeraA = club("col.1", "Primera A", region: .southAmerica)
    static let copaAmerica = national("conmebol.america", "Copa America", region: .southAmerica)
    static let libertadores = club("conmebol.libertadores", "CONMEBOL Libertadores", region: .southAmerica)
    static let premierLeague = club("eng.1", "Premier League", region: .europe)
    static let laLiga = club("esp.1", "LaLiga", region: .europe)
    static let serieA = club("ita.1", "Serie A", region: .europe)
    static let bundesliga = club("ger.1", "Bundesliga", region: .europe)
    static let ligue1 = club("fra.1", "Ligue 1", region: .europe)
    static let primeiraLiga = club("por.1", "Primeira Liga", region: .europe)
    static let eredivisie = club("ned.1", "Eredivisie", region: .europe)
    static let worldCup = national("fifa.world", "FIFA World Cup", region: .global)
    static let fifaFriendlies = national("fifa.friendly", "FIFA Friendlies", region: .global)
    static let championsLeague = club("uefa.champions", "UEFA Champions League", region: .europe)
    static let europaLeague = club("uefa.europa", "UEFA Europa League", region: .europe)
    static let superCup = club("uefa.super_cup", "UEFA Super Cup", region: .europe)
    static let europeanChampionship = national("uefa.euro", "UEFA European Championship", region: .europe)
    static let clubWorldCup = club("fifa.cwc", "FIFA Club World Cup", region: .global)
    static let africaCupOfNations = national("caf.nations", "Africa Cup of Nations", region: .global)
    static let asianCup = national("afc.asian.cup", "AFC Asian Cup", region: .global)

    static let menuPresets: [FootballCompetitionPreset] = [
        .costaRicanPrimeraDivision,
        .ligaMX,
        .majorLeagueSoccer,
        .centralAmericanCup,
        .goldCup,
        .brasileiraoSerieA,
        .ligaProfesionalArgentina,
        .primeraA,
        .copaAmerica,
        .libertadores,
        .premierLeague,
        .laLiga,
        .serieA,
        .bundesliga,
        .ligue1,
        .primeiraLiga,
        .eredivisie,
        .championsLeague,
        .europaLeague,
        .superCup,
        .europeanChampionship,
        .worldCup,
        .fifaFriendlies,
        .clubWorldCup,
        .africaCupOfNations,
        .asianCup,
    ]

    private static let presetsBySlug = Dictionary(uniqueKeysWithValues: menuPresets.map { ($0.slug, $0) })

    static func category(forCompetitionSlug slug: String) -> FootballCompetitionCategory {
        presetsBySlug[slug]?.category ?? .clubCompetitions
    }

    static func region(forCompetitionSlug slug: String) -> FootballCompetitionRegion {
        presetsBySlug[slug]?.region ?? .global
    }

    private static func club(_ slug: String, _ title: String, region: FootballCompetitionRegion) -> FootballCompetitionPreset {
        preset(slug: slug, title: title, category: .clubCompetitions, region: region)
    }

    private static func national(_ slug: String, _ title: String, region: FootballCompetitionRegion) -> FootballCompetitionPreset {
        preset(slug: slug, title: title, category: .nationalTeams, region: region)
    }

    private static func preset(
        slug: String,
        title: String,
        category: FootballCompetitionCategory,
        region: FootballCompetitionRegion
    ) -> FootballCompetitionPreset {
        FootballCompetitionPreset(
            slug: slug,
            title: title,
            lookbackDays: suggestionWindowLookbackDays,
            lookaheadDays: suggestionWindowLookaheadDays,
            category: category,
            region: region
        )
    }
}
