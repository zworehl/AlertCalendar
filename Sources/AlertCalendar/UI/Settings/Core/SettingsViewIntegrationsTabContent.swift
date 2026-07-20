import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var integrationsSettingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSectionHeader(
                title: "Connected Services",
                subtitle: "Manage external services that react to your calendar activity.",
                systemImage: "puzzlepiece.extension"
            )

            integrationActionCard(for: .slackStatusSync)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
