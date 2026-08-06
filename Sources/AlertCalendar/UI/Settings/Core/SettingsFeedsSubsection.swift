import Foundation

extension SettingsView {
    enum FeedsSubsection: String, CaseIterable, Identifiable {
        case atmosphere = "Atmosphere"
        case holidays = "Holidays"
        case football = "Football"
        case gameSales = "Game Sales"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .atmosphere:
                return "Atmosphere"
            case .holidays:
                return "Google Holidays"
            case .football:
                return "Football Fixtures"
            case .gameSales:
                return "Game Sales"
            }
        }

        var symbolName: String {
            switch self {
            case .atmosphere:
                return "sun.max"
            case .holidays:
                return "flag.2.crossed"
            case .football:
                return "sportscourt"
            case .gameSales:
                return "gamecontroller.fill"
            }
        }
    }
}
