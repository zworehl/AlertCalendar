import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var permissionsSettingsContent: some View {
        GroupBox("Permissions Overview") {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) {
                        statusPill(title: "Current Access", value: calendarAccessDescription)
                        statusPill(
                            title: "Last Refresh",
                            value: lastRefreshDate.map { Self.settingsDateFormatter.string(from: $0) } ?? "Waiting for first sync..."
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        statusPill(title: "Current Access", value: calendarAccessDescription)
                        statusPill(
                            title: "Last Refresh",
                            value: lastRefreshDate.map { Self.settingsDateFormatter.string(from: $0) } ?? "Waiting for first sync..."
                        )
                    }
                }

                Text("Each permission can be retried individually. If macOS already denied one, use the matching Settings shortcut to allow it again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        GroupBox("Actions") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(compactActionCardRows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(row) { card in
                            compactActionCard(for: card)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                integrationActionCard(for: .slackStatusSync)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if permissionsShouldUseWideUtilityCardsLayout {
            HStack(alignment: .top, spacing: 12) {
                astronomyLocationSettingsCard
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                globalShortcutsSettingsCard
                    .frame(width: 360, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                astronomyLocationSettingsCard
                globalShortcutsSettingsCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var permissionsShouldUseWideUtilityCardsLayout: Bool {
        settingsWindowWidth >= 1180
    }

    @ViewBuilder
    var astronomyLocationSettingsCard: some View {
        GroupBox("Astronomy Location") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose whether astronomy previews should use automatic system location or manual coordinates. If you do not want to grant Location access, switch automatic location off and enter your own latitude/longitude below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                AstronomyCoordinatesCard(
                    useAutomaticAstronomyLocation: $draft.useAutomaticAstronomyLocation,
                    astronomyLatitude: $draft.astronomyLatitude,
                    astronomyLongitude: $draft.astronomyLongitude,
                    astronomyLocationStatus: astronomyLocationStatus,
                    onDetectNow: detectLocation
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    var globalShortcutsSettingsCard: some View {
        GroupBox("Global Shortcuts") {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Button {
                            refreshPermissionStatuses()
                        } label: {
                            Label("Refresh Permission Status", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            openPrivacySettings()
                        } label: {
                            Label("Open Privacy Settings", systemImage: "gearshape")
                        }
                        .buttonStyle(.bordered)
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            refreshPermissionStatuses()
                        } label: {
                            Label("Refresh Permission Status", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            openPrivacySettings()
                        } label: {
                            Label("Open Privacy Settings", systemImage: "gearshape")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Text("macOS only re-shows native permission prompts when the system considers the app eligible. If a permission stays denied, the per-permission Settings button is the reliable path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
