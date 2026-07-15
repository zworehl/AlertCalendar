import Foundation

enum GameSaleCalendarAlertOption: String, CaseIterable, Identifiable, Sendable {
    case none
    case atTimeOfEvent
    case fifteenMinutesBefore
    case oneHourBefore
    case oneDayBefore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "None"
        case .atTimeOfEvent:
            return "At time of event"
        case .fifteenMinutesBefore:
            return "15 minutes before"
        case .oneHourBefore:
            return "1 hour before"
        case .oneDayBefore:
            return "1 day before"
        }
    }

    func relativeOffset() -> TimeInterval? {
        switch self {
        case .none:
            return nil
        case .atTimeOfEvent:
            return 0
        case .fifteenMinutesBefore:
            return -15 * 60
        case .oneHourBefore:
            return -60 * 60
        case .oneDayBefore:
            return -24 * 60 * 60
        }
    }
}

struct ManagedGameSaleEventRecord: Codable, Equatable, Sendable {
    let sale: GameSaleEvent
    let calendarIdentifier: String
    let eventIdentifier: String?
    let eventUID: String?

    var saleID: String { sale.id }
}

enum GameSalePresence: Equatable, Sendable {
    case absent
    case external
    case managed
}

struct GameSaleNotificationMessage: Equatable, Sendable {
    let title: String
    let body: String
}
