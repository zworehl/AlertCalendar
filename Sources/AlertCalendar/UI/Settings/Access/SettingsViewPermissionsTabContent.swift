import AppKit
import Combine
import Contacts
import CoreLocation
import EventKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var permissionsSettingsContent: some View {
        VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: SettingsVisualMetrics.pageSpacing) {
                    accessOverviewSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    browserProfileAccessSettingsSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
                    accessOverviewSection
                    browserProfileAccessSettingsSection
                }
            }

            LazyVGrid(columns: permissionActionGridColumns, alignment: .leading, spacing: 12) {
                ForEach(SettingsPermissionKind.allCases) { permission in
                    permissionActionCard(for: permission)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            settingsSection(
                title: L10n.text("Diagnostics"),
                subtitle: L10n.text("Refresh details for the last scheduler pass."),
                systemImage: "waveform.path.ecg"
            ) {
                dataRefreshIssuesContent
                DisclosureGroup("Refresh diagnostics", isExpanded: $isShowingPermissionDiagnostics) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 18) {
                            diagnosticsPills
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            diagnosticsPills
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    @ViewBuilder
    var accessOverviewSection: some View {
        settingsSection(
            title: L10n.text("Access Overview"),
            subtitle: L10n.text("Check the app-level state and jump straight to macOS privacy controls when needed."),
            systemImage: "lock.shield"
        ) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            statusPill(title: L10n.text("Current Access"), value: calendarAccessDescription)
                        }

                        Spacer(minLength: 12)

                        permissionOverviewActions
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        statusPill(title: L10n.text("Current Access"), value: calendarAccessDescription)

                        permissionOverviewActions
                    }
                }
            }

    }

    @ViewBuilder
    var diagnosticsPills: some View {
        statusPill(title: L10n.text("Reason"), value: refreshDiagnostics.summary)
        statusPill(title: L10n.text("Pending"), value: refreshDiagnostics.pendingSummary)
        statusPill(title: L10n.text("Phases"), value: refreshDiagnostics.phasesSummary)
        statusPill(title: L10n.text("Feed requests"), value: "\(externalFeedDiagnostics.networkRequests)")
        statusPill(title: L10n.text("Cache hits"), value: "\(externalFeedDiagnostics.cacheHits)")
        statusPill(title: L10n.text("Feed failures"), value: "\(externalFeedDiagnostics.failures)")
        statusPill(title: L10n.text("Feed p50 / p95"), value: Self.feedLatencySummary(externalFeedDiagnostics))
    }

    nonisolated static func feedLatencySummary(_ diagnostics: ExternalFeedDiagnostics) -> String {
        guard let median = diagnostics.medianRequestDuration,
              let p95 = diagnostics.p95RequestDuration else {
            return L10n.text("No samples")
        }
        return String(format: "%.2fs / %.2fs", median, p95)
    }

    var permissionActionGridColumns: [GridItem] {
        let columnCount: Int
        if settingsWindowWidth >= 1_500 {
            columnCount = 5
        } else if settingsWindowWidth >= 920 {
            columnCount = 3
        } else if settingsWindowWidth >= 600 {
            columnCount = 2
        } else {
            columnCount = 1
        }
        let column = GridItem(
            .flexible(minimum: columnCount == 1 ? 0 : 240, maximum: columnCount == 1 ? .infinity : 360),
            spacing: 12,
            alignment: .top
        )
        return Array(repeating: column, count: columnCount)
    }

    @ViewBuilder
    var permissionOverviewActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Button {
                    refreshPermissionStatuses(forceRefresh: true)
                } label: {
                    Label(L10n.text("Refresh Status"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    openPrivacySettings()
                } label: {
                    Label(L10n.text("Open Privacy…"), systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    refreshPermissionStatuses(forceRefresh: true)
                } label: {
                    Label(L10n.text("Refresh Status"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    openPrivacySettings()
                } label: {
                    Label(L10n.text("Open Privacy…"), systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
            }
        }
    }

}
