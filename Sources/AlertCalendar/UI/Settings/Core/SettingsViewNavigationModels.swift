import SwiftUI

extension SettingsView {
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
    }

    enum SettingsIntegrationKind: String, CaseIterable, Identifiable {
        case slackStatusSync

        var id: String { rawValue }

        var title: String {
            switch self {
            case .slackStatusSync:
                return "Slack Status Sync"
            }
        }

        var summary: String {
            switch self {
            case .slackStatusSync:
                return "Publish customizable Slack statuses before and during selected calendar events."
            }
        }

        var fallbackSymbolName: String {
            switch self {
            case .slackStatusSync:
                return "message.badge.waveform"
            }
        }

        var appIconPath: String {
            switch self {
            case .slackStatusSync:
                return "/Applications/Slack.app"
            }
        }

        var accentGradient: LinearGradient {
            switch self {
            case .slackStatusSync:
                return LinearGradient(
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
}
