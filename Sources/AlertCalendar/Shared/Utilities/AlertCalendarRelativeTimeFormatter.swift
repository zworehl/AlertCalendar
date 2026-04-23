import Foundation

enum AlertCalendarRelativeTimeFormatter {
    static func countdownText(to targetDate: Date, from sourceDate: Date, simplified: Bool) -> String {
        let remaining = max(Int(targetDate.timeIntervalSince(sourceDate)), 0)
        if remaining < 60 {
            return "\(remaining)s"
        }

        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if simplified {
            if days > 0 { return "\(days)d" }
            if hours > 0 { return "\(hours)h" }
            return "\(minutes)m"
        }

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func elapsedText(from startDate: Date, to endDate: Date, simplified: Bool) -> String {
        let elapsed = max(Int(endDate.timeIntervalSince(startDate)), 0)
        if elapsed < 60 {
            return "\(elapsed)s"
        }

        let days = elapsed / 86_400
        let hours = (elapsed % 86_400) / 3_600
        let minutes = (elapsed % 3_600) / 60

        if simplified {
            if days > 0 { return "\(days)d" }
            if hours > 0 { return "\(hours)h" }
            return "\(minutes)m"
        }

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func elapsedAgoText(from startDate: Date, to endDate: Date, simplified: Bool) -> String {
        "\(elapsedText(from: startDate, to: endDate, simplified: simplified)) ago"
    }

    static func leadTimeDescription(for title: String, targetDate: Date, now: Date) -> String {
        let remainingSeconds = max(Int(targetDate.timeIntervalSince(now)), 0)
        if remainingSeconds < 60 {
            return "\(title) starts in \(remainingSeconds)s."
        }

        let remainingMinutes = max(1, Int(ceil(Double(remainingSeconds) / 60.0)))
        return "\(title) starts in \(remainingMinutes) minute\(remainingMinutes == 1 ? "" : "s")."
    }
}
