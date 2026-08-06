import Foundation

enum CalendarItemKind: String {
    case event = "Event"
    case reminder = "Reminder"
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
    let color: AlertCalendarColor
    let kind: CalendarItemKind
    let accountTitle: String
    let isSubscribed: Bool
    var allowsContentModifications = true

    static func == (lhs: AvailableCalendar, rhs: AvailableCalendar) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.color == rhs.color
            && lhs.kind == rhs.kind
            && lhs.accountTitle == rhs.accountTitle
            && lhs.isSubscribed == rhs.isSubscribed
    }
}
