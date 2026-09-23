import Foundation

enum GoogleHolidayRefreshPolicy {
    static let interval: TimeInterval = 7 * 24 * 60 * 60
    static let failureRetryInterval: TimeInterval = 6 * 60 * 60

    static func isDue(
        lastRefreshDate: Date?,
        lastAttemptDate: Date? = nil,
        now: Date,
        forceRefresh: Bool = false
    ) -> Bool {
        if forceRefresh { return true }
        if let lastRefreshDate,
           now.timeIntervalSince(lastRefreshDate) < interval {
            return false
        }
        guard let lastAttemptDate else { return true }
        return now.timeIntervalSince(lastAttemptDate) >= failureRetryInterval
    }
}

struct GoogleHolidayCountry: Identifiable, Hashable, Sendable {
    let id: String
    let englishName: String
    let googleCalendarSlug: String

    var flag: String {
        id.unicodeScalars.compactMap { scalar -> UnicodeScalar? in
            guard let regionalIndicator = UnicodeScalar(127_397 + Int(scalar.value)) else { return nil }
            return regionalIndicator
        }
        .map(String.init)
        .joined()
    }

    var displayName: String {
        englishName
    }

    var googleCalendarID: String {
        "en.\(googleCalendarSlug)#holiday@group.v.calendar.google.com"
    }

    var feedURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "calendar.google.com"
        components.path = "/calendar/ical/\(googleCalendarID)/public/basic.ics"
        return components.url!
    }

    // Every country or territory whose public Google Calendar holiday endpoint
    // currently resolves successfully. Sark (CQ) is the only ISO/CLDR region
    // without a corresponding public feed and is intentionally omitted.
    static let all: [GoogleHolidayCountry] = supportedCountryIDs.map { id in
        let name = englishLocale.localizedString(forRegionCode: id) ?? id
        return country(id, name, googleCalendarSlugOverrides[id] ?? id.lowercased())
    }
    .sorted { lhs, rhs in
        lhs.englishName.localizedCaseInsensitiveCompare(rhs.englishName) == .orderedAscending
    }

    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static let validIDs = Set(byID.keys)

    static func normalizedCountryIDs(_ ids: Set<String>) -> Set<String> {
        Set(ids.map { $0.uppercased() }).intersection(validIDs)
    }

    static func countries(for ids: Set<String>) -> [GoogleHolidayCountry] {
        let normalized = normalizedCountryIDs(ids)
        return all.filter { normalized.contains($0.id) }
    }

    static func matchingSubscribedCalendarTitles(_ titles: [String]) -> Set<String> {
        let normalizedTitles = titles.map(normalizedSearchText)
        return Set(all.compactMap { country in
            let countryName = normalizedSearchText(country.englishName)
            let matches = normalizedTitles.contains { title in
                title.contains("holiday") && title.contains(countryName)
            }
            return matches ? country.id : nil
        })
    }

    private static let englishLocale = Locale(identifier: "en_US")

    private static let supportedCountryIDs: [String] = """
    AC AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CP CR CU CV CW CX CY CZ DE DG DJ DK DM DO DZ EA EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU IC ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TA TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS XK YE YT ZA ZM ZW
    """
    .split(whereSeparator: \Character.isWhitespace)
    .map(String.init)

    private static let googleCalendarSlugOverrides: [String: String] = [
        "AT": "austrian", "AU": "australian", "BG": "bulgarian", "BR": "brazilian",
        "CA": "canadian", "CN": "china", "CZ": "czech", "DE": "german",
        "DK": "danish", "ES": "spain", "FI": "finnish", "FR": "french",
        "GB": "uk", "GR": "greek", "HK": "hong_kong", "HR": "croatian",
        "HU": "hungarian", "ID": "indonesian", "IE": "irish", "IL": "jewish",
        "IN": "indian", "IT": "italian", "JP": "japanese", "KR": "south_korea",
        "LT": "lithuanian", "LV": "latvian", "MX": "mexican", "MY": "malaysia",
        "NL": "dutch", "NO": "norwegian", "NZ": "new_zealand", "PH": "philippines",
        "PL": "polish", "PT": "portuguese", "RO": "romanian", "RU": "russian",
        "SE": "swedish", "SG": "singapore", "SI": "slovenian", "SK": "slovak",
        "TR": "turkish", "TW": "taiwan", "UA": "ukrainian", "US": "usa",
        "VN": "vietnamese", "ZA": "sa",
    ]

    private static func country(_ id: String, _ name: String, _ slug: String) -> GoogleHolidayCountry {
        GoogleHolidayCountry(id: id, englishName: name, googleCalendarSlug: slug)
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}

struct GoogleHolidaySourceEvent: Equatable, Sendable {
    let sourceUID: String
    let countryID: String
    let title: String
    let startDate: Date
    let endDateExclusive: Date
}

struct GoogleHolidayEvent: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDateExclusive: Date
    let countryIDs: [String]
    let sourceUIDs: [String]

    var calendarTitle: String {
        let flags = countryIDs.compactMap { GoogleHolidayCountry.byID[$0]?.flag }.joined(separator: " ")
        return flags.isEmpty ? title : "\(flags) \(title)"
    }

}

struct ManagedGoogleHolidayEventRecord: Codable, Equatable, Sendable {
    let holiday: GoogleHolidayEvent
    let calendarIdentifier: String
    let eventIdentifier: String?
    let eventUID: String?
}

enum GoogleHolidayMerger {
    static func merge(
        _ sourceEvents: [GoogleHolidaySourceEvent],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [GoogleHolidayEvent] {
        struct Accumulator {
            var title: String
            var titleDecorationCount: Int
            var startDate: Date
            var endDateExclusive: Date
            var countryIDs: Set<String>
            var sourceUIDs: Set<String>
        }

        var mergedByKey: [String: Accumulator] = [:]

        for event in sourceEvents where event.endDateExclusive > event.startDate {
            guard let title = AlertCalendarString.trimmedNonEmpty(event.title) else { continue }
            let identity = GoogleHolidayCanonicalizer.identity(
                for: title,
                startDate: event.startDate,
                calendar: calendar
            )
            let key = semanticKey(
                normalizedName: identity.normalizedName,
                startDate: event.startDate,
                calendar: calendar
            )
            let displayTitle = identity.displayTitle ?? title
            let displayDecorationCount = identity.displayTitle == nil ? identity.decorationCount : 0
            if var existing = mergedByKey[key] {
                existing.countryIDs.insert(event.countryID)
                existing.sourceUIDs.insert(event.sourceUID)
                if event.endDateExclusive > existing.endDateExclusive {
                    existing.endDateExclusive = event.endDateExclusive
                }
                if GoogleHolidayCanonicalizer.preferredTitle(
                    current: existing.title,
                    currentDecorationCount: existing.titleDecorationCount,
                    candidate: displayTitle,
                    candidateDecorationCount: displayDecorationCount
                ) {
                    existing.title = displayTitle
                    existing.titleDecorationCount = displayDecorationCount
                }
                mergedByKey[key] = existing
            } else {
                mergedByKey[key] = Accumulator(
                    title: displayTitle,
                    titleDecorationCount: displayDecorationCount,
                    startDate: event.startDate,
                    endDateExclusive: event.endDateExclusive,
                    countryIDs: [event.countryID],
                    sourceUIDs: [event.sourceUID]
                )
            }
        }

        return mergedByKey.map { key, value in
            GoogleHolidayEvent(
                id: key,
                title: value.title,
                startDate: value.startDate,
                endDateExclusive: value.endDateExclusive,
                countryIDs: value.countryIDs.sorted(),
                sourceUIDs: value.sourceUIDs.sorted()
            )
        }
        .sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    static func semanticKey(
        title: String,
        startDate: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        let identity = GoogleHolidayCanonicalizer.identity(
            for: title,
            startDate: startDate,
            calendar: calendar
        )
        return semanticKey(
            normalizedName: identity.normalizedName,
            startDate: startDate,
            calendar: calendar
        )
    }

    private static func semanticKey(
        normalizedName: String,
        startDate: Date,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: startDate)
        let dateKey = String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return "\(normalizedName)|\(dateKey)"
    }

    static func normalizedTitle(_ title: String) -> String {
        GoogleHolidayCanonicalizer.mechanicallyNormalizedTitle(title).name
    }
}
