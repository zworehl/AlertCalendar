import Foundation

enum AlertCalendarDateRangeFormatter {
    nonisolated static func compactAllDayRange(
        startDay: Date,
        lastInclusiveDay: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let dateFormatter = makeDateFormatter(locale: locale, calendar: calendar)

        if calendar.isDate(startDay, inSameDayAs: lastInclusiveDay) {
            return dateFormatter.string(from: startDay)
        }

        let sameMonth = calendar.isDate(startDay, equalTo: lastInclusiveDay, toGranularity: .month)
            && calendar.isDate(startDay, equalTo: lastInclusiveDay, toGranularity: .year)
        if sameMonth {
            let monthText = makeMonthFormatter(locale: locale, calendar: calendar).string(from: startDay)
            let startDayNumber = calendar.component(.day, from: startDay)
            let endDayNumber = calendar.component(.day, from: lastInclusiveDay)
            if AlertCalendarLanguage.current == .spanishLatinAmerica {
                return "\(startDayNumber)-\(endDayNumber) \(monthText)"
            }
            return "\(monthText) \(startDayNumber)-\(endDayNumber)"
        }

        return "\(dateFormatter.string(from: startDay))-\(dateFormatter.string(from: lastInclusiveDay))"
    }

    private nonisolated static func makeDateFormatter(locale: Locale, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AlertCalendarLanguage.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }

    private nonisolated static func makeMonthFormatter(locale: Locale, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AlertCalendarLanguage.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MMM"
        return formatter
    }
}
