import AppKit
import CoreLocation
import EventKit
import Foundation

extension CalendarMonitor {
    nonisolated static func goalHighlight(
        from previousMatch: FootballFixtureMatch,
        to currentMatch: FootballFixtureMatch,
        now _: Date
    ) -> FootballGoalHighlight? {
        guard currentMatch.statusReliability == .reported else { return nil }
        guard currentMatch.statusState == .inProgress || currentMatch.statusState == .finished else { return nil }

        let previousHomeScore = footballGoalValue(previousMatch.homeScore)
        let previousAwayScore = footballGoalValue(previousMatch.awayScore)
        let currentHomeScore = footballGoalValue(currentMatch.homeScore)
        let currentAwayScore = footballGoalValue(currentMatch.awayScore)

        let homeDelta = currentHomeScore - previousHomeScore
        let awayDelta = currentAwayScore - previousAwayScore

        let scoringSide: FootballScoreSide
        if homeDelta > 0 && awayDelta == 0 {
            scoringSide = .home
        } else if awayDelta > 0 && homeDelta == 0 {
            scoringSide = .away
        } else {
            return nil
        }
        return FootballGoalHighlight(
            matchID: currentMatch.id,
            scoringSide: scoringSide
        )
    }

    nonisolated static func footballKickoffStatusText(
        for startDate: Date,
        now: Date = AlertCalendarClock.nowRoundedToSecond(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var resolvedCalendar = calendar
        resolvedCalendar.timeZone = timeZone

        let timeFormatter = footballLocalizedDateFormatter(
            template: "h:mm a",
            locale: locale,
            timeZone: timeZone
        )

        let todayStart = resolvedCalendar.startOfDay(for: now)
        let tomorrowStart = resolvedCalendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let dayAfterTomorrowStart = resolvedCalendar.date(byAdding: .day, value: 1, to: tomorrowStart) ?? tomorrowStart

        if startDate >= todayStart, startDate < tomorrowStart {
            return "Today \(timeFormatter.string(from: startDate))"
        }

        if startDate >= tomorrowStart, startDate < dayAfterTomorrowStart {
            return "Tomorrow \(timeFormatter.string(from: startDate))"
        }

        let dayDistance = abs(resolvedCalendar.dateComponents([.day], from: now, to: startDate).day ?? 0)
        let template = dayDistance < 7 ? "EEE h:mm a" : "MMM d h:mm a"
        return footballLocalizedDateFormatter(
            template: template,
            locale: locale,
            timeZone: timeZone
        )
        .string(from: startDate)
    }

    nonisolated static func footballStartedStatusText(
        for startDate: Date,
        now: Date = AlertCalendarClock.nowRoundedToSecond(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var resolvedCalendar = calendar
        resolvedCalendar.timeZone = timeZone

        let todayStart = resolvedCalendar.startOfDay(for: now)
        let startOfMatchDay = resolvedCalendar.startOfDay(for: startDate)

        if startOfMatchDay == todayStart {
            let formatter = footballLocalizedDateFormatter(
                template: "h:mm a",
                locale: locale,
                timeZone: timeZone
            )
            return "Started \(formatter.string(from: startDate))"
        }

        let dayDistance = abs(resolvedCalendar.dateComponents([.day], from: startDate, to: now).day ?? 0)
        let template = dayDistance < 7 ? "EEE h:mm a" : "MMM d h:mm a"
        let formatter = footballLocalizedDateFormatter(
            template: template,
            locale: locale,
            timeZone: timeZone
        )
        return "Started \(formatter.string(from: startDate))"
    }

    nonisolated static func footballScheduleText(
        for match: FootballFixtureMatch,
        now: Date = AlertCalendarClock.nowRoundedToSecond(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        if match.hasInterruptedStatus, match.statusState != .inProgress {
            return footballKickoffStatusText(
                for: match.startDate,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        }

        if match.statusState == .inProgress || match.statusState == .finished {
            return footballStartedStatusText(
                for: match.actualStartDate ?? match.startDate,
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        }

        return footballKickoffStatusText(
            for: match.startDate,
            now: now,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
    }

    nonisolated static func footballStatusBadgeText(
        for match: FootballFixtureMatch,
        now: Date = AlertCalendarClock.nowRoundedToSecond()
    ) -> String? {
        if match.statusReliability == .awaitingLiveData || match.statusReliability == .delayedLiveData {
            return "Soon"
        }

        let trimmed = match.statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = footballNormalizedStatusText(trimmed)

        if let interruptionBadge = footballInterruptedStatusBadgeText(from: normalized) {
            return interruptionBadge
        }

        if match.statusState == .finished {
            if normalized.contains("AET") {
                return "AET"
            }
            if normalized.contains("PEN") || normalized == "PK" || normalized.contains("PENALTY") {
                return "PEN"
            }
            return "FT"
        }

        if footballLooksLikeMinuteStatus(trimmed) {
            if footballStatusIndicatesPenaltyShootout(for: match, now: now) {
                return "PEN"
            }

            if let minuteText = footballStatusBadgeMinuteText(
                for: match,
                rawStatusText: trimmed,
                now: now
            ) {
                if footballStatusConfirmsExtraTime(match) {
                    return "ET \(minuteText)"
                }
                return minuteText
            }

            return trimmed
        }

        if normalized == "HT" || normalized.contains("HALF") {
            return "HT"
        }

        if normalized.contains("AET") {
            return "AET"
        }

        if normalized.contains("PEN") || normalized == "PK" || normalized.contains("PENALTY") {
            return "PEN"
        }

        if footballStatusIndicatesPenaltyShootout(for: match, now: now) {
            return "PEN"
        }

        if footballStatusConfirmsExtraTime(match) {
            if let detailStatusText = match.statusDetailText,
               let minuteText = footballStatusBadgeMinuteText(
                   for: match,
                   rawStatusText: detailStatusText,
                   now: now
               ) {
                return "ET \(minuteText)"
            }

            return "ET"
        }

        if footballStatusIndicatesExtraTime(for: match, now: now) {
            return "ET"
        }

        if let inferredMinute = footballLiveMinute(for: match, now: now),
           inferredMinute > 0,
           match.statusState == .inProgress,
           match.statusReliability == .reported {
            return "\(inferredMinute)'"
        }

        return nil
    }

    nonisolated static func footballStatusBadgeMinuteText(
        for match: FootballFixtureMatch,
        rawStatusText: String,
        now: Date
    ) -> String? {
        let trimmed = rawStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedMinute = footballParsedMinuteComponents(from: trimmed) else { return nil }

        let reportedMinute = parsedMinute.combinedMinute
        if let inferredMinute = footballInferredMinuteFromKickoff(for: match, now: now),
           shouldPreferInferredLiveMinute(
               reportedMinute: reportedMinute,
               inferredMinute: inferredMinute,
               match: match
           ) {
            return "\(inferredMinute)'"
        }

        return footballStatusBadgeMinuteText(from: parsedMinute)
    }

    nonisolated static func footballStatusBadgeMinuteText(from parsedMinute: FootballStatusMinuteComponents) -> String {
        if parsedMinute.stoppageMinute > 0 {
            return "\(parsedMinute.baseMinute)'+\(parsedMinute.stoppageMinute)'"
        }
        return "\(parsedMinute.baseMinute)'"
    }

    nonisolated static func footballStatusTintColor(for text: String) -> NSColor {
        let normalized = text.uppercased()
        if normalized == "ABN" {
            return .systemRed
        }
        if normalized == "SUSP." || normalized == "POSTP." {
            return .systemOrange
        }
        if normalized == "DELAY" {
            return .systemYellow
        }
        if normalized == "FT" {
            return .systemGray
        }
        if normalized.contains("AET") {
            return .systemPurple
        }
        if normalized.contains("PEN") || normalized == "PK" {
            return .systemRed
        }
        if normalized == "HT" {
            return .systemOrange
        }
        if normalized == "ET" || normalized.hasPrefix("ET ") {
            return .systemIndigo
        }
        if normalized == "SOON" {
            return .systemBlue
        }
        return .systemGreen
    }

}
