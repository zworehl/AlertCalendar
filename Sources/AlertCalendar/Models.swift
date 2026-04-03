import AppKit
import Foundation

enum CalendarItemKind: String {
    case event = "Event"
    case reminder = "Reminder"
}

struct UpcomingItem: Identifiable, Equatable {
    let id: String
    let title: String
    let date: Date
    let endDate: Date?
    let isAllDay: Bool
    let showsMutedBackground: Bool
    let travelTimeMinutes: Int?
    let locationText: String?
    let meetingURL: URL?
    let calendarID: String?
    let calendarName: String
    let calendarColor: NSColor
    let kind: CalendarItemKind
    let footballMatch: FootballFixtureMatch?
    let footballMenuBarDisplay: FootballMenuBarDisplay?

    var notificationKey: String {
        "\(id)|\(Int(date.timeIntervalSince1970))|\(kind.rawValue)|\(isAllDay)"
    }
}

enum ActiveEventDisplayMode: String, CaseIterable, Identifiable {
    case remaining
    case elapsed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .remaining:
            return "Show time remaining"
        case .elapsed:
            return "Show elapsed time"
        }
    }
}

struct AvailableCalendar: Identifiable, Equatable {
    let id: String
    let title: String
    let color: NSColor
    let kind: CalendarItemKind
    let accountTitle: String
    let isSubscribed: Bool
}

enum MenuMarkerStyle: Equatable {
    case color(NSColor)
    case reminder(NSColor)
    case birthday(NSColor)
    case allDay(NSColor)
    case sunrise
    case solarNoon
    case sunset
    case solarMidnight

    static func == (lhs: MenuMarkerStyle, rhs: MenuMarkerStyle) -> Bool {
        switch (lhs, rhs) {
        case let (.color(left), .color(right)):
            return left.isEqual(right)
        case let (.reminder(left), .reminder(right)):
            return left.isEqual(right)
        case let (.birthday(left), .birthday(right)):
            return left.isEqual(right)
        case let (.allDay(left), .allDay(right)):
            return left.isEqual(right)
        case (.sunrise, .sunrise), (.solarNoon, .solarNoon), (.sunset, .sunset), (.solarMidnight, .solarMidnight):
            return true
        default:
            return false
        }
    }
}

extension UpcomingItem {
    static func == (lhs: UpcomingItem, rhs: UpcomingItem) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.date == rhs.date
            && lhs.endDate == rhs.endDate
            && lhs.isAllDay == rhs.isAllDay
            && lhs.showsMutedBackground == rhs.showsMutedBackground
            && lhs.travelTimeMinutes == rhs.travelTimeMinutes
            && lhs.locationText == rhs.locationText
            && lhs.meetingURL == rhs.meetingURL
            && lhs.calendarID == rhs.calendarID
            && lhs.calendarName == rhs.calendarName
            && colorsAreEqual(lhs.calendarColor, rhs.calendarColor)
            && lhs.kind == rhs.kind
            && lhs.footballMatch == rhs.footballMatch
            && lhs.footballMenuBarDisplay == rhs.footballMenuBarDisplay
    }
}

extension AvailableCalendar {
    static func == (lhs: AvailableCalendar, rhs: AvailableCalendar) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && colorsAreEqual(lhs.color, rhs.color)
            && lhs.kind == rhs.kind
            && lhs.accountTitle == rhs.accountTitle
            && lhs.isSubscribed == rhs.isSubscribed
    }
}

private func colorsAreEqual(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
    lhs.isEqual(rhs)
}
