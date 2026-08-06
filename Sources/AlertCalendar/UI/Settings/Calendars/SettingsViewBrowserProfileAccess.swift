import AppKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var browserProfileAccessSettingsSection: some View {
        settingsSection(
            title: "Browser Profile Access",
            subtitle: "Read local browser profile names for per-calendar meeting link routing.",
            systemImage: "person.crop.rectangle.stack"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label(
                        meetingBrowserProfileIssues.isEmpty ? "Profile access is available" : "Profile access needs attention",
                        systemImage: meetingBrowserProfileIssues.isEmpty
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(meetingBrowserProfileIssues.isEmpty ? Color.green : Color.orange)

                    Spacer(minLength: 12)

                    cardStatusBadge(
                        SettingsCardBadgeState(
                            title: meetingBrowserProfileIssues.isEmpty ? "Available" : "Action Required",
                            tint: meetingBrowserProfileIssues.isEmpty ? .green : .orange
                        )
                    )
                }

                if meetingBrowserProfileIssues.isEmpty {
                    Text("AlertCalendar can load the profiles exposed by the installed supported browsers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(meetingBrowserProfileIssues) { issue in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(issue.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .help("\(issue.sourcePath)\n\(issue.technicalDescription)")

                            Spacer(minLength: 8)

                            if issue.reason == .accessDenied {
                                Button {
                                    authorizeBrowserProfileAccess(for: issue)
                                } label: {
                                    Label("Choose \(issue.browser.title) Data", systemImage: "doc.badge.plus")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }

                    Text(browserProfileAccessRecoveryDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let browserProfileAuthorizationErrorMessage {
                    Label(browserProfileAuthorizationErrorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        browserProfileAccessActions
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        browserProfileAccessActions
                    }
                }
            }
        }
    }

    @ViewBuilder
    var browserProfileAccessActions: some View {
        Button {
            refreshMeetingBrowserProfiles()
        } label: {
            Label("Retry Profiles", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)

        if browserProfileAccessWasDenied {
            Button {
                openFullDiskAccessSettings()
            } label: {
                Label("Open Full Disk Access", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
        }
    }

    var browserProfileAccessWasDenied: Bool {
        meetingBrowserProfileIssues.contains { $0.reason == .accessDenied }
    }

    var browserProfileAccessRecoveryDescription: String {
        if browserProfileAccessWasDenied {
            return "If Full Disk Access is already enabled, choose each browser's profile data file once so macOS can record your explicit selection."
        }
        return "Open the affected browser once so it can create its profile data, then retry."
    }

    func authorizeBrowserProfileAccess(for issue: MeetingBrowserProfileLoadIssue) {
        guard let expectedSourceURL = MeetingBrowserProfileStore.expectedSourceURL(for: issue.browser) else {
            browserProfileAuthorizationErrorMessage = "No profile data source is available for \(issue.browser.title)."
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose \(issue.browser.title) Profile Data"
        panel.message = "Select “\(expectedSourceURL.lastPathComponent)” to allow AlertCalendar to read profile names."
        panel.prompt = "Grant Access"
        panel.directoryURL = expectedSourceURL.deletingLastPathComponent()
        panel.nameFieldStringValue = expectedSourceURL.lastPathComponent
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        guard selectedURL.lastPathComponent == expectedSourceURL.lastPathComponent else {
            browserProfileAuthorizationErrorMessage = "Choose “\(expectedSourceURL.lastPathComponent)” for \(issue.browser.title)."
            return
        }

        do {
            try MeetingBrowserProfileAuthorizationStore.authorize(
                selectedURL,
                for: issue.browser
            )
            browserProfileAuthorizationErrorMessage = nil
            refreshMeetingBrowserProfiles()
        } catch {
            browserProfileAuthorizationErrorMessage = "AlertCalendar could not save \(issue.browser.title) access: \(error.localizedDescription)"
        }
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else {
            return
        }
        AlertCalendarWorkspace.open(url)
    }
}
