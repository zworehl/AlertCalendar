import SwiftUI

extension SettingsView {
    var softwareUpdateSettingsSection: some View {
        settingsSection(
            title: L10n.text("Software Updates"),
            subtitle: L10n.text("Keep AlertCalendar current with signed releases from GitHub."),
            systemImage: "arrow.triangle.2.circlepath"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                settingsControlRow(
                    title: L10n.text("Check automatically"),
                    detail: L10n.text("Checks GitHub periodically without interrupting your calendar or Slack refresh cycle.")
                ) {
                    Toggle(
                        L10n.text("Check automatically"),
                        isOn: Binding(
                            get: { softwareUpdateController.automaticallyChecksForUpdates },
                            set: { isEnabled in
                                softwareUpdateController.setAutomaticallyChecksForUpdates(isEnabled)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(Text(L10n.text("Check automatically for updates")))
                }

                settingsDivider()

                settingsControlRow(
                    title: L10n.text("Download automatically"),
                    detail: L10n.text("Downloads verified updates in the background and asks before relaunching the app.")
                ) {
                    Toggle(
                        L10n.text("Download automatically"),
                        isOn: Binding(
                            get: { softwareUpdateController.automaticallyDownloadsUpdates },
                            set: { isEnabled in
                                softwareUpdateController.setAutomaticallyDownloadsUpdates(isEnabled)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(
                        !softwareUpdateController.automaticallyChecksForUpdates ||
                            !softwareUpdateController.allowsAutomaticUpdates
                    )
                    .accessibilityLabel(Text(L10n.text("Download updates automatically")))
                }

                settingsDivider()

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(softwareUpdateController.displayVersion)
                            .font(.subheadline.weight(.medium))
                        Text(softwareUpdateStatusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button(L10n.text("Check Now")) {
                        softwareUpdateController.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!softwareUpdateController.canCheckForUpdates)
                }
            }
        }
    }

    private var softwareUpdateStatusDescription: String {
        _ = softwareUpdateController.revision
        if let configurationError = softwareUpdateController.configurationError {
            return configurationError
        }
        if let date = softwareUpdateController.lastUpdateCheckDate {
            return L10n.text("Last checked \(date.formatted(date: .abbreviated, time: .shortened)).")
        }
        return L10n.text("No update check has completed yet.")
    }
}
