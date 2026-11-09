import Foundation

extension GameSalesFeedClient {
    nonisolated static func parseScheduledSales(
        fromHTML html: String,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [GameSaleEvent] {
        let seasonalSales = parseSeasonalSales(
            fromHTML: html,
            calendar: calendar
        )
        let themedSales = parseThemedSales(
            fromHTML: html,
            calendar: calendar
        )

        var salesByID: [GameSaleEvent.ID: GameSaleEvent] = [:]
        for sale in seasonalSales + themedSales where sale.endDateExclusive > now {
            guard sale.startDate < sale.endDateExclusive else { continue }

            if let existing = salesByID[sale.id] {
                if sale.startDate < existing.startDate
                    || (sale.startDate == existing.startDate
                        && sale.officialURL.absoluteString < existing.officialURL.absoluteString) {
                    salesByID[sale.id] = sale
                }
            } else {
                salesByID[sale.id] = sale
            }
        }

        return salesByID.values.sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate {
                return lhs.startDate < rhs.startDate
            }
            if lhs.title != rhs.title {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }
}

private extension GameSalesFeedClient {
    struct DateRangeParts {
        let startMonth: Int
        let startDay: Int
        let endMonth: Int
        let endDay: Int
        let startYear: Int
        let endYear: Int
    }

    nonisolated static func parseSeasonalSales(
        fromHTML html: String,
        calendar: Calendar
    ) -> [GameSaleEvent] {
        matches(for: #"<h2\b[^>]*>(.*?)</h2>"#, in: html).compactMap { captures in
            guard let rawHeadingHTML = captures[safe: 1] ?? nil else { return nil }
            let heading = plainText(fromHTML: rawHeadingHTML)
            guard let parts = firstMatch(
                for: #"^(.+?\bSale)\s*\|\s*([A-Za-z]+)\s+(\d{1,2})\s*-\s*(?:([A-Za-z]+)\s+)?(\d{1,2}),\s*(\d{4})\b"#,
                in: heading
            ),
            let rawTitle = parts[safe: 1] ?? nil,
            let startMonthName = parts[safe: 2] ?? nil,
            let startDayText = parts[safe: 3] ?? nil,
            let endDayText = parts[safe: 5] ?? nil,
            let endYearText = parts[safe: 6] ?? nil,
            let startMonth = monthNumber(startMonthName),
            let startDay = Int(startDayText),
            let endDay = Int(endDayText),
            let endYear = Int(endYearText)
            else {
                return nil
            }

            let endMonthName = (parts[safe: 4] ?? nil) ?? startMonthName
            guard let endMonth = monthNumber(endMonthName) else { return nil }
            let startYear = startMonth > endMonth ? endYear - 1 : endYear
            let dateParts = DateRangeParts(
                startMonth: startMonth,
                startDay: startDay,
                endMonth: endMonth,
                endDay: endDay,
                startYear: startYear,
                endYear: endYear
            )

            let anchor = firstMatch(
                for: #"\bname\s*=\s*[\"']([^\"']+)[\"']"#,
                in: rawHeadingHTML
            )?[safe: 1] ?? nil
            let officialURL = sourceURL(fragment: anchor)
            let sourceTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceID = "seasonal-\(slug(sourceTitle.replacingOccurrences(of: " Sale", with: "")))-\(startYear)"

            return sale(
                sourceID: sourceID,
                title: steamTitle(sourceTitle),
                dateParts: dateParts,
                officialURL: officialURL,
                calendar: calendar
            )
        }
    }

    nonisolated static func parseThemedSales(
        fromHTML html: String,
        calendar: Calendar
    ) -> [GameSaleEvent] {
        var result: [GameSaleEvent] = []
        let tableSections = matches(
            for: #"<h2\b[^>]*>(.*?)</h2>\s*<table\b[^>]*>(.*?)</table>"#,
            in: html
        )

        for section in tableSections {
            guard let headingHTML = section[safe: 1] ?? nil,
                  let tableHTML = section[safe: 2] ?? nil else {
                continue
            }
            let heading = plainText(fromHTML: headingHTML)
            guard let yearMatch = firstMatch(
                for: #"\b(\d{4})\s+Fests\b"#,
                in: heading
            ),
            let yearText = yearMatch[safe: 1] ?? nil,
            let year = Int(yearText) else {
                continue
            }

            for row in matches(for: #"<tr\b[^>]*>(.*?)</tr>"#, in: tableHTML) {
                guard let rowHTML = row[safe: 1] ?? nil else { continue }
                let cells = matches(for: #"<td\b[^>]*>(.*?)</td>"#, in: rowHTML)
                    .compactMap { $0[safe: 1] ?? nil }
                guard cells.count >= 2 else { continue }

                let dateText = plainText(fromHTML: cells[0])
                let dateMatches = matches(
                    for: #"\b([A-Za-z]+)\s+(\d{1,2})\b"#,
                    in: dateText
                )
                guard dateMatches.count >= 2,
                      let startMonthName = dateMatches[0][safe: 1] ?? nil,
                      let startDayText = dateMatches[0][safe: 2] ?? nil,
                      let endMonthName = dateMatches[1][safe: 1] ?? nil,
                      let endDayText = dateMatches[1][safe: 2] ?? nil,
                      let startMonth = monthNumber(startMonthName),
                      let startDay = Int(startDayText),
                      let endMonth = monthNumber(endMonthName),
                      let endDay = Int(endDayText) else {
                    continue
                }

                let rawTitle = plainText(fromHTML: cells[1])
                guard !rawTitle.isEmpty,
                      rawTitle.localizedCaseInsensitiveCompare("Next Fest") != .orderedSame else {
                    continue
                }

                let endYear = endMonth < startMonth ? year + 1 : year
                let dateParts = DateRangeParts(
                    startMonth: startMonth,
                    startDay: startDay,
                    endMonth: endMonth,
                    endDay: endDay,
                    startYear: year,
                    endYear: endYear
                )
                let officialURL = documentationURL(in: rowHTML) ?? Self.steamworksUpcomingEventsURL
                let sourceID = "themed-\(slug(rawTitle))-\(year)"

                if let event = sale(
                    sourceID: sourceID,
                    title: steamTitle(rawTitle),
                    dateParts: dateParts,
                    officialURL: officialURL,
                    calendar: calendar
                ) {
                    result.append(event)
                }
            }
        }
        return result
    }

    nonisolated static func sale(
        sourceID: String,
        title: String,
        dateParts: DateRangeParts,
        officialURL: URL,
        calendar: Calendar
    ) -> GameSaleEvent? {
        guard let startDate = calendar.date(from: DateComponents(
            year: dateParts.startYear,
            month: dateParts.startMonth,
            day: dateParts.startDay
        )),
        let inclusiveEndDate = calendar.date(from: DateComponents(
            year: dateParts.endYear,
            month: dateParts.endMonth,
            day: dateParts.endDay
        )),
        let endDateExclusive = calendar.date(
            byAdding: .day,
            value: 1,
            to: inclusiveEndDate
        ),
        startDate < endDateExclusive else {
            return nil
        }

        return GameSaleEvent(
            store: .steam,
            sourceID: sourceID,
            title: title,
            startDate: startDate,
            endDateExclusive: endDateExclusive,
            officialURL: officialURL
        )
    }

    nonisolated static func sourceURL(fragment: String?) -> URL {
        guard let fragment, !fragment.isEmpty,
              var components = URLComponents(
                  url: steamworksUpcomingEventsURL,
                  resolvingAgainstBaseURL: false
              ) else {
            return steamworksUpcomingEventsURL
        }
        components.fragment = fragment
        return components.url ?? steamworksUpcomingEventsURL
    }

    nonisolated static func documentationURL(in html: String) -> URL? {
        for anchor in matches(
            for: #"<a\b[^>]*href\s*=\s*[\"']([^\"']+)[\"'][^>]*>"#,
            in: html
        ) {
            guard let rawValue = anchor[safe: 1] ?? nil else { continue }
            let value = decodeHTMLEntities(rawValue)
            guard value.contains("/doc/marketing/upcoming_events/"),
                  let url = URL(string: value, relativeTo: steamworksUpcomingEventsURL)?.absoluteURL,
                  url.scheme?.lowercased() == "https",
                  GameStore.infer(from: url) == .steam else {
                continue
            }
            return url
        }
        return nil
    }

    nonisolated static func steamTitle(_ title: String) -> String {
        if title.range(of: "Steam ", options: [.anchored, .caseInsensitive]) != nil {
            return title
        }
        return "Steam \(title)"
    }

    nonisolated static func slug(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let pieces = folded.unicodeScalars.split { scalar in
            !CharacterSet.alphanumerics.contains(scalar)
        }
        return pieces.map(String.init).filter { !$0.isEmpty }.joined(separator: "-")
    }

    nonisolated static func monthNumber(_ value: String) -> Int? {
        switch value.lowercased() {
        case "january", "jan": 1
        case "february", "feb": 2
        case "march", "mar": 3
        case "april", "apr": 4
        case "may": 5
        case "june", "jun": 6
        case "july", "jul": 7
        case "august", "aug": 8
        case "september", "sep", "sept": 9
        case "october", "oct": 10
        case "november", "nov": 11
        case "december", "dec": 12
        default: nil
        }
    }

    nonisolated static func plainText(fromHTML html: String) -> String {
        let withoutBreaks = replacingMatches(
            for: #"<br\s*/?>"#,
            in: html,
            with: " "
        )
        let withoutTags = replacingMatches(
            for: #"<[^>]+>"#,
            in: withoutBreaks,
            with: " "
        )
        return decodeHTMLEntities(withoutTags)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    nonisolated static func decodeHTMLEntities(_ value: String) -> String {
        var result = value
        let namedEntities = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " ",
        ]
        for (entity, decoded) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: decoded)
        }

        let numericPattern = #"&#(x[0-9A-Fa-f]+|[0-9]+);"#
        guard let expression = try? NSRegularExpression(pattern: numericPattern) else {
            return result
        }
        let matches = expression.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        )
        for match in matches.reversed() {
            guard let tokenRange = Range(match.range(at: 1), in: result),
                  let wholeRange = Range(match.range, in: result) else {
                continue
            }
            let token = String(result[tokenRange])
            let number: UInt32?
            if token.lowercased().hasPrefix("x") {
                number = UInt32(token.dropFirst(), radix: 16)
            } else {
                number = UInt32(token, radix: 10)
            }
            guard let number, let scalar = UnicodeScalar(number) else { continue }
            result.replaceSubrange(wholeRange, with: String(Character(scalar)))
        }
        return result
    }

    nonisolated static func matches(
        for pattern: String,
        in value: String
    ) -> [[String?]] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        return expression.matches(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ).map { match in
            (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound,
                      let stringRange = Range(range, in: value) else {
                    return nil
                }
                return String(value[stringRange])
            }
        }
    }

    nonisolated static func firstMatch(
        for pattern: String,
        in value: String
    ) -> [String?]? {
        matches(for: pattern, in: value).first
    }

    nonisolated static func replacingMatches(
        for pattern: String,
        in value: String,
        with template: String
    ) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return value
        }
        return expression.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: template
        )
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
