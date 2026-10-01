import Foundation

enum AlertCalendarRelativeTimeFormatter {
    static func countdownText(to targetDate: Date, from sourceDate: Date, simplified: Bool) -> String {
        let remaining = max(Int(targetDate.timeIntervalSince(sourceDate)), 0)
        if simplified { return singleUnitDurationText(seconds: remaining) }
        if remaining < 60 { return L10n.text("\(remaining)s") }

        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 {
            return L10n.text("\(days)d \(hours)h \(minutes)m")
        }
        if hours > 0 {
            return L10n.text("\(hours)h \(minutes)m")
        }
        return L10n.text("\(minutes)m")
    }

    static func elapsedText(from startDate: Date, to endDate: Date, simplified: Bool) -> String {
        let elapsed = max(Int(endDate.timeIntervalSince(startDate)), 0)
        if simplified { return singleUnitDurationText(seconds: elapsed) }
        if elapsed < 60 { return L10n.text("\(elapsed)s") }

        let days = elapsed / 86_400
        let hours = (elapsed % 86_400) / 3_600
        let minutes = (elapsed % 3_600) / 60

        if days > 0 {
            return L10n.text("\(days)d \(hours)h \(minutes)m")
        }
        if hours > 0 {
            return L10n.text("\(hours)h \(minutes)m")
        }
        return L10n.text("\(minutes)m")
    }

    static func elapsedAgoText(from startDate: Date, to endDate: Date, simplified: Bool) -> String {
        L10n.text("\(elapsedText(from: startDate, to: endDate, simplified: simplified)) ago")
    }

    static func calendarDayRelativeText(
        for targetDate: Date,
        relativeTo now: Date,
        calendar: Calendar = .current
    ) -> String {
        let targetDay = calendar.startOfDay(for: targetDate)
        let currentDay = calendar.startOfDay(for: now)
        let dayOffset = calendar.dateComponents([.day], from: currentDay, to: targetDay).day ?? 0

        if dayOffset == 0 { return L10n.text("today") }
        if dayOffset == 1 { return L10n.text("tomorrow") }

        let isFuture = dayOffset > 0
        let absoluteDayOffset = abs(dayOffset)
        let (amount, unit): (Int, String)

        let earlierDay = isFuture ? currentDay : targetDay
        let laterDay = isFuture ? targetDay : currentDay
        let yearOffset = calendar.dateComponents([.year], from: earlierDay, to: laterDay).year ?? 0
        let monthOffset = calendar.dateComponents([.month], from: earlierDay, to: laterDay).month ?? 0

        if yearOffset >= 1 {
            amount = yearOffset
            unit = yearOffset == 1 ? L10n.text("year") : L10n.text("years")
        } else if monthOffset >= 1 {
            amount = monthOffset
            unit = monthOffset == 1 ? L10n.text("month") : L10n.text("months")
        } else if absoluteDayOffset >= 7 {
            amount = max(1, absoluteDayOffset / 7)
            unit = amount == 1 ? L10n.text("week") : L10n.text("weeks")
        } else {
            amount = absoluteDayOffset
            unit = amount == 1 ? L10n.text("day") : L10n.text("days")
        }

        if isFuture {
            return L10n.text("in \(amount) \(unit)")
        }
        return L10n.text("\(amount) \(unit) ago")
    }

    static func singleUnitDurationText(seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        if clampedSeconds < 60 { return L10n.text("\(clampedSeconds)s") }

        let days = clampedSeconds / 86_400
        if days > 0 { return L10n.text("\(days)d") }

        let hours = clampedSeconds / 3_600
        if hours > 0 { return L10n.text("\(hours)h") }

        return L10n.text("\(clampedSeconds / 60)m")
    }

    static func leadTimeDescription(for title: String, targetDate: Date, now: Date) -> String {
        L10n.text("\(title) starts in \(leadTimeText(targetDate: targetDate, now: now)).")
    }

    static func dueTimeDescription(for title: String, targetDate: Date, now: Date) -> String {
        L10n.text("\(title) — due in \(leadTimeText(targetDate: targetDate, now: now)).")
    }

    private static func leadTimeText(targetDate: Date, now: Date) -> String {
        let remainingSeconds = max(Int(targetDate.timeIntervalSince(now)), 0)
        if remainingSeconds < 60 { return L10n.text("\(remainingSeconds)s") }
        let remainingMinutes = max(1, Int(ceil(Double(remainingSeconds) / 60.0)))
        return L10n.text("\(remainingMinutes) minute\(remainingMinutes == 1 ? "" : "s")")
    }
}
