import Foundation

enum FootballTeamBroadcastCode {
    // ESPN identity and name aliases keep similarly named clubs distinct.
    // The catalog audit and provider sources live in the football test fixtures.
    private static let reviewedTeams: [String: (code: String, names: [String])] = [
        "9739": ("ALD", ["Aldosivi"]),
        "3": ("ARG", ["Argentinos ", "Argentinos Juniors"]),
        "5": ("BOC", ["Boca ", "Boca Juniors"]),
        "2975": ("INS", ["Instituto", "Instituto (Córdoba)"]),
        "10158": ("SAR", ["Sarmiento (J)", "Sarmiento (Junín)"]),
        "19": ("TAL", ["Talleres ", "Talleres (Córdoba)"]),
        "9744": ("IRV", ["Ind. Rivadavia", "Independiente Rivadavia"]),
        "11989": ("CCO", ["C. Córdoba (SE)", "Central Córdoba (Santiago del Estero)"]),
        "19685": ("ERC", ["Estudiantes RC", "Estudiantes de Río Cuarto"]),
        "4936": ("REM", ["Remo"]),
        "885": ("UCA", ["U Católica", "Universidad Catolica", "Universidad Católica"]),
        "19425": ("ALR", ["Always Ready"]),
        "2057": ("LDA", ["Alajuelense", "Liga Deportiva Alajuelense", "LD Alajuelense"]),
        "7239": ("CSC", ["Cartaginés", "CS Cartaginés", "Club Sport Cartaginés"]),
        "862": ("CSH", ["Herediano", "CS Herediano", "Club Sport Herediano"]),
        "7237": ("PFC", ["Puntarenas", "Puntarenas FC"]),
        "20705": ("SFC", ["Sporting San José", "Spr. San José", "Sporting FC"]),
        "21520": ("AFC", ["Alianza", "Alianza FC", "Alianza FC (PAN)"]),
        "20036": ("MIX", ["Deportivo Mixco", "Deportivo"]),
        "2671": ("CCP", ["Cerro Porteño"]),
        "2919": ("ONC", ["Once Caldas"]),
        "859": ("SCA", ["AD San Carlos", "San Carlos"]),
        "131790": ("ISC", ["Inter de San Carlos", "San Carlos"]),
        "7234": ("PZE", ["Pérez Zeledón"]),
        "132447": ("ESC", ["Belén", "Escorpiones Belén"]),
        "7279": ("AKL", ["Auckland", "Auckland City"]),
        "360": ("MUN", ["Man United", "Man Utd", "Manchester United"]),
        "382": ("MCI", ["Man City", "Manchester City"]),
        "85": ("CLT", ["Celta Vigo", "Celta de Vigo", "Real Club Celta"]),
        "124": ("BVB", ["Borussia Dortmund", "Dortmund"]),
        "2790": ("SAL", ["RB Salzburg", "FC Salzburg"]),
        "132": ("BAY", ["Bayern", "Bayern Munich", "Bayern München", "FC Bayern Munich", "FC Bayern München"]),
        "166": ("LIL", ["Lille"]),
        "167": ("LYO", ["Lyon"]),
        "2502": ("NIC", ["Nice"]),
        "176": ("MAR", ["Marseille"]),
        "6851": ("PFC", ["Paris FC"]),
        "104": ("ROM", ["AS Roma"]),
        "2572": ("COM", ["Como"]),
        "233": ("PUM", ["Pumas", "Pumas UNAM", "UNAM"]),
        "232": ("TIG", ["Tigres", "Tigres U.A.N.L.", "Tigres UANL"]),
        "229": ("NEC", ["Necaxa"]),
        "21581": ("CAS", ["Casa Pia"]),
        "3699": ("GIL", ["Gil Vicente"]),
        "3822": ("RIO", ["Rio Ave"]),
        "12215": ("SCL", ["Santa Clara"]),
        "2980": ("BOD", ["Bodo/Glimt"]),
        "2990": ("LPO", ["Lech Poznan"]),
        "617": ("OMO", ["Omonia", "Omonia Nicosia"]),
        "18966": ("LAF", ["LAFC"]),
        "190": ("NYR", ["Red Bull NY", "Red Bull New York"]),
        "193": ("DCU", ["D.C. United"]),
        "187": ("LAG", ["LA Galaxy"]),
        "189": ("NER", ["New England", "New England Revolution"]),
        "22529": ("SDC", ["San Diego", "San Diego FC"]),
        "191": ("SJE", ["San Jose", "San Jose Earthquakes"]),
        "10529": ("GUM", ["Guam"]),
        "7128": ("AIN", ["Al Ain"]),
        "3385": ("URD", ["Urawa Red Diamonds", "Urawa Reds"]),
        "7120": ("UHD", ["Ulsan HD", "Ulsan"]),
        "8625": ("WAC", ["Wydad AC", "Wydad"]),
        "4888": ("NCL", ["New Caledonia"]),
        "4319": ("SDN", ["Sudan"]),
        "4388": ("LBN", ["Lebanon"]),
        "4384": ("SGP", ["Singapore"]),
        "7657": ("GLP", ["Guadeloupe"]),
    ]

    // These provider names are shared with clubs that retain a different code.
    private static let namesRequiringTeamIdentity: Set<String> = ["ALIANZA", "ALIANZAFC", "DEPORTIVO"]

    private static let previousReviewedCodes: [String: String] = [
        "2057": "ALA", "7239": "CAR", "862": "HER", "7237": "PUN", "20705": "SSJ",
        "21520": "ALI", "85": "CEL", "124": "DOR", "20036": "DEP", "2671": "CPT",
        "2919": "CAL", "2790": "SLZ", "3385": "URA", "7120": "ULS", "8625": "WYD",
        "4888": "NCD", "4319": "SUD", "4388": "LIB", "4384": "SIN", "7657": "GDL",
    ]

    private static let codesByName: [String: String] = {
        var candidates: [String: Set<String>] = [:]
        for entry in reviewedTeams.values {
            for name in entry.names {
                let key = compact(name)
                guard !namesRequiringTeamIdentity.contains(key) else { continue }
                candidates[key, default: []].insert(entry.code)
            }
        }
        return candidates.compactMapValues { $0.count == 1 ? $0.first : nil }
    }()

    static func identifier(for team: FootballTeamSummary) -> String {
        if let entry = reviewedTeams[team.id],
           entry.names.contains(where: { compact($0) == compact(team.name) }) {
            return entry.code
        }
        if let code = codesByName[compact(team.name)] { return code }
        if team.isNational,
           let code = FootballNationalLogoResolver.associationCode(
               teamID: team.id, name: team.name, abbreviation: team.abbreviation,
               countryName: team.countryName
           ) {
            return code
        }
        return normalized(team.abbreviation, fallbackName: team.name)
    }

    static func calendarRecoveryIdentifiers(for team: FootballTeamSummary) -> Set<String> {
        let providerCode = compact(team.abbreviation)
        var codes: Set<String> = [identifier(for: team)]
        if !providerCode.isEmpty {
            codes.insert(providerCode)
            codes.insert(String(providerCode.prefix(3)))
        }
        if let previous = previousReviewedCodes[team.id],
           let entry = reviewedTeams[team.id],
           entry.names.contains(where: { compact($0) == compact(team.name) }) {
            codes.insert(previous)
        }
        return codes
    }

    static func normalized(_ raw: String, fallbackName: String) -> String {
        if let code = codesByName[compact(fallbackName)] { return code }
        let providerCode = compact(raw)
        if (1...3).contains(providerCode.count) { return providerCode }

        let ignoredWords: Set<String> = ["FC", "CF", "AC", "SC", "CD", "AD", "CA", "CLUB", "DE", "DEL", "DA", "DO"]
        let words = fallbackName.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased().split { !$0.isLetter && !$0.isNumber }
            .map { compact(String($0)) }
            .filter { !$0.isEmpty && !ignoredWords.contains($0) }
        if words.count >= 3 {
            return String(words.compactMap(\.first).prefix(3))
        }
        if words.count == 2 {
            return String(words[0].prefix(1)) + String(words[1].prefix(2))
        }
        if let word = words.first { return String(word.prefix(3)) }
        return providerCode.isEmpty ? "TBD" : String(providerCode.prefix(3))
    }

    private static func compact(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
