import Foundation

enum GoogleHolidayICSParser {
    enum ParserError: LocalizedError, Equatable {
        case unreadableCalendar

        var errorDescription: String? {
            "The Google holiday calendar could not be read."
        }
    }

    static func parse(
        data: Data,
        countryID: String,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> [GoogleHolidaySourceEvent] {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw ParserError.unreadableCalendar
        }
        return try parse(text: text, countryID: countryID, calendar: calendar)
    }

    static func parse(
        text: String,
        countryID: String,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> [GoogleHolidaySourceEvent] {
        let lines = unfoldedLines(text)
        guard lines.contains("BEGIN:VCALENDAR") else {
            throw ParserError.unreadableCalendar
        }

        var events: [GoogleHolidaySourceEvent] = []
        var properties: [String: String] = [:]
        var isInsideEvent = false

        for line in lines {
            switch line {
            case "BEGIN:VEVENT":
                isInsideEvent = true
                properties.removeAll(keepingCapacity: true)
            case "END:VEVENT":
                if isInsideEvent,
                   properties["STATUS"]?.uppercased() != "CANCELLED",
                   let uid = AlertCalendarString.trimmedNonEmpty(properties["UID"]),
                   let title = AlertCalendarString.trimmedNonEmpty(properties["SUMMARY"]),
                   let startDate = properties["DTSTART"].flatMap({ parseDate($0, calendar: calendar) }) {
                    let fallbackEnd = calendar.date(byAdding: .day, value: 1, to: startDate)
                        ?? startDate.addingTimeInterval(86_400)
                    let endDate = properties["DTEND"].flatMap({ parseDate($0, calendar: calendar) })
                        ?? fallbackEnd
                    if endDate > startDate {
                        events.append(
                            GoogleHolidaySourceEvent(
                                sourceUID: uid,
                                countryID: countryID.uppercased(),
                                title: unescaped(title),
                                startDate: startDate,
                                endDateExclusive: endDate
                            )
                        )
                    }
                }
                isInsideEvent = false
                properties.removeAll(keepingCapacity: true)
            default:
                guard isInsideEvent, let separator = line.firstIndex(of: ":") else { continue }
                let rawName = String(line[..<separator])
                let name = rawName.split(separator: ";", maxSplits: 1).first.map(String.init)?.uppercased() ?? ""
                let value = String(line[line.index(after: separator)...])
                if !name.isEmpty {
                    properties[name] = value
                }
            }
        }

        return events
    }

    private static func unfoldedLines(_ text: String) -> [String] {
        let physicalLines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var lines: [String] = []

        for line in physicalLines {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1].append(contentsOf: line.dropFirst())
            } else {
                lines.append(line)
            }
        }
        return lines
    }

    private static func parseDate(_ value: String, calendar: Calendar) -> Date? {
        let rawDate = String(value.prefix(8))
        guard rawDate.count == 8,
              let year = Int(rawDate.prefix(4)),
              let month = Int(rawDate.dropFirst(4).prefix(2)),
              let day = Int(rawDate.suffix(2)) else {
            return nil
        }

        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func unescaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
