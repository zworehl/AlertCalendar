import Foundation

extension MenuContentView {
    func attendeePreviewMaximumListHeight(
        for item: UpcomingItem,
        snapshot: LayoutSnapshot,
        targetPanelHeight: CGFloat? = nil,
        compactPanelHeight: CGFloat? = nil
    ) -> CGFloat {
        let compactMaximumHeight: CGFloat = snapshot.shouldUseSplitDropdownLayout ? 148 : 188
        guard snapshot.shouldUseSplitDropdownLayout,
              expandableAttendeePreviewKey(snapshot: snapshot) == item.notificationKey else {
            return compactMaximumHeight
        }

        let usesExplicitMeasurements = targetPanelHeight != nil && compactPanelHeight != nil
        let hasCurrentMeasurements = splitContextualPanelMeasurementKey == snapshot.contextualPanelMeasurementKey
            && splitRightColumnHeight > 0
            && splitContextualCompactPanelHeight > 0
        guard usesExplicitMeasurements || hasCurrentMeasurements else {
            return compactMaximumHeight
        }

        return Self.expandedAttendeeListMaximumHeight(
            compactMaximumHeight: compactMaximumHeight,
            targetPanelHeight: targetPanelHeight ?? splitRightColumnHeight,
            compactPanelHeight: compactPanelHeight ?? splitContextualCompactPanelHeight
        )
    }

    func expandableAttendeePreviewKey(snapshot: LayoutSnapshot) -> String? {
        let compactMaximumHeight: CGFloat = snapshot.shouldUseSplitDropdownLayout ? 148 : 188
        return snapshot.displayedContextualActionItems.first { item in
            guard case let .attendees(_, attendees)? = snapshot.contextualPreviewKind(for: item) else {
                return false
            }
            return MeetingAttendeesPreview.attendeeListContentHeight(
                for: attendees.count,
                columnCount: 1
            ) > compactMaximumHeight + 0.5
        }?.notificationKey
    }

    nonisolated static func expandedAttendeeListMaximumHeight(
        compactMaximumHeight: CGFloat,
        targetPanelHeight: CGFloat,
        compactPanelHeight: CGFloat
    ) -> CGFloat {
        compactMaximumHeight + max(0, targetPanelHeight - compactPanelHeight)
    }
}
