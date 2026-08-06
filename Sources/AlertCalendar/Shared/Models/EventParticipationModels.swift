import Foundation

enum EventParticipationStatus: String, Equatable {
    case accepted
    case tentative
    case pending
    case declined

    var usesTexturedFill: Bool {
        switch self {
        case .accepted:
            return false
        case .tentative, .pending, .declined:
            return true
        }
    }

    var appleCalendarBackgroundAlpha: CGFloat {
        switch self {
        case .accepted, .tentative:
            return 0.30
        case .pending:
            return 0.24
        case .declined:
            return 0.20
        }
    }

    var appleCalendarTextAlpha: CGFloat {
        switch self {
        case .accepted:
            return 1.0
        case .tentative:
            return 0.88
        case .pending:
            return 0.74
        case .declined:
            return 0.62
        }
    }

    var appleCalendarStripeAlpha: CGFloat {
        switch self {
        case .accepted:
            return 0
        case .tentative:
            return 0.16
        case .pending:
            return 0.18
        case .declined:
            return 0.24
        }
    }

    var appleCalendarStripeSpacing: CGFloat {
        switch self {
        case .accepted, .tentative:
            return 6
        case .pending:
            return 7
        case .declined:
            return 5
        }
    }
}
