import SwiftUI

extension SettingsView {
    var softwareUpdateSettingsSection: some View {
        settingsSection(
            title: "Software Updates",
            subtitle: "Keep AlertCalendar current with signed releases from GitHub.",
            systemImage: "arrow.triangle.2.circlepath"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                settingsControlRow(
                    title: "Check automatically",
                    detail: "Checks GitHub periodically without interrupting your calendar or Slack refresh cycle."
                ) {
                    Toggle(
                        "Check automatically",
                        isOn: Binding(
                            get: { softwareUpdateController.automaticallyChecksForUpdates },
                            set: { isEnabled in
                                softwareUpdateController.setAutomaticallyChecksForUpdates(isEnabled)
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(Text("Check automatically for updates"))
                }

                settingsDivider()

                settingsControlRow(
                    title: "Download automatically",
                    detail: "Downloads verified updates in the background and asks before relaunching the app."
                ) {
                    Toggle(
                        "Download automatically",
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
                    .accessibilityLabel(Text("Download updates automatically"))
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

                    Button("Check Now") {
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
            return "Last checked \(date.formatted(date: .abbreviated, time: .shortened))."
        }
        return "No update check has completed yet."
    }
}
