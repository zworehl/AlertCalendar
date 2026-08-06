import SwiftUI

extension SettingsView {
    var settingsActionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

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
            Text(hasUnsavedChanges ? "Changes not applied" : "Settings are up to date")
        } icon: {
            Image(systemName: hasUnsavedChanges ? "circle.fill" : "checkmark.circle")
                .font(hasUnsavedChanges ? .system(size: 7, weight: .bold) : .caption)
        }
        .font(.caption)
        .foregroundStyle(hasUnsavedChanges ? Color.orange : Color.secondary)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier("settings.changeStatus")
    }

    private var refreshSettingsButton: some View {
        Button {
            monitor.refreshNow(reason: .manual)
        } label: {
            Label("Refresh Now", systemImage: "arrow.clockwise")
        }
        .help("Refresh calendars and external feeds without applying pending configuration changes.")
        .accessibilityIdentifier("settings.refresh")
    }

    private var settingsActionButtons: some View {
        HStack(spacing: 8) {
            Button("Revert Changes") {
                resetDraft()
            }
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
            .disabled(!hasUnsavedChanges)
            .help("Save and activate all pending configuration changes.")
            .accessibilityIdentifier("settings.apply")
        }
    }
}
