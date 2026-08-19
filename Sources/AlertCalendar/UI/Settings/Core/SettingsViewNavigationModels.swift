import SwiftUI

extension SettingsView {
    enum SettingsSidebarDestination: Hashable {
        case tab(SettingsTab)
        case feed(FeedsSubsection)
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case feeds = "Feeds"
        case calendars = "Calendars"
        case integrations = "Integrations"
        case access = "Access"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .general:
                return "slider.horizontal.3"
            case .feeds:
                return "sun.max"
            case .calendars:
                return "calendar"
            case .integrations:
                return "puzzlepiece.extension"
            case .access:
                return "lock.shield"
            }
        }

        var subtitle: String {
            switch self {
            case .general:
                return "Configure alerts, the menu bar, and upcoming-item previews."
            case .feeds:
                return "Add useful external moments and events to your schedule."
            case .calendars:
                return "Choose sources and define how each calendar behaves."
            case .integrations:
                return "Connect services that react to your calendar activity."
            case .access:
                return "Review permissions, location, and refresh diagnostics."
            }
        }

        var tint: Color {
            switch self {
            case .general:
                return Color(nsColor: .systemGray)
            case .feeds:
                return Color(nsColor: .systemOrange)
            case .calendars:
                return Color(nsColor: .systemRed)
            case .integrations:
                return Color(nsColor: .systemPurple)
            case .access:
                return Color(nsColor: .systemTeal)
            }
        }
    }

    enum SettingsIntegrationKind: String, CaseIterable, Identifiable {
        case slackStatusSync

        var id: String { rawValue }
        var title: String { "Slack Status Sync" }
        var summary: String { "Publish Slack statuses around selected calendar events." }
        var fallbackSymbolName: String { "message.badge.waveform" }
        var appIconPath: String { "/Applications/Slack.app" }
        var accentGradient: LinearGradient {
            LinearGradient(
                colors: [
                    Color(red: 0.26, green: 0.76, blue: 0.52),
                    Color(red: 0.91, green: 0.23, blue: 0.47),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

enum SettingsNavigationPersistence {
    static let selectedTabKey = "settings.navigation.selectedTab"
    static let selectedFeedsSubsectionKey = "settings.navigation.selectedFeedsSubsection"
}
