import Foundation

extension CalendarMonitor {
    nonisolated static func footballLiveMinute(
        for match: FootballFixtureMatch,
        now: Date
    ) -> Int? {
        footballLiveMinuteComponents(for: match, now: now)?.combinedMinute
    }

    nonisolated static func footballLiveMinuteComponents(
        for match: FootballFixtureMatch,
        now: Date
    ) -> FootballStatusMinuteComponents? {
        if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
            return nil
        }

        let normalizedStatus = footballNormalizedStatusText(match.statusText)

        if footballInterruptedMatchState(from: normalizedStatus) != nil {
            return nil
        }

        if normalizedStatus == "HT" || normalizedStatus.contains("HALF") {
            let baseMinute = footballStatusPeriodIndicatesExtraTime(match.statusPeriod) ? 105 : 45
            return FootballStatusMinuteComponents(baseMinute: baseMinute, stoppageMinute: 0)
        }

        if FootballStatusText.indicatesPenaltyShootout(normalizedStatus)
            || footballStatusPeriodIndicatesPenaltyShootout(match.statusPeriod) {
            return FootballStatusMinuteComponents(baseMinute: 121, stoppageMinute: 0)
        }

        if let parsed = footballParsedMinuteComponents(from: match.statusText) {
            return footballResolvedLiveMinuteComponents(parsed, for: match, now: now)
        }

        if let statusDetailText = match.statusDetailText,
           let parsed = footballParsedMinuteComponents(from: statusDetailText) {
            return footballResolvedLiveMinuteComponents(parsed, for: match, now: now)
        }

        if normalizedStatus == "ET" || normalizedStatus.contains("EXTRA TIME") {
            let inferredMinute = footballInferredMinuteFromKickoff(for: match, now: now) ?? 91
            return FootballStatusMinuteComponents(baseMinute: inferredMinute, stoppageMinute: 0)
        }

        guard match.statusState == .inProgress
            || (match.statusState == .unknown && footballEffectiveStartDate(for: match) <= now) else {
            return nil
        }

        guard let inferredMinute = footballInferredMinuteFromKickoff(for: match, now: now) else {
            return nil
        }
        return FootballStatusMinuteComponents(baseMinute: inferredMinute, stoppageMinute: 0)
    }

    nonisolated static func footballResolvedLiveMinuteComponents(
        _ reportedComponents: FootballStatusMinuteComponents,
        for match: FootballFixtureMatch,
        now: Date
    ) -> FootballStatusMinuteComponents {
        if let inferredMinute = footballInferredMinuteFromKickoff(for: match, now: now),
           shouldPreferInferredLiveMinute(
               reportedMinute: reportedComponents.combinedMinute,
               inferredMinute: inferredMinute,
               match: match
           ) {
            return FootballStatusMinuteComponents(baseMinute: inferredMinute, stoppageMinute: 0)
        }

        return reportedComponents
    }

    nonisolated static func footballLiveMatchPhase(
        for match: FootballFixtureMatch,
        now: Date
    ) -> FootballLiveMatchPhase {
        footballDetailedLiveMatchPhase(for: match, now: now).liveMatchPhase
    }

    nonisolated static func footballDetailedLiveMatchPhase(
        for match: FootballFixtureMatch,
        now: Date
    ) -> FootballDetailedLiveMatchPhase {
        if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
            return .unknown
        }

        let normalizedStatus = footballNormalizedStatusText(match.statusText)

        if footballInterruptedMatchState(from: normalizedStatus) != nil {
            return .unknown
        }

        if footballStatusIndicatesPenaltyShootout(for: match, now: now) {
            return .penalties
        }

        if normalizedStatus == "HT" || normalizedStatus.contains("HALF") {
            if footballStatusPeriodIndicatesExtraTime(match.statusPeriod) {
                return .extraTimeHalfTime
            }
            return .halfTime
        }

        if let components = footballLiveMinuteComponents(for: match, now: now) {
            let phase = footballDetailedLiveMatchPhase(
                for: components,
                statusPeriod: match.statusPeriod
            )
            if phase != .unknown {
                return phase
            }
        }

        let periodPhase = footballStatusPeriodPhase(match.statusPeriod)
        if periodPhase != .unknown {
            return periodPhase
        }

        if footballStatusIndicatesExtraTime(for: match, now: now) {
            return .extraTimeFirstHalf
        }

        return .unknown
    }

    nonisolated static func footballDetailedLiveMatchPhase(
        for minuteComponents: FootballStatusMinuteComponents,
        statusPeriod: Int? = nil
    ) -> FootballDetailedLiveMatchPhase {
        let periodPhase = footballStatusPeriodPhase(statusPeriod)
        if periodPhase != .unknown {
            return periodPhase
        }

        switch minuteComponents.baseMinute {
        case ...45:
            return .firstHalf
        case 46...90:
            return .secondHalf
        case 91...105:
            return .extraTimeFirstHalf
        case 106...120:
            return .extraTimeSecondHalf
        default:
            return minuteComponents.baseMinute > 120 ? .penalties : .unknown
        }
    }

    nonisolated static func footballInterruptedMatchDuration(
        for match: FootballFixtureMatch,
        badgeText: String
    ) -> TimeInterval {
        switch badgeText {
        case "ABN", "CANC.":
            if let components = footballReportedStatusMinuteComponents(for: match) {
                return footballDuration(forReportedMinuteComponents: components)
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
        footballReportedStatusMinuteComponents(for: match)?.combinedMinute
    }

    nonisolated static func footballReportedStatusMinuteComponents(
        for match: FootballFixtureMatch
    ) -> FootballStatusMinuteComponents? {
        if let parsed = footballParsedMinuteComponents(from: match.statusText) {
            return parsed
        }

        guard let statusDetailText = match.statusDetailText else { return nil }
        return footballParsedMinuteComponents(from: statusDetailText)
    }

    nonisolated static func footballDuration(
        forReportedMinuteComponents components: FootballStatusMinuteComponents
    ) -> TimeInterval {
        let breakMinutes: Int
        if components.baseMinute <= 45 {
            breakMinutes = 0
        } else if components.baseMinute <= 90 {
            breakMinutes = 15
        } else {
            breakMinutes = 20
        }

        let elapsedMinutes = components.combinedMinute + breakMinutes
        return TimeInterval(max(15, elapsedMinutes) * 60)
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
        footballInterruptedMatchState(from: normalizedStatus)?.badgeText
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
