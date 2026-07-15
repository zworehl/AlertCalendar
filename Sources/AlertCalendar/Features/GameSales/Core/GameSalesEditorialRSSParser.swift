import Foundation

enum GameSalesEditorialRSSParser {
    fileprivate struct RSSItem {
        let title: String
        let link: String
        let guid: String
        let publishedAt: Date
        let content: String
    }

    private struct DateToken {
        let month: Int?
        let day: Int
        let year: Int?
    }

    private struct DateRangeMatch {
        let start: DateToken?
        let end: DateToken
        let startsAtPublication: Bool
        let endIsExclusive: Bool
    }

    private static let monthPattern =
        #"(?:jan(?:uary)?\.?|feb(?:ruary)?\.?|mar(?:ch)?\.?|apr(?:il)?\.?|may|jun(?:e)?\.?|jul(?:y)?\.?|aug(?:ust)?\.?|sep(?:t(?:ember)?)?\.?|oct(?:ober)?\.?|nov(?:ember)?\.?|dec(?:ember)?\.?)"#
    private static let fullDatePattern =
        #"(?:"# + monthPattern + #"\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s+\d{4})?)"#
    private static let endDatePattern =
        #"(?:(?:"# + monthPattern + #")\s+)?\d{1,2}(?:st|nd|rd|th)?(?:,?\s+\d{4})?"#
    private static let optionalEndTimePattern =
        #"(?:\s*(?:at|,)\s*(?<endTime>00:00|23:59|11:59\s*p\.?m\.?|12:00\s*a\.?m\.?)(?:\s+[A-Z]{2,5})?)?"#

    nonisolated static func parseEditorialRSS(
        xml: String,
        store: GameStore,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [GameSaleEvent] {
        guard store == .xbox || store == .playStation,
              let data = xml.data(using: .utf8) else {
            return []
        }

        let delegate = RSSDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return [] }

        var seenIDs: Set<String> = []
        var sales: [GameSaleEvent] = []
        for item in delegate.items {
            guard let officialURL = canonicalURL(item.link, store: store),
                  isEligibleTitle(item.title, store: store),
                  let range = explicitDateRange(
                    in: visibleText(item.content),
                    title: item.title
                  ),
                  let dates = resolvedDates(
                    for: range,
                    publicationDate: item.publishedAt,
                    calendar: calendar
                  ),
                  dates.start < dates.endExclusive,
                  dates.endExclusive > now else {
                continue
            }

            let identity = item.guid.isEmpty ? officialURL.absoluteString : item.guid
            let sourceID = "editorial-\(slug(identity))"
            guard !sourceID.hasSuffix("editorial-"),
                  seenIDs.insert(sourceID).inserted else {
                continue
            }

            sales.append(GameSaleEvent(
                store: store,
                sourceID: sourceID,
                title: cleanTitle(item.title),
                startDate: dates.start,
                endDateExclusive: dates.endExclusive,
                officialURL: officialURL
            ))
        }

        return sales.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private static func explicitDateRange(
        in content: String,
        title: String
    ) -> DateRangeMatch? {
        let searchable = "\(title). \(content)"
        let absolutePatterns = [
            #"\b(?:runs?\s+)?from\s+(?<start>"# + fullDatePattern
                + #").{0,160}?\b(?:through|until|to)\s+(?<end>"#
                + endDatePattern + #")"# + optionalEndTimePattern,
            #"\b(?:sale|promotion|deals?)\b.{0,100}?\b(?:runs?|lasts?)\s+(?:from\s+)?(?<start>"#
                + fullDatePattern + #").{0,160}?\b(?:through|until|to)\s+(?<end>"#
                + endDatePattern + #")"# + optionalEndTimePattern,
            #"\b(?:starts?|begins?|kicks?\s+off)\s*(?:on|:)??\s*(?<start>"#
                + fullDatePattern + #").{0,260}?\b(?:ends?(?:\s+on)?|concludes?(?:\s+on)?|lasts?\s+until|runs?\s+(?:through|until|to))\s*:??\s*(?<end>"#
                + endDatePattern + #")"# + optionalEndTimePattern,
            #"\b(?:sale|promotion|deals?)\s+(?:begins?|starts?)\s*:??\s*(?<start>"#
                + fullDatePattern + #").{0,320}?\b(?:sale|promotion|deals?)?\s*(?:ends?|concludes?)\s*:??\s*(?<end>"#
                + endDatePattern + #")"# + optionalEndTimePattern,
        ]

        for pattern in absolutePatterns {
            guard let match = firstMatch(pattern, in: searchable),
                  hasSaleContext(match.range, in: searchable),
                  let rawStart = capture("start", from: match, in: searchable),
                  let rawEnd = capture("end", from: match, in: searchable),
                  let start = parseDateToken(rawStart, monthRequired: true),
                  let end = parseDateToken(rawEnd, monthRequired: false) else {
                continue
            }
            return DateRangeMatch(
                start: start,
                end: end,
                startsAtPublication: false,
                endIsExclusive: isMidnight(capture("endTime", from: match, in: searchable))
            )
        }

        let publicationStartPatterns = [
            #"\b(?:starting|starts?|begins?|kicks?\s+off|valid)\s+(?:now|today)\b.{0,180}?\b(?:through|until|to|ends?\s+(?:on\s+)?)\s*(?<end>"#
                + fullDatePattern + #")"# + optionalEndTimePattern,
            #"\b(?:from\s+)?now\s+(?:through|until|to)\s+(?<end>"#
                + fullDatePattern + #")"# + optionalEndTimePattern,
        ]
        for pattern in publicationStartPatterns {
            guard let match = firstMatch(pattern, in: searchable),
                  hasSaleContext(match.range, in: searchable),
                  let rawEnd = capture("end", from: match, in: searchable),
                  let end = parseDateToken(rawEnd, monthRequired: true) else {
                continue
            }
            return DateRangeMatch(
                start: nil,
                end: end,
                startsAtPublication: true,
                endIsExclusive: isMidnight(capture("endTime", from: match, in: searchable))
            )
        }
        return nil
    }

    private static func resolvedDates(
        for range: DateRangeMatch,
        publicationDate: Date,
        calendar: Calendar
    ) -> (start: Date, endExclusive: Date)? {
        let publicationDay = calendar.startOfDay(for: publicationDate)
        let publicationComponents = calendar.dateComponents(
            [.year, .month],
            from: publicationDay
        )
        guard let publicationYear = publicationComponents.year,
              let publicationMonth = publicationComponents.month else {
            return nil
        }

        let startDate: Date
        if range.startsAtPublication {
            startDate = publicationDay
        } else {
            guard let start = range.start,
                  let startMonth = start.month else { return nil }
            var startYear = start.year ?? publicationYear
            if start.year == nil,
               publicationMonth >= 10,
               startMonth <= 3 {
                startYear += 1
            }
            guard let date = calendar.date(from: DateComponents(
                year: startYear,
                month: startMonth,
                day: start.day
            )) else { return nil }
            startDate = date
        }

        let startComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        guard let startYear = startComponents.year,
              let startMonth = startComponents.month,
              let startDay = startComponents.day else { return nil }
        let endMonth = range.end.month ?? startMonth
        var endYear = range.end.year ?? startYear
        if range.end.year == nil,
           (endMonth < startMonth || (endMonth == startMonth && range.end.day < startDay)) {
            endYear += 1
        }
        guard let endDay = calendar.date(from: DateComponents(
            year: endYear,
            month: endMonth,
            day: range.end.day
        )) else { return nil }

        if range.endIsExclusive {
            return (startDate, endDay)
        }
        guard let exclusive = calendar.date(byAdding: .day, value: 1, to: endDay) else {
            return nil
        }
        return (startDate, exclusive)
    }

    private static func parseDateToken(
        _ value: String,
        monthRequired: Bool
    ) -> DateToken? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withMonthPattern = #"^(?<month>"# + monthPattern
            + #")\s+(?<day>\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(?<year>\d{4}))?$"#
        if let match = firstMatch(withMonthPattern, in: trimmed),
           let rawMonth = capture("month", from: match, in: trimmed),
           let month = monthNumber(rawMonth),
           let rawDay = capture("day", from: match, in: trimmed),
           let day = Int(rawDay) {
            return DateToken(
                month: month,
                day: day,
                year: capture("year", from: match, in: trimmed).flatMap(Int.init)
            )
        }
        guard !monthRequired,
              let match = firstMatch(
                #"^(?<day>\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(?<year>\d{4}))?$"#,
                in: trimmed
              ),
              let rawDay = capture("day", from: match, in: trimmed),
              let day = Int(rawDay) else {
            return nil
        }
        return DateToken(
            month: nil,
            day: day,
            year: capture("year", from: match, in: trimmed).flatMap(Int.init)
        )
    }

    private static func canonicalURL(_ rawValue: String, store: GameStore) -> URL? {
        guard let url = URL(string: decodeEntities(rawValue)),
              url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              GameStore.infer(from: url) == store,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func isEligibleTitle(_ title: String, store: GameStore) -> Bool {
        guard contains(#"\b(?:sale|promotion|deals?|savings?|discount)\b"#, in: title) else {
            return false
        }
        return store != .playStation
            || !contains(#"\b(?:Southeast\s+Asia|Hong\s+Kong|Taiwan)\b"#, in: title)
    }

    private static func hasSaleContext(_ range: NSRange, in value: String) -> Bool {
        guard let matchRange = Range(range, in: value) else { return false }
        let before = min(240, value.distance(from: value.startIndex, to: matchRange.lowerBound))
        let after = min(240, value.distance(from: matchRange.upperBound, to: value.endIndex))
        let lower = value.index(matchRange.lowerBound, offsetBy: -before)
        let upper = value.index(matchRange.upperBound, offsetBy: after)
        return contains(
            #"\b(?:sale|promotion|deals?|savings?|discount|offer)\b"#,
            in: String(value[lower..<upper])
        )
    }

    private static func visibleText(_ html: String) -> String {
        var text = replacing(#"<(script|style)\b[^>]*>.*?</\1>"#, in: html, with: " ")
        text = replacing(#"<br\s*/?>|</(?:p|div|li|h[1-6]|section)>"#, in: text, with: ". ")
        text = replacing(#"<[^>]+>"#, in: text, with: " ")
        return decodeEntities(text)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    private static func cleanTitle(_ value: String) -> String {
        decodeEntities(value).split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    }

    private static func slug(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return folded.unicodeScalars
            .split { !CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private static func monthNumber(_ value: String) -> Int? {
        switch value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
        case "jan", "january": 1
        case "feb", "february": 2
        case "mar", "march": 3
        case "apr", "april": 4
        case "may": 5
        case "jun", "june": 6
        case "jul", "july": 7
        case "aug", "august": 8
        case "sep", "sept", "september": 9
        case "oct", "october": 10
        case "nov", "november": 11
        case "dec", "december": 12
        default: nil
        }
    }

    private static func isMidnight(_ value: String?) -> Bool {
        guard let value else { return false }
        let compact = value.lowercased().filter { !$0.isWhitespace && $0 != "." }
        return compact == "00:00" || compact == "12:00am"
    }

    private static func decodeEntities(_ value: String) -> String {
        var result = value
        for (entity, decoded) in [
            "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#8211;": "–",
            "&#8212;": "—", "&#8217;": "'",
        ] {
            result = result.replacingOccurrences(of: entity, with: decoded)
        }
        return result
    }

    private static func firstMatch(
        _ pattern: String,
        in value: String
    ) -> NSTextCheckingResult? {
        expression(pattern)?.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        )
    }

    private static func capture(
        _ name: String,
        from match: NSTextCheckingResult,
        in value: String
    ) -> String? {
        let range = match.range(withName: name)
        guard range.location != NSNotFound,
              let stringRange = Range(range, in: value) else { return nil }
        return String(value[stringRange])
    }

    private static func contains(_ pattern: String, in value: String) -> Bool {
        firstMatch(pattern, in: value) != nil
    }

    private static func replacing(
        _ pattern: String,
        in value: String,
        with replacement: String
    ) -> String {
        guard let expression = expression(pattern) else { return value }
        return expression.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: replacement
        )
    }

    private static func expression(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }
}

private final class RSSDelegate: NSObject, XMLParserDelegate {
    private var isInsideItem = false
    private var currentElement = ""
    private var values: [String: String] = [:]
    private(set) var items: [GameSalesEditorialRSSParser.RSSItem] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName.lowercased() == "item" {
            isInsideItem = true
            values = [:]
        }
        currentElement = elementName.lowercased()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }
        values[currentElement, default: ""] += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard isInsideItem, let string = String(data: CDATABlock, encoding: .utf8) else {
            return
        }
        values[currentElement, default: ""] += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer { currentElement = "" }
        guard elementName.lowercased() == "item" else { return }
        isInsideItem = false

        let title = normalized(values["title"])
        let link = normalized(values["link"])
        let guid = normalized(values["guid"])
        let content = values["content:encoded"] ?? values["description"] ?? ""
        guard !title.isEmpty,
              !link.isEmpty,
              let publishedAt = Self.parseRFC822(normalized(values["pubdate"])) else {
            return
        }
        items.append(GameSalesEditorialRSSParser.RSSItem(
            title: title,
            link: link,
            guid: guid,
            publishedAt: publishedAt,
            content: content
        ))
    }

    private func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func parseRFC822(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
