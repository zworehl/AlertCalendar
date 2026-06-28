import Foundation

extension CalendarMonitor {
    nonisolated static func footballLiveMinute(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Int? {
        if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
            return nil
        }

        let normalizedStatus = footballNormalizedStatusText(match.statusText)

        if footballInterruptedStatusBadgeText(from: normalizedStatus) != nil {
            return nil
        }

        if normalizedStatus == "HT" || normalizedStatus.contains("HALF") {
            return 45
        }

        if normalizedStatus.contains("PEN") || normalizedStatus == "PK" {
            return 121
        }

        if let parsed = footballParsedMinuteComponents(from: match.statusText) {
            let reportedMinute = parsed.combinedMinute
            if let inferredMinute = footballInferredMinuteFromKickoff(for: match, now: now),
               shouldPreferInferredLiveMinute(
                   reportedMinute: reportedMinute,
                   inferredMinute: inferredMinute,
                   match: match
               ) {
                return inferredMinute
            }
            return reportedMinute
        }

        if let statusDetailText = match.statusDetailText,
           let parsed = footballParsedMinuteComponents(from: statusDetailText) {
            let reportedMinute = parsed.combinedMinute
            if let inferredMinute = footballInferredMinuteFromKickoff(for: match, now: now),
               shouldPreferInferredLiveMinute(
                   reportedMinute: reportedMinute,
                   inferredMinute: inferredMinute,
                   match: match
               ) {
                return inferredMinute
            }
            return reportedMinute
        }

        if normalizedStatus == "ET" || normalizedStatus.contains("EXTRA TIME") {
            return footballInferredMinuteFromKickoff(for: match, now: now) ?? 91
        }

        guard match.statusState == .inProgress
            || (match.statusState == .unknown && footballEffectiveStartDate(for: match) <= now) else {
            return nil
        }

        return footballInferredMinuteFromKickoff(for: match, now: now)
    }

    nonisolated static func footballLiveMatchPhase(
        for match: FootballFixtureMatch,
        now: Date
    ) -> FootballLiveMatchPhase {
        if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
            return .unknown
        }

        let normalizedStatus = footballNormalizedStatusText(match.statusText)

        if footballInterruptedStatusBadgeText(from: normalizedStatus) != nil {
            return .unknown
        }

        if footballStatusIndicatesPenaltyShootout(for: match, now: now) {
            return .penalties
        }

        if footballStatusIndicatesExtraTime(for: match, now: now) {
            return .extraTime
        }

        if normalizedStatus == "HT" || normalizedStatus.contains("HALF") {
            return .halfTime
        }

        if let parsed = footballParsedMinuteComponents(from: match.statusText)
            ?? match.statusDetailText.flatMap(footballParsedMinuteComponents(from:)) {
            let resolvedMinute = footballLiveMinute(for: match, now: now) ?? parsed.combinedMinute

            if parsed.baseMinute > 90 {
                return .extraTime
            }

            if resolvedMinute > 45 || parsed.baseMinute > 45 || match.statusPeriod == 2 {
                return .secondHalf
            }

            return .firstHalf
        }

        guard let inferredMinute = footballLiveMinute(for: match, now: now) else {
            return .unknown
        }

        if inferredMinute >= footballPenaltyShootoutInferenceMinute {
            return .penalties
        }

        if inferredMinute > 90 {
            return footballCanReachExtraTime(match) ? .extraTime : .secondHalf
        }

        if inferredMinute > 45 {
            return .secondHalf
        }

        return .firstHalf
    }

    nonisolated static func footballInterruptedMatchDuration(
        for match: FootballFixtureMatch,
        badgeText: String
    ) -> TimeInterval {
        switch badgeText {
        case "ABN", "CANC.":
            if let minute = footballReportedStatusMinute(for: match) {
                return footballDuration(forReportedMinute: minute)
            }
            return footballRegulationMatchDuration
        case "SUSP.", "POSTP.", "DELAY":
            return footballRegulationMatchDuration
        default:
            return footballRegulationMatchDuration
        }
    }

    nonisolated static func footballInferredMinuteFromKickoff(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Int? {
        let elapsedSeconds = max(0, now.timeIntervalSince(footballEffectiveStartDate(for: match)))
        let rawMinutes = Int(elapsedSeconds / 60)
        if footballStatusPeriodIndicatesPenaltyShootout(match.statusPeriod) {
            let inferredPenaltyMinute = rawMinutes <= 60 ? 121 : max(121, rawMinutes - 15)
            return min(inferredPenaltyMinute, 130)
        }
        if footballStatusConfirmsExtraTime(match) {
            let inferredExtraTimeMinute = rawMinutes <= 60 ? 91 : max(91, rawMinutes - 15)
            return min(inferredExtraTimeMinute, 120)
        }
        if rawMinutes <= 45 {
            return rawMinutes
        }
        if rawMinutes <= 60 {
            return 45
        }

        let inferredMinute = max(46, rawMinutes - 15)
        if footballCanReachExtraTime(match), footballScoresAreLevel(match) {
            return min(inferredMinute, footballPenaltyShootoutInferenceMinute)
        }
        return min(inferredMinute, 90)
    }

    nonisolated static func shouldPreferInferredLiveMinute(
        reportedMinute: Int,
        inferredMinute: Int,
        match: FootballFixtureMatch
    ) -> Bool {
        guard match.statusState == .inProgress,
              match.statusReliability == .reported else {
            return false
        }

        guard inferredMinute >= 60 else { return false }
        return inferredMinute - reportedMinute >= 35
    }

    nonisolated static func footballReportedStatusMinute(for match: FootballFixtureMatch) -> Int? {
        if let parsed = footballParsedMinute(from: match.statusText) {
            return parsed
        }

        guard let statusDetailText = match.statusDetailText else { return nil }
        return footballParsedMinute(from: statusDetailText)
    }

    nonisolated static func footballDuration(forReportedMinute minute: Int) -> TimeInterval {
        let elapsedMinutes: Int
        if minute <= 45 {
            elapsedMinutes = minute
        } else if minute <= 90 {
            elapsedMinutes = minute + 15
        } else {
            elapsedMinutes = minute + 20
        }

        return TimeInterval(max(15, elapsedMinutes) * 60)
    }

    nonisolated static func footballParsedMinute(from rawStatusText: String) -> Int? {
        footballParsedMinuteComponents(from: rawStatusText)?.combinedMinute
    }

    nonisolated static func footballParsedMinuteComponents(from rawStatusText: String) -> FootballStatusMinuteComponents? {
        let trimmed = rawStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let characters = Array(trimmed)
        for index in characters.indices where characters[index].wholeNumberValue != nil {
            if let parsed = footballParsedMinuteComponents(in: characters, startingAt: index) {
                return parsed
            }
        }

        return nil
    }

    nonisolated private static func footballParsedMinuteComponents(
        in characters: [Character],
        startingAt startIndex: Int
    ) -> FootballStatusMinuteComponents? {
        var index = startIndex
        var baseMinuteText = ""

        while index < characters.endIndex,
              let digit = characters[index].wholeNumberValue,
              baseMinuteText.count < 3 {
            baseMinuteText.append(String(digit))
            index += 1
        }

        guard !baseMinuteText.isEmpty else { return nil }
        guard index == characters.endIndex || characters[index].wholeNumberValue == nil else { return nil }
        skipFootballMinuteWhitespace(in: characters, index: &index)

        if index < characters.endIndex, isFootballMinuteMark(characters[index]) {
            let markIndex = index
            index += 1
            skipFootballMinuteWhitespace(in: characters, index: &index)
            if index == characters.endIndex || characters[index] != "+" {
                guard let baseMinute = Int(baseMinuteText), baseMinute > 0 else { return nil }
                return FootballStatusMinuteComponents(
                    baseMinute: baseMinute,
                    stoppageMinute: 0
                )
            }

            index = markIndex + 1
            skipFootballMinuteWhitespace(in: characters, index: &index)
        }

        var extraMinuteText = ""
        if index < characters.endIndex, characters[index] == "+" {
            index += 1
            skipFootballMinuteWhitespace(in: characters, index: &index)

            while index < characters.endIndex,
                  let digit = characters[index].wholeNumberValue,
                  extraMinuteText.count < 2 {
                extraMinuteText.append(String(digit))
                index += 1
            }

            guard !extraMinuteText.isEmpty else { return nil }
            guard index == characters.endIndex || characters[index].wholeNumberValue == nil else { return nil }
            skipFootballMinuteWhitespace(in: characters, index: &index)
        }

        guard index < characters.endIndex, isFootballMinuteMark(characters[index]) else { return nil }

        let baseMinute = Int(baseMinuteText) ?? 0
        let extraMinute = Int(extraMinuteText) ?? 0
        guard baseMinute + extraMinute > 0 else { return nil }

        return FootballStatusMinuteComponents(
            baseMinute: baseMinute,
            stoppageMinute: extraMinute
        )
    }

    nonisolated private static func skipFootballMinuteWhitespace(
        in characters: [Character],
        index: inout Int
    ) {
        while index < characters.endIndex, characters[index].isWhitespace {
            index += 1
        }
    }

    nonisolated private static func isFootballMinuteMark(_ character: Character) -> Bool {
        character == "'" || character == "’"
    }

    nonisolated static func footballInterruptedStatusBadgeText(from normalizedStatus: String) -> String? {
        FootballStatusText.interruptedBadge(for: normalizedStatus)
    }

    nonisolated static func footballRegexInt(_ result: NSTextCheckingResult, in text: String, at index: Int) -> Int? {
        guard index < result.numberOfRanges else { return nil }
        let range = result.range(at: index)
        guard range.location != NSNotFound,
              let swiftRange = Range(range, in: text) else {
            return nil
        }
        return Int(text[swiftRange])
    }

    nonisolated static func footballLooksLikeMinuteStatus(_ rawStatusText: String) -> Bool {
        footballParsedMinute(from: rawStatusText) != nil
    }

    nonisolated static func footballNormalizedStatusText(_ rawStatusText: String) -> String {
        FootballStatusText.normalized(rawStatusText)
    }

    nonisolated static func footballLocalizedDateFormatter(
        template: String,
        locale: Locale,
        timeZone: TimeZone
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
