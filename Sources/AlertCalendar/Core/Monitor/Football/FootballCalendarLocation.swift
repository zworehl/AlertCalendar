import EventKit
import CoreLocation
import Foundation

enum FootballCalendarLocation {
    static func resolvedText(reported: String?, existing: String?, structuredTitle: String?) -> String? {
        FootballDataAPIClient.normalizedLocationTextValue(reported)
            ?? FootballDataAPIClient.normalizedLocationTextValue(existing)
            ?? FootballDataAPIClient.normalizedLocationTextValue(structuredTitle)
    }

    static func structuredLocation(
        title: String,
        coordinate: CLLocationCoordinate2D?,
        existing: EKStructuredLocation? = nil
    ) -> EKStructuredLocation {
        // Setting EKEvent.structuredLocation to nil also erases event.location.
        // A title-only location keeps the stadium available while geocoding recovers.
        let location = EKStructuredLocation(title: title)
        if let coordinate {
            location.geoLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        } else if FootballDataAPIClient.normalizedLocationTextValue(existing?.title) == title {
            location.geoLocation = existing?.geoLocation
            location.radius = existing?.radius ?? 0
        }
        return location
    }
}
