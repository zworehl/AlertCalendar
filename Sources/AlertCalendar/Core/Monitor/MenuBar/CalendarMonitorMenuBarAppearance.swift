import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    func isTimedItemDisplayableInMenuBar(_ item: UpcomingItem, now: Date) -> Bool {
        guard !item.isAllDay else { return false }

        if let endDate = item.endDate {
            return endDate > now
        }

        if item.kind == .reminder {
            return true
        }

        return item.date >= now
    }

    func snapshotSettings() -> AppSettings {
        settingsStore.load()
    }

    func normalizedTitle(_ rawTitle: String?) -> String {
        guard let rawTitle else { return "(Untitled)" }
        let cleaned = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "(Untitled)" : cleaned
    }

    func markerStyle(for item: UpcomingItem) -> MenuMarkerStyle {
        if item.kind == .reminder {
            return .reminder(item.calendarColor)
        }
        if isBirthdayItem(item) {
            return .birthday(item.calendarColor)
        }
        if item.kind == .event, item.isAllDay {
            return .allDay(item.calendarColor)
        }
        if let moment = AstronomyMoment(eventTitle: item.title) {
            return moment.menuMarkerStyle
        }
        return .color(item.calendarColor)
    }

    func backgroundTintColor(for item: UpcomingItem, now: Date) -> NSColor {
        if item.showsMutedBackground {
            return item.calendarColor.withAlphaComponent(0.26)
        }
        if item.kind == .reminder, item.date <= now {
            return item.calendarColor.withAlphaComponent(0.26)
        }
        return .clear
    }

    func segmentBackgroundVisual(for item: UpcomingItem, now: Date, settings: AppSettings) -> (color: NSColor, progress: CGFloat) {
        if let progress = activeEventProgress(for: item, now: now, settings: settings) {
            return (item.calendarColor.withAlphaComponent(0.30), progress)
        }

        let fullTint = backgroundTintColor(for: item, now: now)
        if fullTint.alphaComponent > 0.01 {
            return (fullTint, 1.0)
        }

        return (.clear, 0)
    }

    func activeEventProgress(for item: UpcomingItem, now: Date, settings: AppSettings) -> CGFloat? {
        guard item.kind == .event else { return nil }
        guard let endDate = item.endDate, endDate > item.date else { return nil }
        guard item.date <= now, now < endDate else { return nil }

        let totalDuration: TimeInterval
        let elapsed: TimeInterval
        if item.kind == .event,
           let calendarID = item.calendarID,
           settings.weekdayOnlyEventCalendarIDs.contains(calendarID) {
            totalDuration = weekdayOnlyDuration(from: item.date, to: endDate)
            elapsed = weekdayOnlyDuration(from: item.date, to: now)
        } else {
            totalDuration = endDate.timeIntervalSince(item.date)
            elapsed = now.timeIntervalSince(item.date)
        }
        guard totalDuration > 0 else { return nil }

        return min(max(CGFloat(elapsed / totalDuration), 0), 1)
    }

    func weekdayOnlyDuration(from start: Date, to end: Date) -> TimeInterval {
        guard end > start else { return 0 }
        let calendar = Calendar.current
        var cursor = start
        var total: TimeInterval = 0

        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let segmentEnd = min(end, nextDayStart)
            if isWeekday(dayStart) {
                total += segmentEnd.timeIntervalSince(cursor)
            }
            cursor = segmentEnd
        }

        return total
    }
    func allDayLabel(for item: UpcomingItem) -> String? {
        guard item.kind == .event, item.isAllDay else { return nil }
        guard let endDate = item.endDate else { return "all-day" }

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: item.date)
        let endDay = calendar.startOfDay(for: endDate)
        let usesExclusiveEndDay = endDate == endDay
        let lastInclusiveDay: Date
        if usesExclusiveEndDay,
           let adjusted = calendar.date(byAdding: .day, value: -1, to: endDay) {
            lastInclusiveDay = adjusted
        } else {
            lastInclusiveDay = endDay
        }

        let daySpan = calendar.dateComponents([.day], from: startDay, to: lastInclusiveDay).day ?? 0
        guard daySpan >= 1 else { return "all-day" }

        let sameMonth = calendar.isDate(startDay, equalTo: lastInclusiveDay, toGranularity: .month)
            && calendar.isDate(startDay, equalTo: lastInclusiveDay, toGranularity: .year)
        if sameMonth {
            let monthText = Self.allDayMonthFormatter.string(from: startDay)
            let startDayNumber = calendar.component(.day, from: startDay)
            let endDayNumber = calendar.component(.day, from: lastInclusiveDay)
            return "\(monthText) \(startDayNumber)-\(endDayNumber)"
        }

        let startText = Self.allDayDateFormatter.string(from: startDay)
        let endText = Self.allDayDateFormatter.string(from: lastInclusiveDay)
        return "\(startText)-\(endText)"
    }

    func color(from calendar: EKCalendar) -> NSColor {
        if let converted = NSColor(cgColor: calendar.cgColor) {
            return converted
        }
        return .systemBlue
    }

    func trimmedTitle(_ title: String, maxLength: Int) -> String {
        guard title.count > maxLength else { return title }
        let end = title.index(title.startIndex, offsetBy: maxLength - 1)
        return String(title[..<end])
    }

    func relativeCountdown(to targetDate: Date, from sourceDate: Date, simplified: Bool) -> String {
        let remaining = max(Int(targetDate.timeIntervalSince(sourceDate)), 0)
        if remaining < 60 {
            return "\(remaining)s"
        }
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if simplified {
            if days > 0 {
                return "\(days)d"
            }
            if hours > 0 {
                return "\(hours)h"
            }
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

    func elapsedCountdown(from startDate: Date, to endDate: Date, simplified: Bool) -> String {
        let elapsed = max(Int(endDate.timeIntervalSince(startDate)), 0)
        if elapsed < 60 {
            return "\(elapsed)s"
        }
        let days = elapsed / 86_400
        let hours = (elapsed % 86_400) / 3_600
        let minutes = (elapsed % 3_600) / 60

        if simplified {
            if days > 0 {
                return "\(days)d"
            }
            if hours > 0 {
                return "\(hours)h"
            }
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
}
