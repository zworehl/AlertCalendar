import Foundation

struct GoogleHolidayCanonicalIdentity: Equatable, Sendable {
    let normalizedName: String
    let displayTitle: String?
    let decorationCount: Int
}

enum GoogleHolidayCanonicalizer {
    static func identity(
        for title: String,
        startDate: Date,
        calendar: Calendar
    ) -> GoogleHolidayCanonicalIdentity {
        let mechanicallyNormalized = mechanicallyNormalizedTitle(title)
        let alias = canonicalAlias(
            for: mechanicallyNormalized.name,
            startDate: startDate,
            calendar: calendar
        )
        return GoogleHolidayCanonicalIdentity(
            normalizedName: alias?.key ?? mechanicallyNormalized.name,
            displayTitle: alias?.displayTitle,
            decorationCount: mechanicallyNormalized.decorationCount
        )
    }

    static func mechanicallyNormalizedTitle(_ title: String) -> (name: String, decorationCount: Int) {
        var tokens = foldedTokens(title)
        var decorationCount = 0

        for prefix in [
            ["substitute", "bank", "holiday", "for"],
            ["substitute", "holiday", "for"],
            ["public", "holiday", "for"],
            ["day", "off", "for"],
        ] where tokens.starts(with: prefix) {
            tokens.removeFirst(prefix.count)
            decorationCount += prefix.count
            break
        }

        if tokens.first == "the" {
            tokens.removeFirst()
            decorationCount += 1
        }

        let regionalDecorationIndices = Set(tokens.indices.filter { index in
            guard tokens[index] == "regional" else { return false }
            let previousIsHoliday = index > 0 && tokens[index - 1] == "holiday"
            let nextIsHoliday = index + 1 < tokens.count && tokens[index + 1] == "holiday"
            return previousIsHoliday || nextIsHoliday
        })
        let removableTokens: Set<String> = [
            "holiday",
            "observed",
            "substitute",
            "tentative",
        ]
        tokens = tokens.enumerated().compactMap { index, token in
            if removableTokens.contains(token)
                || regionalDecorationIndices.contains(index)
                || token == "s" {
                decorationCount += 1
                return nil
            }
            if token == "labour" {
                decorationCount += 1
                return "labor"
            }
            if token == "st" {
                decorationCount += 1
                return "saint"
            }
            return token
        }

        return (tokens.joined(separator: " "), decorationCount)
    }

    static func preferredTitle(
        current: String,
        currentDecorationCount: Int,
        candidate: String,
        candidateDecorationCount: Int
    ) -> Bool {
        if candidateDecorationCount != currentDecorationCount {
            return candidateDecorationCount < currentDecorationCount
        }
        if candidate.count != current.count {
            return candidate.count < current.count
        }
        return candidate.localizedCaseInsensitiveCompare(current) == .orderedAscending
    }

    private struct Alias {
        let key: String
        let displayTitle: String
    }

    private static func canonicalAlias(
        for name: String,
        startDate: Date,
        calendar: Calendar
    ) -> Alias? {
        let tokens = Set(name.split(separator: " ").map(String.init))
        let excludesAdjacentOccurrence = !tokens.isDisjoint(
            with: ["after", "before", "eve", "second", "third", "fourth", "2", "3", "4"]
        )

        if !excludesAdjacentOccurrence {
            if newYearsDayNames.contains(name) {
                return Alias(key: "new years day", displayTitle: "New Year's Day")
            }
            if christmasDayNames.contains(name) {
                return Alias(key: "christmas day", displayTitle: "Christmas Day")
            }
            if easterSundayNames.contains(name) {
                return Alias(key: "easter sunday", displayTitle: "Easter Sunday")
            }
            if holySaturdayNames.contains(name) {
                return Alias(key: "holy saturday", displayTitle: "Holy Saturday")
            }
            if goodFridayNames.contains(name) {
                return Alias(key: "good friday", displayTitle: "Good Friday")
            }
            if easterMondayNames.contains(name) {
                return Alias(key: "easter monday", displayTitle: "Easter Monday")
            }
            if epiphanyNames.contains(name) {
                return Alias(key: "epiphany", displayTitle: "Epiphany")
            }
            if ascensionDayNames.contains(name) {
                return Alias(key: "ascension day", displayTitle: "Ascension Day")
            }
            if pentecostNames.contains(name) {
                return Alias(key: "pentecost", displayTitle: "Pentecost")
            }
            if pentecostMondayNames.contains(name) {
                return Alias(key: "pentecost monday", displayTitle: "Pentecost Monday")
            }
        }

        if tokens.contains("assumption"),
           tokens.contains("mary") || name == "assumption day" {
            return Alias(key: "assumption of mary", displayTitle: "Assumption of Mary")
        }
        if tokens.isSuperset(of: ["immaculate", "conception"]) {
            return Alias(key: "immaculate conception", displayTitle: "Immaculate Conception")
        }
        if tokens.contains("annunciation"), !tokens.contains("eve") {
            return Alias(key: "annunciation", displayTitle: "Feast of the Annunciation")
        }
        if saintPeterAndPaulNames.contains(name) {
            return Alias(key: "saints peter and paul", displayTitle: "Saints Peter and Paul")
        }
        if mothersDayNames.contains(name) {
            return Alias(key: "mothers day", displayTitle: "Mother's Day")
        }
        if fathersDayNames.contains(name) {
            return Alias(key: "fathers day", displayTitle: "Father's Day")
        }
        if allSoulsDayNames.contains(name) {
            return Alias(key: "all souls day", displayTitle: "All Souls' Day")
        }

        let components = calendar.dateComponents([.month, .day], from: startDate)
        if components.month == 5, components.day == 1, workersDayNames.contains(name) {
            return Alias(key: "workers day", displayTitle: "International Workers' Day")
        }

        guard !excludesAdjacentOccurrence else { return nil }

        if isEidAlFitr(name, tokens: tokens) {
            return Alias(key: "eid al fitr", displayTitle: "Eid al-Fitr")
        }
        if isEidAlAdha(name, tokens: tokens) {
            return Alias(key: "eid al adha", displayTitle: "Eid al-Adha")
        }
        if isProphetsBirthday(name, tokens: tokens) {
            return Alias(key: "prophets birthday", displayTitle: "The Prophet's Birthday")
        }
        if isIsraAndMiraj(name, tokens: tokens) {
            return Alias(key: "isra and miraj", displayTitle: "Isra and Mi'raj")
        }
        if tokens.contains("arafat") || tokens.contains("arafah") {
            return Alias(key: "arafat day", displayTitle: "Arafat Day")
        }
        if !tokens.isDisjoint(with: ["ashura", "ashoura", "ashoora"]) {
            return Alias(key: "ashura", displayTitle: "Ashura")
        }
        if tokens.contains("muharram") || name == "al hijra islamic new year" {
            return Alias(key: "islamic new year", displayTitle: "Islamic New Year")
        }
        if isDiwali(name, tokens: tokens) {
            return Alias(key: "diwali", displayTitle: "Diwali")
        }
        if isHoli(name, tokens: tokens) {
            return Alias(key: "holi", displayTitle: "Holi")
        }
        if isVesak(name, tokens: tokens) {
            return Alias(key: "vesak", displayTitle: "Vesak")
        }
        if mahaShivaratriNames.contains(name) {
            return Alias(key: "maha shivaratri", displayTitle: "Maha Shivaratri")
        }
        if ugadiNames.contains(name) {
            return Alias(key: "ugadi", displayTitle: "Ugadi")
        }
        if vaisakhiNames.contains(name) {
            return Alias(key: "vaisakhi", displayTitle: "Vaisakhi")
        }
        if vasantPanchamiNames.contains(name) {
            return Alias(key: "vasant panchami", displayTitle: "Vasant Panchami")
        }
        if chungYeungNames.contains(name) {
            return Alias(key: "chung yeung festival", displayTitle: "Chung Yeung Festival")
        }
        if chuseokNames.contains(name) {
            return Alias(key: "chuseok", displayTitle: "Chuseok")
        }
        if africaDayNames.contains(name) {
            return Alias(key: "africa day", displayTitle: "Africa Day")
        }
        if emancipationDayNames.contains(name) {
            return Alias(key: "emancipation day", displayTitle: "Emancipation Day")
        }
        if juneteenthNames.contains(name) {
            return Alias(key: "juneteenth", displayTitle: "Juneteenth")
        }
        if indigenousResistanceDayNames.contains(name) {
            return Alias(key: "indigenous resistance day", displayTitle: "Indigenous Resistance Day")
        }
        if culturalDiversityDayNames.contains(name) {
            return Alias(key: "cultural diversity day", displayTitle: "Cultural Diversity Day")
        }
        if freedomAndDemocracyDayNames.contains(name) {
            return Alias(key: "freedom and democracy day", displayTitle: "Freedom and Democracy Day")
        }
        if abolitionOfSlaveryDayNames.contains(name) {
            return Alias(key: "abolition of slavery day", displayTitle: "Abolition of Slavery Day")
        }
        if cincoDeMayoNames.contains(name) {
            return Alias(key: "cinco de mayo", displayTitle: "Cinco de Mayo")
        }
        if pongalNames.contains(name) {
            return Alias(key: "pongal", displayTitle: "Pongal")
        }
        if midsummerDayNames.contains(name) {
            return Alias(key: "midsummer day", displayTitle: "Midsummer Day")
        }
        if dashainNames.contains(name) {
            return Alias(key: "dashain", displayTitle: "Dashain")
        }
        return nil
    }

    private static func foldedTokens(_ title: String) -> [String] {
        let folded = title.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let characters = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        }
        return String(characters)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private static func isEidAlFitr(_ name: String, tokens: Set<String>) -> Bool {
        let hasFitrTransliteration = !tokens.isDisjoint(with: ["fitr", "fithr", "fitri", "fetr"])
        let hasEidPrefix = !tokens.isDisjoint(with: ["aid", "eid", "idd", "idul"])
        return (hasFitrTransliteration && hasEidPrefix)
            || name.hasPrefix("ramadan bayram")
            || name.hasPrefix("ramdan bayram")
            || name.hasPrefix("oraza bayram")
            || name.hasPrefix("ramadan feast")
    }

    private static func isEidAlAdha(_ name: String, tokens: Set<String>) -> Bool {
        let hasAdhaTransliteration = !tokens.isDisjoint(with: ["adha", "haa", "kabir", "kebir", "qurban"])
        let hasEidPrefix = !tokens.isDisjoint(with: ["aid", "eid", "id", "idul"])
        return (hasAdhaTransliteration && hasEidPrefix)
            || name.hasPrefix("kurban ")
            || name.hasPrefix("kurman ")
            || name.hasPrefix("sacrifice feast")
            || name.hasPrefix("feast of the sacrifice")
    }

    private static func isProphetsBirthday(_ name: String, tokens: Set<String>) -> Bool {
        if tokens.contains("prophet"), tokens.contains("birthday") {
            return true
        }
        return name.hasPrefix("maulid")
            || name.hasPrefix("maouloud")
            || name.hasPrefix("mouloud")
            || name == "id el maulud"
    }

    private static func isIsraAndMiraj(_ name: String, tokens: Set<String>) -> Bool {
        let hasMiraj = tokens.contains("miraj") || tokens.isSuperset(of: ["mi", "raj"])
        return (tokens.contains("isra") && hasMiraj)
            || name == "miraj"
            || name == "mi raj"
    }

    private static func isDiwali(_ name: String, tokens: Set<String>) -> Bool {
        !tokens.isDisjoint(with: ["deepavali", "divali", "diwali"])
            && tokens.count <= 3
            && !name.contains("day after")
    }

    private static func isHoli(_ name: String, tokens: Set<String>) -> Bool {
        !tokens.isDisjoint(with: ["holi", "phagwa", "phagwah"])
            && !tokens.contains("dahana")
    }

    private static func isVesak(_ name: String, tokens: Set<String>) -> Bool {
        if !tokens.isDisjoint(with: ["vesak", "wesak", "waisak"]) {
            return !tokens.contains("after")
        }
        return tokens.contains("buddha")
            && !tokens.isDisjoint(with: ["jayanti", "purnima"])
    }

    private static let newYearsDayNames: Set<String> = [
        "new year",
        "new year day",
    ]
    private static let christmasDayNames: Set<String> = [
        "armenian christmas",
        "armenian christmas day",
        "catholic christmas",
        "catholic christmas day",
        "catholic protestant christmas day",
        "christmas",
        "christmas day",
        "coptic christmas",
        "coptic christmas day",
        "ethiopian christmas day",
        "first day of western christmas",
        "orthodox christmas",
        "orthodox christmas day",
        "western christmas day",
    ]
    private static let easterSundayNames: Set<String> = [
        "armenian orthodox easter sunday",
        "catholic easter sunday",
        "catholic protestant easter sunday",
        "coptic easter",
        "coptic easter sunday",
        "easter",
        "easter day",
        "easter sunday",
        "easter sunday orthodox",
        "orthodox easter",
        "orthodox easter day",
        "orthodox easter sunday",
        "western easter sunday",
    ]
    private static let holySaturdayNames: Set<String> = [
        "armenian orthodox holy saturday",
        "catholic protestant holy saturday",
        "coptic holy saturday",
        "easter saturday",
        "easter saturday orthodox",
        "holy saturday",
        "holy saturday orthodox",
        "orthodox holy saturday",
        "western easter saturday",
    ]
    private static let goodFridayNames: Set<String> = [
        "armenian orthodox good friday",
        "catholic protestant good friday",
        "coptic good friday",
        "ethiopian good friday",
        "good friday",
        "good friday orthodox",
        "orthodox good friday",
        "western good friday",
    ]
    private static let easterMondayNames: Set<String> = [
        "armenian orthodox easter monday",
        "catholic protestant easter monday",
        "easter monday",
        "easter monday orthodox",
        "orthodox easter monday",
        "western easter monday",
    ]
    private static let epiphanyNames: Set<String> = [
        "catholic protestant epiphany",
        "epiphany",
        "epiphany orthodox",
        "orthodox epiphany",
        "orthodox epiphany day",
    ]
    private static let ascensionDayNames: Set<String> = [
        "armenian orthodox ascension day",
        "ascension day",
        "ascension day of jesus christ",
        "catholic protestant ascension day",
        "orthodox ascension day",
    ]
    private static let pentecostNames: Set<String> = [
        "armenian orthodox pentecost",
        "catholic protestant pentecost",
        "orthodox pentecost",
        "pentecost",
        "whit sunday",
        "whit sunday pentecost",
    ]
    private static let pentecostMondayNames: Set<String> = [
        "armenian orthodox pentecost monday",
        "catholic protestant pentecost monday",
        "orthodox pentecost monday",
        "pentecost monday",
        "whit monday",
    ]
    private static let saintPeterAndPaulNames: Set<String> = [
        "feast of saint peter and saint paul",
        "feast of saints peter and paul",
        "feasts of saints peter and paul",
        "saint peter and saint paul",
        "saints peter and paul",
    ]
    private static let mothersDayNames: Set<String> = [
        "mother day",
        "mothers day",
    ]
    private static let fathersDayNames: Set<String> = [
        "father day",
        "fathers day",
    ]
    private static let allSoulsDayNames: Set<String> = [
        "all soul day",
        "all souls day",
    ]
    private static let workersDayNames: Set<String> = [
        "international labor day",
        "international workers day",
        "labor and solidarity day",
        "labor day",
        "labor day may day",
        "may day",
        "national workers day",
        "spring and labor day",
        "workers day",
    ]
    private static let mahaShivaratriNames: Set<String> = [
        "maha shivaratree",
        "maha shivaratri",
        "mahasivarathri day",
        "shivaratri",
    ]
    private static let ugadiNames: Set<String> = ["ougadi", "ugadi"]
    private static let vaisakhiNames: Set<String> = ["baisakhi", "vaisakhi"]
    private static let vasantPanchamiNames: Set<String> = ["basant panchami", "vasant panchami"]
    private static let chungYeungNames: Set<String> = [
        "chong yeung festival",
        "chung yeung festival",
    ]
    private static let chuseokNames: Set<String> = ["chuseok", "chuseok harvest festival"]
    private static let africaDayNames: Set<String> = ["africa day", "africa freedom day"]
    private static let emancipationDayNames: Set<String> = [
        "african emancipation day",
        "emancipation day",
    ]
    private static let juneteenthNames: Set<String> = [
        "juneteenth",
        "juneteenth independence day",
        "juneteenth national independence day",
    ]
    private static let indigenousResistanceDayNames: Set<String> = [
        "day of indigenous resistance",
        "indigenous resistance day",
    ]
    private static let culturalDiversityDayNames: Set<String> = [
        "day of cultural diversity",
        "day of respect for cultural diversity",
    ]
    private static let freedomAndDemocracyDayNames: Set<String> = [
        "fight for freedom and democracy day",
        "struggle for freedom and democracy day",
    ]
    private static let abolitionOfSlaveryDayNames: Set<String> = [
        "abolition of slavery",
        "abolition of slavery day",
    ]
    private static let cincoDeMayoNames: Set<String> = [
        "battle of puebla cinco de mayo",
        "cinco de mayo",
    ]
    private static let pongalNames: Set<String> = ["pongal", "tamil thai pongal day"]
    private static let midsummerDayNames: Set<String> = ["midsummer", "midsummer day"]
    private static let dashainNames: Set<String> = ["dashain", "dashami dashain"]
}
