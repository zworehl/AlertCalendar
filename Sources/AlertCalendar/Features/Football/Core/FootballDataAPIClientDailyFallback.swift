import Foundation

struct FootballScoreboardCalendar: Sendable {
    let start: String
    let end: String
    let days: Set<String>

    init?(root: [String: Any]) {
        guard let league = (root["leagues"] as? [[String: Any]])?.first,
              league["calendarIsWhitelist"] as? Bool == true,
              league["calendarType"] as? String == "day",
              let start = league["calendarStartDate"] as? String,
              let end = league["calendarEndDate"] as? String,
              let days = league["calendar"] as? [String],
              start.count >= 10, end.count >= 10, days.allSatisfy({ $0.count >= 10 }) else { return nil }
        self.start = String(start.prefix(10))
        self.end = String(end.prefix(10))
        self.days = Set(days.map { String($0.prefix(10)) })
    }

    func includesOrDoesNotCover(_ day: Date, calendar: Calendar) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: day)
        return key < start || key >= end || days.contains(key)
    }
}

extension FootballDataAPIClient {
    /// Some ESPN soccer feeds reject all multi-day requests with HTTP 400.
    /// Use their published match days where available, retaining ordinary day
    /// queries outside the published season so season boundaries stay covered.
    func dailyFixtureResult(
        _ competition: FootballCompetitionPreset, range: FootballScoreboardDateRange, forceRefresh: Bool
    ) async throws -> FootballFixtureLoadResult {
        let published = await publishedScoreboardCalendar(for: competition)
        try Task.checkCancellation()
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: range.start)
        var result = FootballFixtureLoadResult()
        while day <= range.end {
            try Task.checkCancellation()
            if published?.includesOrDoesNotCover(day, calendar: calendar) ?? true {
                let page = try await fixturePageResult(
                    competition, range: FootballScoreboardDateRange(start: day, end: day), forceRefresh: forceRefresh
                )
                result.matches += page.matches
                result.failures += page.failures
                result.availablePageCount += page.availablePageCount
            } else {
                // The authoritative calendar confirms there are no fixtures on this day.
                result.availablePageCount += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return result
    }

    private func publishedScoreboardCalendar(for competition: FootballCompetitionPreset) async -> FootballScoreboardCalendar? {
        let now = Date()
        if let cached = scoreboardCalendars[competition.slug], now.timeIntervalSince(cached.fetchedAt) < 5 * 60 {
            return cached.calendar
        }
        if let task = scoreboardCalendarTasks[competition.slug] { return await task.value }
        let task = Task { [session] () -> FootballScoreboardCalendar? in
            guard let url = Self.scoreboardURL(slug: competition.slug, dateRange: nil),
                  let root = try? await Self.fetchScoreboardRoot(url: url, slug: competition.slug, session: session) else { return nil }
            return FootballScoreboardCalendar(root: root)
        }
        scoreboardCalendarTasks[competition.slug] = task
        let calendar = await task.value
        scoreboardCalendarTasks[competition.slug] = nil
        scoreboardCalendars[competition.slug] = (calendar, now)
        return calendar
    }
}
