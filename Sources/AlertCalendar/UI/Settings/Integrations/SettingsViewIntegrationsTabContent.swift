import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var integrationsSettingsContent: some View {
        VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
            settingsSectionHeader(
                title: "Connected Services",
                subtitle: "Manage calendar, Apple Music, and YouTube Music activity in your Slack status.",
                systemImage: "puzzlepiece.extension"
            )

            integrationActionCard(for: .slackStatusSync)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
