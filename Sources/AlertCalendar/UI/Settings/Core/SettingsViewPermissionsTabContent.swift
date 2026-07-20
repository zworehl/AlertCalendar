import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var permissionsSettingsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection(
                title: "Access Overview",
                subtitle: "Check the app-level state and jump straight to macOS privacy controls when needed.",
                systemImage: "lock.shield"
            ) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            statusPill(title: "Current Access", value: calendarAccessDescription)
                            statusPill(
                                title: "Last Refresh",
                                value: lastRefreshDate.map { Self.settingsDateFormatter.string(from: $0) } ?? "Waiting for first sync..."
                            )
                        }

                        Spacer(minLength: 12)

                        permissionOverviewActions
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        statusPill(title: "Current Access", value: calendarAccessDescription)
                        statusPill(
                            title: "Last Refresh",
                            value: lastRefreshDate.map { Self.settingsDateFormatter.string(from: $0) } ?? "Waiting for first sync..."
                        )

                        permissionOverviewActions
                    }
                }
            }

            LazyVGrid(columns: permissionActionGridColumns, alignment: .leading, spacing: 12) {
                ForEach(SettingsPermissionKind.allCases) { permission in
                    permissionActionCard(for: permission)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            settingsSection(
                title: "Diagnostics",
                subtitle: "Refresh details for the last scheduler pass.",
                systemImage: "waveform.path.ecg"
            ) {
                DisclosureGroup("Refresh diagnostics", isExpanded: $isShowingPermissionDiagnostics) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 18) {
                            statusPill(title: "Reason", value: refreshDiagnostics.summary)
                            statusPill(title: "Pending", value: refreshDiagnostics.pendingSummary)
                            statusPill(title: "Feed requests", value: "\(externalFeedDiagnostics.networkRequests)")
                            statusPill(title: "Cache hits", value: "\(externalFeedDiagnostics.cacheHits)")
                            statusPill(title: "Feed failures", value: "\(externalFeedDiagnostics.failures)")
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            statusPill(title: "Reason", value: refreshDiagnostics.summary)
                            statusPill(title: "Pending", value: refreshDiagnostics.pendingSummary)
                            statusPill(title: "Feed requests", value: "\(externalFeedDiagnostics.networkRequests)")
                            statusPill(title: "Cache hits", value: "\(externalFeedDiagnostics.cacheHits)")
                            statusPill(title: "Feed failures", value: "\(externalFeedDiagnostics.failures)")
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    var permissionActionGridColumns: [GridItem] {
        if settingsWindowWidth >= 1380 {
            return [
                GridItem(.flexible(minimum: 260), spacing: 12, alignment: .top),
                GridItem(.flexible(minimum: 260), spacing: 12, alignment: .top),
                GridItem(.flexible(minimum: 260), spacing: 12, alignment: .top),
                GridItem(.flexible(minimum: 260), spacing: 12, alignment: .top)
            ]
        }
        if settingsWindowWidth >= 940 {
            return [
                GridItem(.flexible(minimum: 300), spacing: 12, alignment: .top),
                GridItem(.flexible(minimum: 300), spacing: 12, alignment: .top)
            ]
        }
        return [GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top)]
    }

    @ViewBuilder
    var permissionOverviewActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Button {
                    refreshPermissionStatuses(forceRefresh: true)
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    openPrivacySettings()
                } label: {
                    Label("Open Privacy", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    refreshPermissionStatuses(forceRefresh: true)
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    openPrivacySettings()
                } label: {
                    Label("Open Privacy", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
        }
    }

}
