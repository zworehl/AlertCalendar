import AppKit
import CoreLocation
import MapKit
import SwiftUI

extension MenuContentView {
    func meetingServiceName(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        let scheme = (url.scheme ?? "").lowercased()
        let absolute = url.absoluteString.lowercased()

        if host.contains("meet.google.") {
            return "Meet"
        }
        if host.contains("zoom.") || host.contains("us02web.zoom.") {
            return "Zoom"
        }
        if scheme == "msteams"
            || scheme == "microsoftteams"
            || host.contains("teams.")
            || host.contains("teams.microsoft.")
            || host.contains("teams.live.")
            || host.contains("teams.office.")
            || host.contains("aka.ms")
            || host.contains("microsoftteams.")
            || host.contains("teams.ms")
            || absolute.contains("meetup-join")
            || absolute.contains("teams.microsoft.com")
            || absolute.contains("teams.live.com")
            || absolute.contains("teams.office.com") {
            return "Microsoft Teams"
        }
        if host.contains("webex.") {
            return "Webex"
        }
        if host.contains("whereby.") {
            return "Whereby"
        }
        if host.contains("jitsi.") || host.contains("meet.jit.si") {
            return "Jitsi"
        }
        if host.contains("chime.aws") || host.contains("amazonchime.") {
            return "Amazon Chime"
        }

        return "Meeting Link"
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

    func locationTextForMenuBarItem(_ item: UpcomingItem) -> String? {
        if let locationText = item.locationText {
            if monitor.isVirtualLocationText(locationText) {
                return nil
            }
            return locationText
        }
        return nil
    }
}
