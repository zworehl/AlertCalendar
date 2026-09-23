import SwiftUI

struct SettingsPendingChangesBanner: View {
    let isApplying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isEmphasized = false

    private var shouldPulse: Bool { !isApplying && !reduceMotion && scenePhase == .active }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isApplying ? "arrow.triangle.2.circlepath" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(isApplying ? "Applying your changes…" : "Your changes are not active yet")
                    .font(.callout.weight(.semibold))
                Text("Choose Apply to save and activate them, or Revert Changes to discard them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(isEmphasized ? 0.22 : 0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(isEmphasized ? 0.65 : 0.3)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.pendingChangesBanner")
        .task(id: shouldPulse) {
            isEmphasized = false
            guard shouldPulse else { return }
            do {
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 1.2)) { isEmphasized = true }
                    try await Task.sleep(for: .seconds(1.2))
                    withAnimation(.easeInOut(duration: 1.2)) { isEmphasized = false }
                    try await Task.sleep(for: .seconds(10.8))
                }
            } catch { isEmphasized = false }
        }
    }
}
