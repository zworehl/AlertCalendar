import SwiftUI

struct SlackStatusRulesColumnWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct SlackStatusSyncRuleDropDelegate: DropDelegate {
    let targetRuleID: String
    @Binding var rules: [SlackStatusSyncRule]
    @Binding var draggingRuleID: String?

    func validateDrop(info: DropInfo) -> Bool {
        draggingRuleID != nil
    }

    func dropEntered(info: DropInfo) {
        moveDraggingRuleIfNeeded()
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingRuleID = nil
        return true
    }

    private func moveDraggingRuleIfNeeded() {
        guard let draggingRuleID, draggingRuleID != targetRuleID else { return }
        guard let sourceIndex = rules.firstIndex(where: { $0.id == draggingRuleID }) else { return }
        guard let targetIndex = rules.firstIndex(where: { $0.id == targetRuleID }) else { return }

        withAnimation(.easeInOut(duration: 0.14)) {
            rules.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
    }
}
