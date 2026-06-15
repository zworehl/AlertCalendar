import CoreLocation
import MapKit
import Foundation

struct ResolvedLocationCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ResolvedLocation: Equatable, Sendable {
    let coordinate: ResolvedLocationCoordinate
    let timeZoneIdentifier: String?
}

actor LocationCoordinateResolver {
    static let shared = LocationCoordinateResolver()

    private enum ResolutionMode: String, Sendable {
        case coordinate
        case timeZone

        var allowsLooseFallbacks: Bool {
            self == .timeZone
        }
    }

    private enum CacheEntry: Sendable {
        case found(ResolvedLocation)
        case notFound
    }

    private var cache: [String: CacheEntry] = [:]

    func coordinate(for rawText: String) async -> ResolvedLocationCoordinate? {
        await location(for: rawText, mode: .coordinate)?.coordinate
    }

    func timeZone(for rawText: String) async -> TimeZone? {
        guard let identifier = await location(for: rawText, mode: .timeZone)?.timeZoneIdentifier else { return nil }
        return TimeZone(identifier: identifier)
    }

    private func location(for rawText: String, mode: ResolutionMode) async -> ResolvedLocation? {
        let normalizedCacheText = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .autoupdatingCurrent)
        let cacheKey = "\(mode.rawValue)|\(normalizedCacheText)"

        guard !normalizedCacheText.isEmpty else { return nil }

        if let cached = cache[cacheKey] {
            switch cached {
            case .found(let location):
                return location
            case .notFound:
                return nil
            }
        }

        if let knownLocation = Self.knownLocation(for: rawText) {
            cache[cacheKey] = .found(knownLocation)
            return knownLocation
        }

        let queries = Self.searchQueries(
            from: rawText,
            allowsLooseFallbacks: mode.allowsLooseFallbacks
        )
        guard !queries.isEmpty else {
            cache[cacheKey] = .notFound
            return nil
        }

        if let parsed = queries.compactMap(Self.parseCoordinatePair).first {
            let location = ResolvedLocation(coordinate: parsed, timeZoneIdentifier: nil)
            cache[cacheKey] = .found(location)
            return location
        }

        for query in queries {
            // Stadiums and venues behave more like POIs than postal addresses, so let Maps search first.
            if let location = await Self.localSearchLocation(for: query) {
                if location.timeZoneIdentifier != nil {
                    cache[cacheKey] = .found(location)
                    return location
                }

                if let geocodedLocation = await Self.geocodeLocation(for: query),
                   let timeZoneIdentifier = geocodedLocation.timeZoneIdentifier {
                    let locationWithTimeZone = ResolvedLocation(
                        coordinate: location.coordinate,
                        timeZoneIdentifier: timeZoneIdentifier
                    )
                    cache[cacheKey] = .found(locationWithTimeZone)
                    return locationWithTimeZone
                }

                cache[cacheKey] = .found(location)
                return location
            }

            if let location = await Self.geocodeLocation(for: query) {
                cache[cacheKey] = .found(location)
                return location
            }
        }

        cache[cacheKey] = .notFound
        return nil
    }

    private static func geocodeLocation(for query: String) async -> ResolvedLocation? {
        await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(query) { placemarks, _ in
                guard let placemarks,
                      let placemark = bestGeocodedLocationMatch(for: query, placemarks: placemarks),
                      let coordinate = placemark.location?.coordinate else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: ResolvedLocation(
                        coordinate: ResolvedLocationCoordinate(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        ),
                        timeZoneIdentifier: placemark.timeZone?.identifier
                    )
                )
            }
        }
    }

    private static func localSearchLocation(for query: String) async -> ResolvedLocation? {
        await withCheckedContinuation { continuation in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest]
            MKLocalSearch(request: request).start { response, _ in
                guard let mapItem = bestLocalSearchMatch(for: query, mapItems: response?.mapItems ?? []),
                      let coordinate = mapItem.placemark.location?.coordinate else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: ResolvedLocation(
                        coordinate: ResolvedLocationCoordinate(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        ),
                        timeZoneIdentifier: mapItem.timeZone?.identifier
                    )
                )
            }
        }
    }
}
