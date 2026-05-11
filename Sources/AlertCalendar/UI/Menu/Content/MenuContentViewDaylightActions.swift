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
        let accentColor = Color(nsColor: item.calendarColor)
        let titleFont = Font.system(size: 12, weight: .semibold)
        let timeFont = Font.system(size: 11, weight: .medium)

        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                contextualMarkerView(for: item, accentColor: accentColor)

                Text(item.title)
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            Spacer(minLength: 12)

            if isHovered {
                contextualActionButtons(for: item, locationText: nil)
            } else {
                Text(timeText(item.date))
                    .font(timeFont)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func contextualMarkerView(for item: UpcomingItem, accentColor: Color) -> some View {
        if let markerSymbol = markerSymbolName(for: item) {
            Image(systemName: markerSymbol)
                .font(.system(size: 12, weight: .regular))
                .frame(width: 12, height: 12)
                .foregroundStyle(accentColor)
        } else if let image = markerImage(for: item) {
            let markerSize = markerImageSize(for: item)
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: markerSize.width, height: markerSize.height)
        } else {
            Capsule()
                .fill(accentColor)
                .frame(width: 4, height: 14)
        }
    }

    @ViewBuilder
    func contextualActionButtons(
        for item: UpcomingItem,
        locationText: String?,
        showsJoinButton: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            if showsJoinButton,
               let meetingURL = item.meetingURL {
                joinActionButton(for: meetingURL)
            }

            skipActionButton(for: item)

            if let locationText {
                mapActionButton(for: item, locationText: locationText)
            }
        }
    }

    @ViewBuilder
    func contextualDaylightPreview(for item: UpcomingItem, preferredHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Daylight Map")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

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
    }

    var hasValidAstronomyPreviewCoordinates: Bool {
        abs(settings.astronomyLatitude) <= 90 && abs(settings.astronomyLongitude) <= 180
    }
}
