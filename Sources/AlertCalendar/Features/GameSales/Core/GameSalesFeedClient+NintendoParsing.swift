import Foundation
struct NintendoSaleArticleReference: Hashable, Sendable {
    let url: URL
    let lastModified: Date
}
extension GameSalesFeedClient {
    nonisolated static func parseNintendoSitemap(
        _ xml: String,
        now: Date
    ) -> [NintendoSaleArticleReference] {
        NintendoSaleParser.parseSitemap(xml, now: now)
    }

    nonisolated static func parseNintendoSaleArticle(
        _ html: String,
        url: URL,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> GameSaleEvent? {
        NintendoSaleParser.parseArticle(
            html,
            url: url,
            now: now,
            calendar: calendar
        )
    }
}

private enum NintendoSaleParser {
    private struct ArticleMetadata {
        let headline: String
        let publishedAt: Date
    }

    private struct DateToken {
        let month: Int
        let day: Int
        let year: Int?
    }

    private struct DateRangeTokens {
        let start: DateToken?
        let end: DateToken
        let startsAtPublication: Bool
    }

    private static let sitemapRecency: TimeInterval = 120 * 24 * 60 * 60
    private static let pacificTimeZone = TimeZone(identifier: "America/Los_Angeles")!

    private static let monthPattern =
        #"(?:jan(?:uary)?\.?|feb(?:ruary)?\.?|mar(?:ch)?\.?|apr(?:il)?\.?|may|jun(?:e)?\.?|jul(?:y)?\.?|aug(?:ust)?\.?|sep(?:t(?:ember)?)?\.?|oct(?:ober)?\.?|nov(?:ember)?\.?|dec(?:ember)?\.?)"#
    private static let writtenDatePattern =
        #"(?:"# + monthPattern + #"\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s+\d{4})?)"#
    private static let numericDatePattern = #"(?:\d{1,2}/\d{1,2}(?:/\d{2,4})?)"#
    private static let datePattern = #"(?:"# + writtenDatePattern + #"|"# + numericDatePattern + #")"#
    static func parseSitemap(
        _ xml: String,
        now: Date
    ) -> [NintendoSaleArticleReference] {
        let oldestAcceptedDate = now.addingTimeInterval(-sitemapRecency)
        var referencesByURL: [URL: NintendoSaleArticleReference] = [:]

        for block in captures(#"<url\b[^>]*>(.*?)</url>"#, in: xml) {
            guard let rawURL = firstCapture(#"<loc\b[^>]*>(.*?)</loc>"#, in: block),
                  let sourceURL = URL(string: decodeEntities(rawURL)),
                  let officialURL = canonicalArticleURL(sourceURL),
                  let rawLastModified = firstCapture(#"<lastmod\b[^>]*>(.*?)</lastmod>"#, in: block),
                  let lastModified = parseISO8601(decodeEntities(rawLastModified)),
                  lastModified >= oldestAcceptedDate,
                  lastModified <= now else {
                continue
            }

            let reference = NintendoSaleArticleReference(
                url: officialURL,
                lastModified: lastModified
            )
            if let existing = referencesByURL[officialURL],
               existing.lastModified >= lastModified {
                continue
            }
            referencesByURL[officialURL] = reference
        }
        return referencesByURL.values.sorted { lhs, rhs in
            if lhs.lastModified != rhs.lastModified {
                return lhs.lastModified > rhs.lastModified
            }
            return lhs.url.absoluteString < rhs.url.absoluteString
        }
    }

    static func parseArticle(
        _ html: String,
        url: URL,
        now: Date,
        calendar: Calendar
    ) -> GameSaleEvent? {
        guard let officialURL = canonicalArticleURL(url),
              hasPromotionsTag(in: html),
              let metadata = articleMetadata(in: html),
              metadata.publishedAt <= now else {
            return nil
        }

        let text = visibleText(from: html)
        guard isDigitalSale(text),
              let rangeTokens = explicitDateRange(in: text) else {
            return nil
        }

        var pacificCalendar = calendar
        pacificCalendar.timeZone = pacificTimeZone
        let publicationDay = pacificCalendar.startOfDay(for: metadata.publishedAt)

        let startDate: Date
        if rangeTokens.startsAtPublication {
            startDate = publicationDay
        } else {
            guard let startToken = rangeTokens.start,
                  let resolvedStart = resolveStartDate(
                    startToken,
                    publicationDay: publicationDay,
                    calendar: pacificCalendar
                  ) else {
                return nil
            }
            startDate = resolvedStart
        }

        guard let inclusiveEndDate = resolveEndDate(
            rangeTokens.end,
            startDate: startDate,
            calendar: pacificCalendar
        ),
        let endDateExclusive = pacificCalendar.date(
            byAdding: .day,
            value: 1,
            to: inclusiveEndDate
        ),
        startDate < endDateExclusive,
        endDateExclusive > now else {
            return nil
        }

        let slug = officialURL.deletingPathExtension().lastPathComponent.lowercased()
        guard !slug.isEmpty else { return nil }

        return GameSaleEvent(
            store: .nintendoSwitch,
            sourceID: "nintendo-us-\(slug)",
            title: metadata.headline,
            startDate: startDate,
            endDateExclusive: endDateExclusive,
            officialURL: officialURL
        )
    }
    private static func canonicalArticleURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              let host = url.host?.lowercased(),
              host == "www.nintendo.com" || host == "nintendo.com" else {
            return nil
        }

        let components = url.pathComponents
        guard components.count == 4,
              components[1].lowercased() == "us",
              components[2].lowercased() == "whatsnew",
              !components[3].isEmpty,
              components[3] != ".",
              components[3] != ".." else {
            return nil
        }

        var canonical = URLComponents()
        canonical.scheme = "https"
        canonical.host = "www.nintendo.com"
        canonical.path = "/us/whatsnew/\(components[3])/"
        return canonical.url
    }

    private static func hasPromotionsTag(in html: String) -> Bool {
        firstCapture(
            #"((?:ContentTag:|[\"']id[\"']\s*:\s*[\"'])articleCategoryPromotions\b)"#,
            in: html
        ) != nil
    }

    private static func articleMetadata(in html: String) -> ArticleMetadata? {
        for payload in captures(
            #"<script\b[^>]*type\s*=\s*[\"']application/ld\+json[\"'][^>]*>(.*?)</script>"#,
            in: html
        ) {
            guard let data = decodeEntities(payload).data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data),
                  let article = newsArticle(in: root),
                  let headline = article["headline"] as? String,
                  !headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let rawPublishedAt = article["datePublished"] as? String,
                  let publishedAt = parseISO8601(rawPublishedAt) else {
                continue
            }

            return ArticleMetadata(
                headline: decodeEntities(headline)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                publishedAt: publishedAt
            )
        }
        return nil
    }

    private static func newsArticle(in value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            if isNewsArticleType(dictionary["@type"]) {
                return dictionary
            }
            for nestedValue in dictionary.values {
                if let article = newsArticle(in: nestedValue) {
                    return article
                }
            }
        } else if let array = value as? [Any] {
            for nestedValue in array {
                if let article = newsArticle(in: nestedValue) {
                    return article
                }
            }
        }
        return nil
    }

    private static func isNewsArticleType(_ value: Any?) -> Bool {
        if let type = value as? String {
            return type.caseInsensitiveCompare("NewsArticle") == .orderedSame
        }
        if let types = value as? [String] {
            return types.contains {
                $0.caseInsensitiveCompare("NewsArticle") == .orderedSame
            }
        }
        return false
    }

    private static func visibleText(from html: String) -> String {
        var result = replacing(
            #"<(script|style)\b[^>]*>.*?</\1>"#,
            in: html,
            with: " "
        )
        result = replacing(#"<br\s*/?>"#, in: result, with: " ")
        result = replacing(#"</(?:p|div|h[1-6]|li|section)>"#, in: result, with: ". ")
        result = replacing(#"<[^>]+>"#, in: result, with: " ")
        return decodeEntities(result)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    private static func isDigitalSale(_ text: String) -> Bool {
        let hasSaleLanguage = contains(
            #"\b(?:sale|deals?|savings?|promotion)\b"#,
            in: text
        )
        let hasDigitalStoreLanguage = contains(
            #"\bNintendo\s+eShop\b|\bdigital\s+(?:games?|titles?|downloads?|DLC)\b"#,
            in: text
        )
        return hasSaleLanguage && hasDigitalStoreLanguage
    }

    private static func explicitDateRange(in text: String) -> DateRangeTokens? {
        let nowPattern =
            #"\b(?:from\s+)?now\s+(?:through|until|to)\s+("# + datePattern + #")"#
        if let match = firstMatch(nowPattern, in: text),
           hasSaleContext(match.range, in: text),
           let rawEnd = capture(1, from: match, in: text),
           let end = parseDateToken(rawEnd) {
            return DateRangeTokens(start: nil, end: end, startsAtPublication: true)
        }

        let absolutePatterns = [
            #"\bfrom\s+("# + datePattern + #").{0,120}?\b(?:through|until|to)\s+("# + datePattern + #")"#,
            #"\b(?:starts?|begins?|kicks?\s+off)\s+(?:on\s+)?("# + datePattern + #").{0,240}?\b(?:ends?(?:\s+on)?|lasts?\s+until|runs?\s+(?:through|until|to))\s+("# + datePattern + #")"#,
            #"\b(?:sale|promotion|deals?)\b.{0,60}?\b(?:runs?|lasts?)\s+(?:from\s+)?("# + datePattern + #").{0,120}?\b(?:through|until|to)\s+("# + datePattern + #")"#,
            #"\b(?:offer|sale|promotion)\s+(?:is\s+)?valid\s+("# + datePattern + #")\s*(?:-|–|—|through|until|to)\s*("# + datePattern + #")"#,
        ]

        for pattern in absolutePatterns {
            guard let match = firstMatch(pattern, in: text),
                  hasSaleContext(match.range, in: text),
                  let rawStart = capture(1, from: match, in: text),
                  let rawEnd = capture(2, from: match, in: text),
                  let start = parseDateToken(rawStart),
                  let end = parseDateToken(rawEnd) else {
                continue
            }
            return DateRangeTokens(
                start: start,
                end: end,
                startsAtPublication: false
            )
        }
        return nil
    }

    private static func hasSaleContext(_ range: NSRange, in text: String) -> Bool {
        guard let matchRange = Range(range, in: text) else { return false }
        let lowerBound = text.index(
            matchRange.lowerBound,
            offsetBy: -min(180, text.distance(from: text.startIndex, to: matchRange.lowerBound))
        )
        let upperBound = text.index(
            matchRange.upperBound,
            offsetBy: min(180, text.distance(from: matchRange.upperBound, to: text.endIndex))
        )
        return contains(
            #"\b(?:sale|deals?|savings?|promotion|offer)\b"#,
            in: String(text[lowerBound..<upperBound])
        )
    }

    private static func parseDateToken(_ value: String) -> DateToken? {
        if let numeric = firstMatch(
            #"^(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?$"#,
            in: value.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
        let rawMonth = capture(1, from: numeric, in: value),
        let rawDay = capture(2, from: numeric, in: value),
        let month = Int(rawMonth),
        let day = Int(rawDay) {
            let year = capture(3, from: numeric, in: value).flatMap(Int.init)
            return DateToken(
                month: month,
                day: day,
                year: year.map { $0 < 100 ? 2000 + $0 : $0 }
            )
        }

        guard let written = firstMatch(
            #"^("# + monthPattern + #")\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?$"#,
            in: value.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
        let rawMonth = capture(1, from: written, in: value),
        let month = monthNumber(rawMonth),
        let rawDay = capture(2, from: written, in: value),
        let day = Int(rawDay) else {
            return nil
        }
        return DateToken(
            month: month,
            day: day,
            year: capture(3, from: written, in: value).flatMap(Int.init)
        )
    }

    private static func resolveStartDate(
        _ token: DateToken,
        publicationDay: Date,
        calendar: Calendar
    ) -> Date? {
        let publicationYear = calendar.component(.year, from: publicationDay)
        let publicationMonth = calendar.component(.month, from: publicationDay)
        let resolvedYear = token.year ?? (publicationMonth >= 10 && token.month <= 3 ? publicationYear + 1 : publicationYear)
        return calendar.date(from: DateComponents(
            year: resolvedYear,
            month: token.month,
            day: token.day
        ))
    }

    private static func resolveEndDate(
        _ token: DateToken,
        startDate: Date,
        calendar: Calendar
    ) -> Date? {
        let startComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        guard let startYear = startComponents.year,
              let startMonth = startComponents.month,
              let startDay = startComponents.day else {
            return nil
        }

        var endYear = token.year ?? startYear
        if token.year == nil,
           (token.month < startMonth || (token.month == startMonth && token.day < startDay)) {
            endYear += 1
        }
        return calendar.date(from: DateComponents(
            year: endYear,
            month: token.month,
            day: token.day
        ))
    }

    private static func monthNumber(_ value: String) -> Int? {
        let month = value
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return switch month {
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

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func decodeEntities(_ value: String) -> String {
        var result = value
        for (entity, decoded) in [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " ",
        ] {
            result = result.replacingOccurrences(of: entity, with: decoded)
        }
        return result
    }

    private static func captures(_ pattern: String, in value: String) -> [String] {
        guard let expression = expression(pattern) else { return [] }
        return expression.matches(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ).compactMap { capture(1, from: $0, in: value) }
    }

    private static func firstCapture(_ pattern: String, in value: String) -> String? {
        guard let match = firstMatch(pattern, in: value) else { return nil }
        return capture(1, from: match, in: value)
    }

    private static func firstMatch(_ pattern: String, in value: String) -> NSTextCheckingResult? {
        expression(pattern)?.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        )
    }

    private static func capture(
        _ index: Int,
        from match: NSTextCheckingResult,
        in value: String
    ) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: value) else {
            return nil
        }
        return String(value[range])
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
