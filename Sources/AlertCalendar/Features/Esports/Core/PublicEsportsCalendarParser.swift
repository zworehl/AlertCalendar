import Foundation

enum PublicEsportsCalendarParser {
    struct Result: Sendable {
        let matches: [EsportsMatch]
        let rejectedEvents: Int
    }

    /// A narrow timed-event parser for this publisher, not a general ICS importer.
    /// Floating dates, recurrences and ambiguous identities cannot update events.
    static func parse(_ data: Data, game: EsportsGame, from: Date, to: Date,
                      trackedIDs: [Int] = [], fetchedAt: Date) throws -> Result {
        guard data.count <= 5_000_000, !data.contains(0),
              PublicEsportsCalendarClient.slug(for: game) != nil else { throw EsportsFeedError.invalidPayload }
        let lines = try unfoldedText(data).components(separatedBy: "\n")
        guard lines.first == "BEGIN:VCALENDAR", lines.last(where: { !$0.isEmpty }) == "END:VCALENDAR",
              lines.filter({ $0 == "BEGIN:VCALENDAR" }).count == 1,
              lines.filter({ $0 == "END:VCALENDAR" }).count == 1 else { throw EsportsFeedError.invalidPayload }
        var event: [String: String]?
        var invalid = false
        var depth = 0
        var count = 0
        var rejected = 0
        var matches: [Int: EsportsMatch] = [:]
        var ambiguous: Set<Int> = []
        for line in lines {
            if line == "BEGIN:VEVENT" {
                guard event == nil else { throw EsportsFeedError.invalidPayload }
                count += 1
                guard count <= 10_000 else { throw EsportsFeedError.invalidPayload }
                event = [:]; invalid = false; depth = 0
            } else if line == "END:VEVENT" {
                guard let properties = event, depth == 0 else { throw EsportsFeedError.invalidPayload }
                event = nil
                // The remote filter is useful, but local classification remains authoritative.
                guard belongs(properties, to: game) else { continue }
                guard !invalid, let match = makeMatch(properties, game: game, fetchedAt: fetchedAt) else {
                    rejected += 1; continue
                }
                guard !ambiguous.contains(match.providerID) else { continue }
                if let previous = matches[match.providerID], previous != match {
                    matches[match.providerID] = nil; ambiguous.insert(match.providerID); rejected += 1
                } else { matches[match.providerID] = match }
            } else if event != nil {
                if line.hasPrefix("BEGIN:") { depth += 1; continue }
                if line.hasPrefix("END:") {
                    guard depth > 0 else { throw EsportsFeedError.invalidPayload }
                    depth -= 1; continue
                }
                guard depth == 0 else { continue }
                guard let colon = line.firstIndex(of: ":") else { invalid = true; continue }
                let rawKey = String(line[..<colon])
                guard let firstKey = rawKey.split(separator: ";", maxSplits: 1).first, !firstKey.isEmpty else {
                    invalid = true; continue
                }
                let key = String(firstKey).uppercased()
                let value = String(line[line.index(after: colon)...])
                if event?[key] != nil { invalid = true }
                // Only explicit UTC timestamps are safe for this publisher's contract.
                if ["DTSTART", "DTEND"].contains(key), rawKey != key { invalid = true }
                event?[key] = value
            }
        }
        guard event == nil else { throw EsportsFeedError.invalidPayload }
        let tracked = Set(trackedIDs)
        let values = matches.values.filter { match in
            guard let start = match.scheduledAt else { return false }
            return tracked.contains(match.providerID) || match.status == .running || (start >= from && start <= to)
        }.sorted { ($0.scheduledAt ?? .distantFuture, $0.providerID) < ($1.scheduledAt ?? .distantFuture, $1.providerID) }
        return Result(matches: values, rejectedEvents: rejected)
    }

    /// RFC 5545 folding can split a UTF-8 scalar, so unfold before decoding.
    private static func unfoldedText(_ data: Data) throws -> String {
        let bytes = Array(data)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        var physicalLength = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 13 || byte == 10 {
                if byte == 13 {
                    guard index + 1 < bytes.count, bytes[index + 1] == 10 else { throw EsportsFeedError.invalidPayload }
                    index += 1
                }
                index += 1; physicalLength = 0
                if index < bytes.count, bytes[index] == 32 || bytes[index] == 9 {
                    guard !output.isEmpty else { throw EsportsFeedError.invalidPayload }
                    index += 1
                } else { output.append(10) }
            } else {
                physicalLength += 1
                guard physicalLength <= 32_768 else { throw EsportsFeedError.invalidPayload }
                output.append(byte); index += 1
            }
        }
        guard let text = String(bytes: output, encoding: .utf8) else { throw EsportsFeedError.invalidPayload }
        return text
    }

    private static func belongs(_ properties: [String: String], to game: EsportsGame) -> Bool {
        let name = game == .starCraft2 ? "StarCraft 2" : game.displayName
        let categories = properties["CATEGORIES"]?.components(separatedBy: ",").map(unescape) ?? []
        return categories.contains(name) && properties["LOCATION"].map(unescape) == name
    }

    private static func makeMatch(_ properties: [String: String], game: EsportsGame, fetchedAt: Date) -> EsportsMatch? {
        guard properties["RRULE"] == nil, properties["RECURRENCE-ID"] == nil,
              let uid = properties["UID"],
              let range = uid.range(of: #"^pandascore-([1-9][0-9]*)@esports-calendar\.local$"#, options: .regularExpression),
              range == (uid.startIndex..<uid.endIndex),
              let number = uid.dropFirst("pandascore-".count).split(separator: "@").first,
              let id = Int(number), id > 0,
              let rawStart = properties["DTSTART"], let start = utcDate(rawStart),
              let rawTitle = properties["SUMMARY"] else { return nil }
        let title = unescape(rawTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 1_024 else { return nil }
        // DTEND in this public feed is estimated; it is deliberately not endAt.
        if let rawEnd = properties["DTEND"] {
            guard let end = utcDate(rawEnd), end > start else { return nil }
        }
        let description = unescape(properties["DESCRIPTION"] ?? "")
        let league = description.components(separatedBy: "\n").first { $0.hasPrefix("📋 League: ") }
            .map { String($0.dropFirst("📋 League: ".count)).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        var status: EsportsMatchStatus = .scheduled
        if properties["STATUS"] == "CANCELLED" { status = .canceled }
        else if title.hasPrefix("✅ "), description.contains("✅ Final Score: ") { status = .finished }
        else if title.hasPrefix("🔴 LIVE: ") { status = .running }
        let rawURL = properties["URL"].map(unescape).flatMap(URL.init(string:))
        var match = EsportsMatch(providerID: id, game: game, name: title,
            competitionName: league, status: status, scheduledAt: start,
            streamURL: EsportsStreamURLPolicy.safeURL(rawURL), fetchedAt: fetchedAt)
        match.feedSourceURL = PublicEsportsCalendarClient.sourceURL
        match.feedSourceAttribution = PublicEsportsCalendarClient.attribution
        // This is an application grouping key from the literal published league,
        // never an invented external numeric league ID.
        if !league.isEmpty {
            match.feedCompetitionKey = "esport-calendar:\(game.rawValue):\(league.precomposedStringWithCanonicalMapping)"
        }
        return match
    }

    private static func utcDate(_ value: String) -> Date? {
        guard value.count == 16, value.hasSuffix("Z"),
              value.range(of: #"^[0-9]{8}T[0-9]{6}Z$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var escaped = false
        for character in value {
            if escaped {
                switch character {
                case "n", "N": result.append("\n")
                case "\\", ",", ";": result.append(character)
                default: result.append("\\"); result.append(character)
                }
                escaped = false
            } else if character == "\\" { escaped = true }
            else { result.append(character) }
        }
        if escaped { result.append("\\") }
        return result
    }
}
