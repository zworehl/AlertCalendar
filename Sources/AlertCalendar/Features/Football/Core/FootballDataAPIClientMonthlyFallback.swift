import Foundation

extension FootballDataAPIClient {
    static let monthlyScoreboardLimit = 1_000

    static func isMonthlyScoreboardURL(_ url: URL) -> Bool {
        let dates = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "dates" })?.value
        return dates?.count == 6
    }

    static func isIncompleteScoreboardMonth(_ error: Error) -> Bool {
        if case .incompleteScoreboardMonth = error as? ClientError { return true }
        return false
    }

    static func monthlyScoreboardURL(slug: String, month: Date, calendar: Calendar = .current) -> URL? {
        guard let base = scoreboardURL(slug: slug, dateRange: nil),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMM"
        components.queryItems = [
            URLQueryItem(name: "dates", value: formatter.string(from: month)),
            URLQueryItem(name: "limit", value: String(monthlyScoreboardLimit))
        ]
        return components.url
    }

    /// ESPN accepts calendar months even where it rejects date ranges. Explicitly
    /// raise its default 100-event cap and retain daily queries for unsupported or
    /// potentially truncated months. Neighboring months cover timezone boundaries.
    func monthlyFixtureResult(
        _ competition: FootballCompetitionPreset, range: FootballScoreboardDateRange, forceRefresh: Bool,
        refreshStartedAt: Date?
    ) async throws -> FootballFixtureLoadResult {
        let calendar = Calendar.current
        let firstDay = calendar.date(byAdding: .day, value: -1, to: range.start) ?? range.start
        let lastDay = calendar.date(byAdding: .day, value: 1, to: range.end) ?? range.end
        guard var month = calendar.dateInterval(of: .month, for: firstDay)?.start else {
            return try await dailyFixtureResult(competition, range: range, forceRefresh: forceRefresh)
        }
        var result = FootballFixtureLoadResult()
        while month <= lastDay {
            try Task.checkCancellation()
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: month), nextMonth > month,
                  let url = Self.monthlyScoreboardURL(slug: competition.slug, month: month, calendar: calendar) else { break }
            let coverageStart = calendar.date(byAdding: .day, value: -1, to: month) ?? month
            let affectedRange = FootballScoreboardDateRange(
                start: max(range.start, coverageStart), end: min(range.end, nextMonth)
            )
            let cachedFailure = scoreboardPageFailures.value(forKey: url.absoluteString)
            if let cachedFailure, cachedFailure.rejectedRange,
               Date().timeIntervalSince(cachedFailure.failedAt) < 24 * 60 * 60 {
                let daily = try await dailyFixtureResult(competition, range: affectedRange, forceRefresh: forceRefresh)
                result.matches += daily.matches
                result.failures += daily.failures
                result.availablePageCount += daily.availablePageCount
                month = nextMonth
                continue
            }
            do {
                let matches = try await scoreboardMatchesPage(
                    url: url, slug: competition.slug, competitionName: competition.title,
                    competitionCategory: competition.category, forceRefresh: forceRefresh,
                    refreshStartedAt: refreshStartedAt
                )
                if scoreboardPageFailures.value(forKey: url.absoluteString)?.rejectedRange == true {
                    let daily = try await dailyFixtureResult(competition, range: affectedRange, forceRefresh: forceRefresh)
                    result.matches += daily.matches
                    result.failures += daily.failures
                    result.availablePageCount += daily.availablePageCount
                    month = nextMonth
                    continue
                }
                result.matches += matches
                result.availablePageCount += 1
                if let failure = scoreboardPageFailures.value(forKey: url.absoluteString) {
                    result.failures.append(FootballFixtureLoadFailure(
                        competitionSlug: competition.slug, range: affectedRange,
                        reason: failure.reason, attemptedAt: failure.failedAt
                    ))
                }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
                if Self.isRejectedScoreboardRange(error) || Self.isIncompleteScoreboardMonth(error) {
                    let daily = try await dailyFixtureResult(competition, range: affectedRange, forceRefresh: forceRefresh)
                    result.matches += daily.matches
                    result.failures += daily.failures
                    result.availablePageCount += daily.availablePageCount
                } else {
                    result.failures.append(FootballFixtureLoadFailure(
                        competitionSlug: competition.slug, range: affectedRange,
                        reason: Self.fixtureFailureDescription(error),
                        attemptedAt: scoreboardPageFailures.value(forKey: url.absoluteString)?.failedAt ?? Date()
                    ))
                }
            }
            month = nextMonth
        }
        return result
    }
}
