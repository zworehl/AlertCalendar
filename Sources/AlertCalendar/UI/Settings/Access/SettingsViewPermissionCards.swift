import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    struct SettingsCardBadgeState {
        let title: String
        let tint: Color
    }

    @ViewBuilder
    func permissionActionCard(for permission: SettingsPermissionKind) -> some View {
        let grantState = permissionGrantState(for: permission)
        let isRequesting = activePermissionRequests.contains(permission)

        VStack(alignment: .leading, spacing: 14) {
            permissionActionCardHeader(for: permission, grantState: grantState)

            Text(permission.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(permissionGrantDescription(for: permission, state: grantState))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let message = permissionActionMessages[permission] {
                Label(message, systemImage: grantState == .allowed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(grantState == .allowed ? Color.green : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if permission == .location {
                AstronomyCoordinatesCard(
                    useAutomaticAstronomyLocation: $draft.useAutomaticAstronomyLocation,
                    astronomyLatitude: $draft.astronomyLatitude,
                    astronomyLongitude: $draft.astronomyLongitude,
                    onDetectNow: detectLocation
                )
            }

            permissionActionButtons(
                for: permission,
                grantState: grantState,
                isRequesting: isRequesting
            )
        }
        .settingsPanelSurface(borderColor: permissionBorderColor(for: grantState))
    }

    @ViewBuilder
    func permissionActionCardHeader(for permission: SettingsPermissionKind, grantState: PermissionGrantState) -> some View {
        let headerStatus = permissionHeaderStatusText(for: permission)

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                SettingsPermissionIconView(
                    fallbackSymbolName: permission.fallbackSymbolName,
                    gradient: permission.accentGradient,
                    appIconPath: permission.appIconPath
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(permission.title)
                        .font(SettingsTypography.sectionTitle)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)

                    permissionStatusBadge(for: grantState)
                }

                if let headerStatus {
                    Spacer(minLength: 12)

                    permissionHeaderStatusLabel(headerStatus)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    SettingsPermissionIconView(
                        fallbackSymbolName: permission.fallbackSymbolName,
                        gradient: permission.accentGradient,
                        appIconPath: permission.appIconPath
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(permission.title)
                            .font(SettingsTypography.sectionTitle)
                            .fixedSize(horizontal: false, vertical: true)

                        permissionStatusBadge(for: grantState)
                    }
                }

                if let headerStatus {
                    permissionHeaderStatusLabel(headerStatus)
                }
            }
        }
    }

    @ViewBuilder
    func permissionHeaderStatusLabel(_ status: String) -> some View {
        Text(status)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    func permissionHeaderStatusText(for permission: SettingsPermissionKind) -> String? {
        guard permission == .location else { return nil }
        guard astronomyLocationStatus != "Manual coordinates" else { return nil }
        guard draft.useAutomaticAstronomyLocation else { return astronomyLocationStatus }
        return isAutomaticLocationResultStatus ? nil : astronomyLocationStatus
    }

    var isAutomaticLocationResultStatus: Bool {
        astronomyLocationStatus.hasPrefix("Auto location:")
            || astronomyLocationStatus.hasPrefix("Approximate auto location:")
            || astronomyLocationStatus.hasPrefix("Detected location:")
            || astronomyLocationStatus.hasPrefix("Detected approximate location:")
            || astronomyLocationStatus.contains("Using saved coordinates:")
    }

    @ViewBuilder
    func integrationActionCard(for integration: SettingsIntegrationKind) -> some View {
        let badgeState = integrationBadgeState(for: integration)

        slackIntegrationActionCard(badgeState: badgeState)
    }

    @ViewBuilder
    func integrationActionCardHeader(
        for integration: SettingsIntegrationKind,
        badgeState: SettingsCardBadgeState
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                SettingsPermissionIconView(
                    fallbackSymbolName: integration.fallbackSymbolName,
                    gradient: integration.accentGradient,
                    appIconPath: integration.appIconPath
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(integration.title)
                        .font(SettingsTypography.sectionTitle)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)

                    cardStatusBadge(badgeState)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            HStack(alignment: .top, spacing: 12) {
                SettingsPermissionIconView(
                    fallbackSymbolName: integration.fallbackSymbolName,
                    gradient: integration.accentGradient,
                    appIconPath: integration.appIconPath
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(integration.title)
                        .font(SettingsTypography.sectionTitle)
                        .fixedSize(horizontal: false, vertical: true)

                    cardStatusBadge(badgeState)
                }
            }
        }
    }

    @ViewBuilder
    func permissionActionButtons(
        for permission: SettingsPermissionKind,
        grantState: PermissionGrantState,
        isRequesting: Bool
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)

                permissionPrimaryButton(
                    for: permission,
                    grantState: grantState,
                    isRequesting: isRequesting
                )

                if grantState != .denied && grantState != .restricted {
                    permissionSettingsButton(for: permission)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(alignment: .leading, spacing: 8) {
                permissionPrimaryButton(
                    for: permission,
                    grantState: grantState,
                    isRequesting: isRequesting
                )

                if grantState != .denied && grantState != .restricted {
                    permissionSettingsButton(for: permission)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    func integrationActionButtons(for _: SettingsIntegrationKind) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                slackIntegrationPrimaryButton

                Button {
                    extractSlackTokenFromClipboard()
                } label: {
                    Label("Extract Token", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 10) {
                slackIntegrationPrimaryButton

                Button {
                    extractSlackTokenFromClipboard()
                } label: {
                    Label("Extract Token", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    var slackIntegrationPrimaryButton: some View {
        Button {
            connectSlackToken()
        } label: {
            Label(
                slackIntegrationPrimaryButtonTitle,
                systemImage: "key.fill"
            )
        }
        .buttonStyle(.borderedProminent)
        .disabled(slackUserTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help("Stage this Slack connection. It will connect when you click Apply.")
    }

    var slackIntegrationPrimaryButtonTitle: String {
        slackConnections.isEmpty ? "Connect Token" : "Reconnect Token"
    }

}
