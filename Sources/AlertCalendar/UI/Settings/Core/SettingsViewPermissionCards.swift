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

            Spacer(minLength: 0)

            permissionActionButtons(
                for: permission,
                grantState: grantState,
                isRequesting: isRequesting
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(permissionBorderColor(for: grantState), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    func permissionActionCardHeader(for permission: SettingsPermissionKind, grantState: PermissionGrantState) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                SettingsPermissionIconView(
                    fallbackSymbolName: permission.fallbackSymbolName,
                    gradient: permission.accentGradient,
                    appIconPath: permission.appIconPath
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(permission.title)
                        .font(.headline)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)

                    permissionStatusBadge(for: grantState)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            HStack(alignment: .top, spacing: 12) {
                SettingsPermissionIconView(
                    fallbackSymbolName: permission.fallbackSymbolName,
                    gradient: permission.accentGradient,
                    appIconPath: permission.appIconPath
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(permission.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    permissionStatusBadge(for: grantState)
                }
            }
        }
    }

    @ViewBuilder
    func integrationActionCard(for integration: SettingsIntegrationKind) -> some View {
        let badgeState = integrationBadgeState(for: integration)

        if integration == .slackStatusSync {
            slackIntegrationActionCard(badgeState: badgeState)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                integrationActionCardHeader(for: integration, badgeState: badgeState)

                Text(integration.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(integrationDescription(for: integration))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                integrationActionButtons(for: integration)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(badgeState.tint.opacity(0.24), lineWidth: 1)
                    )
            )
        }
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
                        .font(.headline)
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
                        .font(.headline)
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
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            permissionPrimaryButton(
                for: permission,
                grantState: grantState,
                isRequesting: isRequesting
            )

            permissionSettingsButton(for: permission)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    func integrationActionButtons(for integration: SettingsIntegrationKind) -> some View {
        switch integration {
        case .focusFilters:
            HStack(spacing: 10) {
                Spacer(minLength: 0)

                Button {
                    synchronizeActiveFocusFilterNow()
                } label: {
                    Label("Sync Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openSystemSettingsRoot()
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .slackStatusSync:
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
    }

    var slackIntegrationPrimaryButtonTitle: String {
        slackConnections.isEmpty ? "Connect Token" : "Reconnect Token"
    }

    func updatePermissionButtonsLayout(windowWidth: CGFloat) {
        let spacing: CGFloat = 12
        let horizontalPadding: CGFloat = 40
        let availableWidth = max(windowWidth - horizontalPadding, 0)
        let fiveAcrossMinimumWidth: CGFloat = 270
        let threeAcrossMinimumWidth: CGFloat = 320
        let nextRowCounts: [Int]

        if availableWidth >= (fiveAcrossMinimumWidth * 5) + (spacing * 4) {
            nextRowCounts = [5]
        } else if availableWidth >= (threeAcrossMinimumWidth * 3) + (spacing * 2) {
            nextRowCounts = [3, 2]
        } else {
            nextRowCounts = [2, 2, 1]
        }

        if nextRowCounts != compactActionRowCounts {
            compactActionRowCounts = nextRowCounts
        }
    }

    var compactActionCards: [SettingsActionCardKind] {
        SettingsPermissionKind.allCases.map(SettingsActionCardKind.permission) + [.integration(.focusFilters)]
    }

    var compactActionCardRows: [[SettingsActionCardKind]] {
        let items = compactActionCards
        var rows: [[SettingsActionCardKind]] = []
        var startIndex = 0

        for rowCount in compactActionRowCounts where startIndex < items.count {
            let endIndex = min(startIndex + rowCount, items.count)
            rows.append(Array(items[startIndex ..< endIndex]))
            startIndex = endIndex
        }

        if startIndex < items.count {
            rows.append(Array(items[startIndex...]))
        }

        return rows
    }

    @ViewBuilder
    func compactActionCard(for card: SettingsActionCardKind) -> some View {
        switch card {
        case let .permission(permission):
            permissionActionCard(for: permission)
        case let .integration(integration):
            integrationActionCard(for: integration)
        }
    }
}
