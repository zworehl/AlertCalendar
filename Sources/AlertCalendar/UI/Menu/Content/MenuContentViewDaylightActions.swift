import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    @ViewBuilder
    func contextualDaylightHeader(for item: UpcomingItem) -> some View {
        MenuContentHoverContainer { isHovered in
            contextualDaylightHeaderContent(for: item, isHovered: isHovered)
        }
    }

    @ViewBuilder
    func contextualDaylightHeaderContent(for item: UpcomingItem, isHovered: Bool) -> some View {
        let titleFont = MenuMarkerMetrics.rowTitleFont
        let timeFont = MenuMarkerMetrics.rowDetailFont
        let trailingReservation = contextualDaylightHeaderTrailingReservation(for: item)

        ZStack(alignment: .trailing) {
            HStack(alignment: .center, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    contextualMarkerView(for: item)

                    Text(item.title)
                        .font(titleFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }

                Spacer(minLength: 12)

                Text(timeText(item.date))
                    .font(timeFont)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: trailingReservation, alignment: .trailing)
                    .opacity(isHovered ? 0 : 1)
            }

            // Keep the action subtree in the ZStack in both states so that its
            // native 28-point control height and trailing width are part of the
            // stable hover region before the pointer enters it.
            contextualActionButtons(for: item, locationText: nil)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
                .accessibilityHidden(!isHovered)
                .disabled(!isHovered)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(height: Self.contextualDaylightHeaderHeight, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
        .menuRowHoverBackground(isHovered: isHovered)
        .contentShape(Rectangle())
    }

    func contextualDaylightHeaderTrailingReservation(for item: UpcomingItem) -> CGFloat {
        max(
            contextualActionRowWidth(
                for: item,
                locationText: nil,
                showsJoinButton: false
            ),
            Self.measuredTextWidth(timeText(item.date), font: MenuMarkerMetrics.rowDetailNSFont)
        )
    }

    nonisolated static var contextualDaylightHeaderHeight: CGFloat {
        MenuActionControlMetrics.minimumHitTargetSize + 8
    }

    @ViewBuilder
    func contextualMarkerView(for item: UpcomingItem) -> some View {
        menuMarkerColumn(
            for: item,
            rowMinimumHeight: Self.contextualDaylightHeaderHeight
        )
    }

    @ViewBuilder
    func contextualActionButtons(
        for item: UpcomingItem,
        locationText: String?,
        showsJoinButton: Bool = false
    ) -> some View {
        MenuActionButtonGroup {
            if showsJoinButton,
               item.meetingURL != nil {
                joinActionButton(for: item)
            }
            if shouldShowOpenLinkAction(for: item) {
                openLinkActionButton(for: item)
            }

            if let locationText,
               Self.hasUsableContextualLocation(locationText) {
                mapActionButton(for: item, locationText: locationText)
            }

            skipActionButton(for: item)
        }
    }

    @ViewBuilder
    func contextualDaylightPreview(for item: UpcomingItem, preferredHeight: CGFloat) -> some View {
        DaylightPreviewArtwork(
            latitude: settings.astronomyLatitude,
            longitude: settings.astronomyLongitude,
            date: item.date,
            isEnabled: hasValidAstronomyPreviewCoordinates
        )
        .frame(maxWidth: .infinity)
        .frame(height: preferredHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    var hasValidAstronomyPreviewCoordinates: Bool {
        abs(settings.astronomyLatitude) <= 90 && abs(settings.astronomyLongitude) <= 180
    }
}
