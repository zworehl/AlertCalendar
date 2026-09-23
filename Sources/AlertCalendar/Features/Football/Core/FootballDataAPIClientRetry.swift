import Foundation

extension FootballDataAPIClient {
    static func isRejectedScoreboardRange(_ error: Error) -> Bool {
        if case .unsuccessfulResponse(statusCode: 400) = error as? ClientError { return true }
        return false
    }

    static func rateLimitRetryDate(header: String?, now: Date) -> Date {
        if let header, let seconds = TimeInterval(header), seconds.isFinite {
            return now.addingTimeInterval(max(60, seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return max(now.addingTimeInterval(60), header.flatMap { formatter.date(from: $0) } ?? now)
    }

    static func fixtureFailureDescription(_ error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return "ESPN did not respond in time."
            case .notConnectedToInternet, .networkConnectionLost: return "The network connection is unavailable."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "Could not connect to ESPN."
            default: return "The ESPN connection failed (\(error.code.rawValue))."
            }
        }
        if let error = error as? ClientError { return error.localizedDescription }
        return "ESPN returned unreadable fixture data."
    }

    static func isRetryableFixtureError(_ error: Error) -> Bool {
        if let error = error as? URLError {
            return [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code)
        }
        if case .unsuccessfulResponse(let statusCode) = error as? ClientError {
            return (500...599).contains(statusCode)
        }
        return false
    }

    static func fetchScoreboardPageWithRetry(
        url: URL, slug: String, competitionName: String, session: URLSession,
        competitionCategory: FootballCompetitionCategory?
    ) async throws -> [FootballFixtureMatch] {
        for attempt in 0...2 {
            do {
                try Task.checkCancellation()
                return try await fetchMatchesPage(
                    url: url, slug: slug, competitionName: competitionName,
                    session: session, competitionCategory: competitionCategory
                )
            } catch {
                guard attempt < 2, isRetryableFixtureError(error) else { throw error }
                try await Task.sleep(for: .seconds(Double(attempt + 1)))
            }
        }
        throw ClientError.invalidResponse
    }
}
