import Foundation

struct WorkingDayRules: Equatable {
    static let selectableDayCount = 28

    var nonWorkingDateKeys: Set<String>
    var calendar: Calendar

    init(nonWorkingDateKeys: Set<String> = [], calendar: Calendar = .current) {
        self.nonWorkingDateKeys = nonWorkingDateKeys
        self.calendar = calendar
    }

    func isWorkingDay(_ date: Date) -> Bool {
        Self.isWeekday(date, calendar: calendar)
            && !nonWorkingDateKeys.contains(Self.dateKey(for: date, calendar: calendar))
    }

    func workingDuration(from start: Date, to end: Date) -> TimeInterval {
        guard end > start else { return 0 }

        var cursor = start
        var total: TimeInterval = 0

        while cursor < end {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let segmentEnd = min(end, nextDayStart)
            if isWorkingDay(dayStart) {
                total += segmentEnd.timeIntervalSince(cursor)
            }
            cursor = segmentEnd
        }

        return total
    }

    static func isWeekday(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return (2 ... 6).contains(weekday)
    }

    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return dateKey(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
    }

    static func selectableDates(now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let startDay = calendar.startOfDay(for: now)
        return (0 ..< selectableDayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startDay)
        }
    }

    static func selectableDateKeys(now: Date = Date(), calendar: Calendar = .current) -> [String] {
        selectableDates(now: now, calendar: calendar)
            .filter { isWeekday($0, calendar: calendar) }
            .map { dateKey(for: $0, calendar: calendar) }
    }

    static func selectableCalendarGridDates(now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let selectableDates = selectableDates(now: now, calendar: calendar)
        guard let firstDate = selectableDates.first,
              let lastDate = selectableDates.last
        else {
            return []
        }

        let gridStart = sundayStartOfWeek(containing: firstDate, calendar: calendar)
        let lastWeekStart = sundayStartOfWeek(containing: lastDate, calendar: calendar)
        guard let gridEnd = calendar.date(byAdding: .day, value: 7, to: lastWeekStart) else {
            return []
        }

        var dates: [Date] = []
        var cursor = gridStart
        while cursor < gridEnd {
            dates.append(cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }
        return dates
    }

    static func normalizedNonWorkingDateKeys(
        _ rawKeys: Set<String>,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Set<String> {
        let validKeys = Set(selectableDateKeys(now: now, calendar: calendar))
        return Set(rawKeys.compactMap { rawKey in
            guard let normalizedKey = normalizedDateKey(rawKey, calendar: calendar),
                  validKeys.contains(normalizedKey)
            else {
                return nil
            }
            return normalizedKey
        })
    }

    static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        guard let components = dateComponents(fromKey: key) else { return nil }
        var dateComponents = DateComponents()
        dateComponents.calendar = calendar
        dateComponents.timeZone = calendar.timeZone
        dateComponents.year = components.year
        dateComponents.month = components.month
        dateComponents.day = components.day

        guard let date = calendar.date(from: dateComponents) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == components.year,
              roundTrip.month == components.month,
              roundTrip.day == components.day
        else {
            return nil
        }

        return calendar.startOfDay(for: date)
    }

    static func normalizedDateKey(_ rawKey: String, calendar: Calendar = .current) -> String? {
        guard let date = date(fromKey: rawKey, calendar: calendar) else { return nil }
        return dateKey(for: date, calendar: calendar)
    }

    private static func dateComponents(fromKey key: String) -> (year: Int, month: Int, day: Int)? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }

        return (year, month, day)
    }

    private static func dateKey(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func sundayStartOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dayStart)
        return calendar.date(byAdding: .day, value: 1 - weekday, to: dayStart) ?? dayStart
    }
}
