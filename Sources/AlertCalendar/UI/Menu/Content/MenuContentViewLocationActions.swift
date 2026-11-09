import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    func meetingServiceName(for url: URL) -> String {
        MeetingService.resolve(from: url).title
    }

    @ViewBuilder
    func linkDetailRow(
        for item: UpcomingItem,
        detailFont: Font,
        accentColor: Color,
        detailTextColor: Color,
        isHovered: Bool
    ) -> some View {
        if let meetingURL = item.meetingURL {
            let service = MeetingService.resolve(from: meetingURL)
            HStack(alignment: .center, spacing: 4) {
                MeetingServiceIconView(
                    service: service,
                    size: MenuMarkerMetrics.symbolSize,
                    fallbackColor: accentColor,
                    isHovered: isHovered
                )
                Text(service.title)
                    .font(detailFont)
                    .foregroundStyle(detailTextColor)
            }
        }
    }

    func mapURL(for locationText: String) -> URL? {
        guard let encoded = locationText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }

    func preciseMapURL(for coordinate: ResolvedLocationCoordinate, label: String) -> URL? {
        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(
                name: "ll",
                value: String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
            ),
            URLQueryItem(name: "q", value: label),
        ]
        return components?.url
    }

    func openMap(for item: UpcomingItem, locationText: String) {
        let label: String
        if let footballMatch = item.footballMatch {
            label = footballContextualVenueName(for: item, match: footballMatch)
                ?? displayLocationName(from: locationText)
        } else {
            label = displayLocationName(from: locationText)
        }

        Task {
            if let coordinate = await LocationCoordinateResolver.shared.coordinate(
                for: locationText,
                preferring: item.locationCoordinate
            ),
               let preciseURL = preciseMapURL(for: coordinate, label: label) {
                _ = await MainActor.run {
                    AlertCalendarWorkspace.open(preciseURL)
                }
                return
            }

            if let fallbackURL = mapURL(for: locationText) {
                _ = await MainActor.run {
                    AlertCalendarWorkspace.open(fallbackURL)
                }
            }
        }
    }

    func shouldShowPhysicalMap(for item: UpcomingItem, locationText: String?) -> Bool {
        guard item.meetingURL == nil else { return false }
        guard let locationText else { return false }
        return !monitor.isVirtualLocationText(locationText)
    }

    func shouldShowOpenLinkAction(for item: UpcomingItem) -> Bool {
        Self.hasOpenLinkAction(for: item)
    }

    nonisolated static func hasOpenLinkAction(for item: UpcomingItem) -> Bool {
        item.openLinkURL != nil && item.meetingURL == nil
    }

    func locationTextForMenuBarItem(_ item: UpcomingItem) -> String? {
        if let locationText = item.locationText {
            if monitor.isVirtualLocationText(locationText)
                || !Self.hasUsableContextualLocation(locationText) {
                return nil
            }
            return locationText
        }
        return nil
    }
}
