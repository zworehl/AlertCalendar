import SwiftUI

extension SettingsView {
    var dataRefreshIssuesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Persistent update problems trigger a notification after 5 minutes, then at most once an hour until recovery. Notifications follow macOS notification settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if dataRefreshIssues.isEmpty {
                Label("No unresolved update problems", systemImage: "checkmark.circle")
                    .font(.callout)
            }
            ForEach(dataRefreshIssues) { issue in
                VStack(alignment: .leading, spacing: 4) {
                    Label(issue.title, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(issue.detail).font(.caption).textSelection(.enabled)
                    Text("Last failed attempt: \(issue.lastFailedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
