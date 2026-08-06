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
        currentSettings
    }

    func normalizedTitle(_ rawTitle: String?) -> String {
        AlertCalendarString.trimmedNonEmpty(rawTitle) ?? "(Untitled)"
    }

    func markerStyle(for item: UpcomingItem, now: Date? = nil) -> MenuMarkerStyle {
        if let now, Self.shouldShowTravelDepartureState(for: item, now: now) {
            return .travel(item.calendarColor)
        }
        if item.kind == .reminder {
            return .reminder(item.calendarColor)
        }
        if isBirthdayItem(item) {
            return .birthday(item.calendarColor)
        }
        if let gameStore = item.gameStore {
            return .gameStore(gameStore)
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
        if item.kind == .reminder, item.date <= now {
            return item.calendarColor.nsColor.withAlphaComponent(0.26)
        }
        return .clear
    }

    func segmentBackgroundVisual(for item: UpcomingItem, now: Date, settings: AppSettings) -> (color: NSColor, progress: CGFloat) {
        if let progress = Self.travelDepartureProgress(for: item, now: now) {
            return (item.calendarColor.nsColor.withAlphaComponent(0.30), progress)
        }

        if let progress = activeEventProgress(for: item, now: now, settings: settings) {
            return (item.calendarColor.nsColor.withAlphaComponent(0.30), progress)
        }

        let fullTint = backgroundTintColor(for: item, now: now)
        if fullTint.alphaComponent > 0.01 {
            return (fullTint, 1.0)
        }

        return (.clear, 0)
    }

    func menuBarAccessorySymbolNames(for item: UpcomingItem) -> [String] {
        let isBirthday = isBirthdayItem(item)
        return Self.menuBarAccessorySymbolNames(
            for: item,
            includesDocumentIndicator: !isBirthday,
            includesRecurrenceIndicator: !isBirthday
        )
    }

    nonisolated static func menuBarAccessorySymbolNames(
        for item: UpcomingItem,
        includesDocumentIndicator: Bool = true,
        includesRecurrenceIndicator: Bool = true
    ) -> [String] {
        var symbolNames: [String] = []
        if item.kind == .event, item.hasDocumentIndicator, includesDocumentIndicator {
            symbolNames.append("paperclip")
        }
        if item.isRecurring, includesRecurrenceIndicator {
            symbolNames.append("repeat")
        }

        return symbolNames
    }

    func activeEventProgress(for item: UpcomingItem, now: Date, settings: AppSettings) -> CGFloat? {
        Self.activeItemProgress(
            for: item,
            now: now,
            weekdayOnlyEventCalendarIDs: settings.weekdayOnlyEventCalendarIDs,
            weekdayOnlyDuration: { start, end in
                weekdayOnlyDuration(from: start, to: end, nonWorkingDateKeys: settings.nonWorkingDateKeys)
            }
        )
    }

    func activeParticipationTextureStatus(
        for item: UpcomingItem,
        now: Date,
        settings: AppSettings
    ) -> EventParticipationStatus? {
        Self.activeParticipationTextureStatus(
            for: item,
            now: now,
            weekdayOnlyEventCalendarIDs: settings.weekdayOnlyEventCalendarIDs,
            weekdayOnlyDuration: { start, end in
                weekdayOnlyDuration(from: start, to: end, nonWorkingDateKeys: settings.nonWorkingDateKeys)
            }
        )
    }

    nonisolated static func activeParticipationTextureStatus(
        for item: UpcomingItem,
        now: Date,
        weekdayOnlyEventCalendarIDs: Set<String>,
        weekdayOnlyDuration: (Date, Date) -> TimeInterval = { start, end in
            end.timeIntervalSince(start)
        }
    ) -> EventParticipationStatus? {
        guard let status = item.eventParticipationStatus,
              status.usesTexturedFill,
              activeItemProgress(
                  for: item,
                  now: now,
                  weekdayOnlyEventCalendarIDs: weekdayOnlyEventCalendarIDs,
                  weekdayOnlyDuration: weekdayOnlyDuration
              ) != nil else {
            return nil
        }

        return status
    }

    nonisolated static func travelStartDate(for item: UpcomingItem) -> Date? {
        guard item.kind == .event,
              !item.isAllDay,
              item.meetingURL == nil,
              let travelTimeMinutes = item.travelTimeMinutes,
              travelTimeMinutes > 0
        else {
            return nil
        }

        return item.date.addingTimeInterval(TimeInterval(-travelTimeMinutes * 60))
    }

    nonisolated static func shouldShowTravelDepartureState(for item: UpcomingItem, now: Date) -> Bool {
        guard travelStartDate(for: item) != nil else { return false }
        return now < item.date
    }

    nonisolated static func travelDepartureProgress(for item: UpcomingItem, now: Date) -> CGFloat? {
        guard let travelStartDate = travelStartDate(for: item),
              travelStartDate <= now,
              now < item.date
        else {
            return nil
        }

        let travelDuration = item.date.timeIntervalSince(travelStartDate)
        guard travelDuration > 0 else { return nil }

        let elapsed = now.timeIntervalSince(travelStartDate)
        return min(max(CGFloat(elapsed / travelDuration), 0), 1)
    }

    nonisolated static func activeItemProgress(
        for item: UpcomingItem,
        now: Date,
        weekdayOnlyEventCalendarIDs: Set<String>,
        weekdayOnlyDuration: (Date, Date) -> TimeInterval = { start, end in
            end.timeIntervalSince(start)
        }
    ) -> CGFloat? {
        if item.kind == .reminder {
            return item.date <= now ? 1 : nil
        }

        guard item.kind == .event else { return nil }
        guard let endDate = item.endDate, endDate > item.date else { return nil }
        guard item.date <= now, now < endDate else { return nil }

        let totalDuration: TimeInterval
        let elapsed: TimeInterval
        if item.kind == .event,
           let calendarID = item.calendarID,
           weekdayOnlyEventCalendarIDs.contains(calendarID) {
            totalDuration = weekdayOnlyDuration(item.date, endDate)
            elapsed = weekdayOnlyDuration(item.date, now)
        } else {
            totalDuration = endDate.timeIntervalSince(item.date)
            elapsed = now.timeIntervalSince(item.date)
        }
        guard totalDuration > 0 else { return nil }

        return min(max(CGFloat(elapsed / totalDuration), 0), 1)
    }

    func weekdayOnlyDuration(
        from start: Date,
        to end: Date,
        nonWorkingDateKeys: Set<String> = []
    ) -> TimeInterval {
        WorkingDayRules(nonWorkingDateKeys: nonWorkingDateKeys).workingDuration(from: start, to: end)
    }
    func allDayLabel(for item: UpcomingItem, now: Date, simplified: Bool) -> String? {
        guard item.kind == .event, item.isAllDay else { return nil }
        return Self.allDayLabel(
            startDate: item.date,
            endDate: item.endDate,
            now: now,
            simplified: simplified
        )
    }

    nonisolated static func allDayLabel(
        startDate: Date,
        endDate: Date?,
        now: Date,
        simplified: Bool,
        calendar: Calendar = .current
    ) -> String {
        let startDay = calendar.startOfDay(for: startDate)
        if startDay > now {
            return "in \(formattedRelativeCountdown(to: startDay, from: now, simplified: simplified))"
        }

        guard let endDate else { return "all-day" }

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

        return Self.formattedAllDayRange(
            startDay: startDay,
            lastInclusiveDay: lastInclusiveDay,
            calendar: calendar
        )
    }

    func color(from calendar: EKCalendar) -> AlertCalendarColor {
        if let converted = NSColor(cgColor: calendar.cgColor) {
            return AlertCalendarColor(nsColor: converted)
        }
        return .systemBlue
    }

    func trimmedTitle(_ title: String, maxLength: Int) -> String {
        guard title.count > maxLength else { return title }
        let end = title.index(title.startIndex, offsetBy: maxLength - 1)
        return String(title[..<end])
    }

    nonisolated static func formattedRelativeCountdown(to targetDate: Date, from sourceDate: Date, simplified: Bool) -> String {
        AlertCalendarRelativeTimeFormatter.countdownText(
            to: targetDate,
            from: sourceDate,
            simplified: simplified
        )
    }

    func relativeCountdown(to targetDate: Date, from sourceDate: Date, simplified: Bool) -> String {
        Self.formattedRelativeCountdown(to: targetDate, from: sourceDate, simplified: simplified)
    }

    func elapsedCountdown(from startDate: Date, to endDate: Date, simplified: Bool) -> String {
        AlertCalendarRelativeTimeFormatter.elapsedText(
            from: startDate,
            to: endDate,
            simplified: simplified
        )
    }
}
