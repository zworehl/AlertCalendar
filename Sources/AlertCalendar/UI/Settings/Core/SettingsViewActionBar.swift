import SwiftUI

extension SettingsView {
    var settingsActionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                settingsOperationalStatus

                Spacer(minLength: 12)

                refreshSettingsButton
                settingsChangeStatus
                settingsActionButtons
            }

            VStack(alignment: .leading, spacing: 8) {
                settingsOperationalStatus
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    refreshSettingsButton

                    Spacer(minLength: 12)

                    settingsChangeStatus
                    settingsActionButtons
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.actionBar")
    }

    @ViewBuilder
    private var settingsOperationalStatus: some View {
        HStack(spacing: 12) {
            pollingFreshnessLabel

            if let calendarAlertRuleStatusDescription {
                Label(
                    calendarAlertRuleStatusDescription,
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(calendarAlertRuleStatusDescription)
            }
        }
    }

    private var settingsChangeStatus: some View {
        Label {
            Text(
                isApplyingChanges
                    ? "Applying changes…"
                    : (hasUnsavedChanges ? "Changes not applied" : "Settings are up to date")
            )
        } icon: {
            Image(
                systemName: isApplyingChanges
                    ? "arrow.triangle.2.circlepath"
                    : (hasUnsavedChanges ? "circle.fill" : "checkmark.circle")
            )
                .font(hasUnsavedChanges && !isApplyingChanges ? .system(size: 7, weight: .bold) : .caption)
        }
        .font(.caption)
        .foregroundStyle(hasUnsavedChanges || isApplyingChanges ? Color.orange : Color.secondary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier("settings.changeStatus")
    }

    private var refreshSettingsButton: some View {
        Button {
            refreshSettingsManually()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Image(systemName: "arrow.clockwise")
                        .hidden()

                    if isManualSettingsRefreshInProgress {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }

                Text("Refresh Now")
            }
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(isApplyingChanges)
        .allowsHitTesting(!isManualSettingsRefreshInProgress)
        .help("Refresh calendars and external feeds without applying pending configuration changes.")
        .accessibilityIdentifier("settings.refresh")
    }

    private func refreshSettingsManually() {
        guard !isManualSettingsRefreshInProgress else { return }

        isManualSettingsRefreshInProgress = true
        Task { @MainActor in
            let startedAt = Date()
            await monitor.enqueueRefreshAndWait(reason: .manual)

            // Very fast refreshes otherwise look like a rendering flash instead of feedback.
            let remainingPresentationTime = max(0, 0.5 - Date().timeIntervalSince(startedAt))
            if remainingPresentationTime > 0 {
                try? await Task.sleep(
                    nanoseconds: UInt64(remainingPresentationTime * 1_000_000_000)
                )
            }
            isManualSettingsRefreshInProgress = false
        }
    }

    private var settingsActionButtons: some View {
        HStack(spacing: 8) {
            Button("Revert Changes") {
                resetDraft()
            }
            .buttonStyle(.bordered)
            .disabled(!hasUnsavedChanges)
            .help("Discard every configuration change made since the last Apply.")
            .accessibilityIdentifier("settings.revert")

            Button {
                applyDraft()
            } label: {
                Label("Apply", systemImage: "checkmark")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!hasUnsavedChanges || isApplyingChanges)
            .help("Save and activate all pending configuration changes.")
            .accessibilityIdentifier("settings.apply")
        }
        .controlSize(.regular)
    }
}
