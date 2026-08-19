import SwiftUI

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

        var subtitle: String {
            switch self {
            case .atmosphere:
                return "Bring daylight, lunar phases, and orbital moments into your schedule."
            case .holidays:
                return "Combine regional holiday feeds into a writable Apple Calendar."
            case .football:
                return "Follow supported competitions and add fixtures automatically."
            case .gameSales:
                return "Track upcoming promotions from your favorite game stores."
            }
        }

        var tint: Color {
            switch self {
            case .atmosphere:
                return Color(nsColor: .systemOrange)
            case .holidays:
                return Color(nsColor: .systemGreen)
            case .football:
                return Color(nsColor: .systemBrown)
            case .gameSales:
                return Color(nsColor: .systemIndigo)
            }
        }

        var usesEmbeddedDetailScroller: Bool {
            switch self {
            case .football:
                return true
            case .atmosphere, .holidays, .gameSales:
                return false
            }
        }
    }
}
