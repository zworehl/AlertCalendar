import Foundation

struct LocalGamingCalendarEvent: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case competitive, gamingEvent }
    let id: String
    let game: EsportsGame
    let title: String
    let startDate: Date
    let endDate: Date?
    let isAllDay: Bool
    let calendarID: String
    let calendarName: String
    let sourceURL: URL?
    let eventIdentifier: String?
    let eventUID: String?
    let kind: Kind
    let providerMatchID: String?
}

/// Classification never synthesizes participants, scores, or provider identity.
/// Releases/maintenance remain ordinary gaming events, even in esports calendars.
enum GamingCalendarClassifier {
    static func classify(title: String, notes: String?, url: URL?, calendarName: String) -> (EsportsGame, LocalGamingCalendarEvent.Kind)? {
        // Short league codes inside arbitrary links (e.g. Meet paths) are not game evidence.
        let plainTitle = title.replacingOccurrences(of: #"https?://[^\s<>]+"#, with: "", options: .regularExpression)
        let primary = normalized(plainTitle)
        let plainNotes = (notes ?? "").replacingOccurrences(of: #"https?://[^\s<>]+"#, with: "", options: .regularExpression)
        let context = normalized([plainTitle, plainNotes, calendarName].joined(separator: " "))
        let heading = normalized(plainTitle + " " + calendarName)
        let officialLoLURL = url?.host?.lowercased().split(separator: ".").suffix(2).joined(separator: ".") == "lolesports.com"
            || (notes ?? "").range(of: #"https://(?:[a-z0-9-]+\.)?lolesports\.com(?:/|\s|$)"#, options: [.regularExpression, .caseInsensitive]) != nil
        let matches = EsportsGame.allCases.filter { game in
            aliases(for: game).contains { contains($0, in: $0.count <= 4 ? heading : context) }
                || (game == .leagueOfLegends && officialLoLURL)
        }
        guard matches.count == 1, let game = matches.first else { return nil }
        let noncompetitive = ["maintenance", "mantenimiento", "server downtime", "servidores", "patch", "parche", "release", "lanzamiento", "sale", "rebajas", "season launch", "actualizacion", "update"]
        if noncompetitive.contains(where: { contains($0, in: primary) }) { return (game, .gamingEvent) }
        let tournamentTerms = ["tournament", "torneo", "championship", "campeonato", "world cup", "world series", "worlds", "playoff", "playoffs", "qualifier", "clasificatorio", "final", "finals", "semifinal", "quarterfinal", "esports", "e-sports"]
        let hasVersus = primary.range(of: #"\S+\s+(vs\.?|versus|v\.)\s+\S+"#, options: .regularExpression) != nil
        let competitive = hasVersus || (tournamentTerms + competitionCodes(for: game)).contains { contains($0, in: context) }
        return (game, competitive ? .competitive : .gamingEvent)
    }

    static func providerReference(in notes: String?) -> String? {
        guard let notes else { return nil }
        let pattern = #"(?m)^pandascore:(leagueOfLegends|counterStrike2|rocketLeague|starCraft2):[1-9][0-9]*$"#
        guard let range = notes.range(of: pattern, options: .regularExpression) else { return nil }
        return String(notes[range])
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func contains(_ phrase: String, in text: String) -> Bool {
        text.range(of: "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![a-z0-9])", options: .regularExpression) != nil
    }

    private static func aliases(for game: EsportsGame) -> [String] {
        switch game {
        case .leagueOfLegends: ["league of legends", "lolesports", "lck", "lpl", "lec", "lcs", "lta", "msi"]
        case .counterStrike2: ["counter-strike", "counter strike", "cs2", "csgo", "cs:go"]
        case .rocketLeague: ["rocket league", "rlcs"]
        case .starCraft2: ["starcraft ii", "starcraft 2", "starcraft2", "sc2"]
        case .ageOfEmpires2: ["age of empires ii", "age of empires 2", "aoe2", "aoe ii", "wololo", "hidden cup"]
        case .geoGuessr: ["geoguessr"]
        case .granTurismo7: ["gran turismo 7", "gran turismo", "gt7", "gt world series", "gtws"]
        }
    }

    private static func competitionCodes(for game: EsportsGame) -> [String] {
        switch game {
        case .leagueOfLegends: ["lck", "lpl", "lec", "lcs", "lta", "msi", "first stand"]
        case .counterStrike2: ["iem", "esl", "blast", "major", "pgl"]
        case .rocketLeague: ["rlcs"]
        case .starCraft2: ["gsl", "esl", "iem", "wcs"]
        case .ageOfEmpires2: ["wololo", "hidden cup", "king of the desert", "nac"]
        case .geoGuessr: ["world league"]
        case .granTurismo7: ["gt world series", "gtws", "nations cup", "manufacturers cup"]
        }
    }
}
