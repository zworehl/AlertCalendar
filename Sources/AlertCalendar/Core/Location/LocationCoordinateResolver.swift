import CoreLocation
import MapKit
import Foundation

struct ResolvedLocationCoordinate: Equatable, Hashable, Sendable {
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
    private static let lookupTimeout: TimeInterval = 6

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

    private enum LookupResult: Sendable {
        case found(ResolvedLocation)
        case notFound
        case timedOut
    }

    private var cache = AlertCalendarLRUCache<String, CacheEntry>(capacity: 256)

    func coordinate(for rawText: String) async -> ResolvedLocationCoordinate? {
        await location(for: rawText, mode: .coordinate)?.coordinate
    }

    func coordinate(
        for rawText: String,
        preferring preferredCoordinate: ResolvedLocationCoordinate?
    ) async -> ResolvedLocationCoordinate? {
        if let preferredCoordinate {
            return preferredCoordinate
        }

        return await coordinate(for: rawText)
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

        if let cached = cache.value(forKey: cacheKey) {
            switch cached {
            case .found(let location):
                return location
            case .notFound:
                return nil
            }
        }

        if let knownLocation = Self.knownLocation(for: rawText) {
            cache.insert(.found(knownLocation), forKey: cacheKey)
            return knownLocation
        }

        let queries = Self.searchQueries(
            from: rawText,
            allowsLooseFallbacks: mode.allowsLooseFallbacks
        )
        guard !queries.isEmpty else {
            cache.insert(.notFound, forKey: cacheKey)
            return nil
        }

        if let parsed = queries.compactMap(Self.parseCoordinatePair).first {
            let location = ResolvedLocation(coordinate: parsed, timeZoneIdentifier: nil)
            cache.insert(.found(location), forKey: cacheKey)
            return location
        }

        for query in queries {
            // Stadiums and venues behave more like POIs than postal addresses, so let Maps search first.
            switch await Self.localSearchLocation(for: query) {
            case .found(let location):
                if location.timeZoneIdentifier != nil {
                    cache.insert(.found(location), forKey: cacheKey)
                    return location
                }

                switch await Self.geocodeLocation(for: query) {
                case .found(let geocodedLocation) where geocodedLocation.timeZoneIdentifier != nil:
                    let locationWithTimeZone = ResolvedLocation(
                        coordinate: location.coordinate,
                        timeZoneIdentifier: geocodedLocation.timeZoneIdentifier
                    )
                    cache.insert(.found(locationWithTimeZone), forKey: cacheKey)
                    return locationWithTimeZone
                case .timedOut:
                    return location
                case .found, .notFound:
                    break
                }

                cache.insert(.found(location), forKey: cacheKey)
                return location
            case .timedOut:
                return nil
            case .notFound:
                break
            }

            switch await Self.geocodeLocation(for: query) {
            case .found(let location):
                cache.insert(.found(location), forKey: cacheKey)
                return location
            case .timedOut:
                return nil
            case .notFound:
                break
            }
        }

        cache.insert(.notFound, forKey: cacheKey)
        return nil
    }

    private static func geocodeLocation(for query: String) async -> LookupResult {
        await withCheckedContinuation { continuation in
            let box = LocationLookupContinuationBox(continuation)
            let geocoder = CLGeocoder()
            let timeoutWorkItem = DispatchWorkItem {
                geocoder.cancelGeocode()
                box.resume(returning: .timedOut)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + lookupTimeout, execute: timeoutWorkItem)

            geocoder.geocodeAddressString(query) { placemarks, _ in
                guard let placemarks,
                      let placemark = bestGeocodedLocationMatch(for: query, placemarks: placemarks),
                      let coordinate = placemark.location?.coordinate else {
                    box.resume(returning: .notFound)
                    return
                }

                box.resume(
                    returning: .found(ResolvedLocation(
                        coordinate: ResolvedLocationCoordinate(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        ),
                        timeZoneIdentifier: placemark.timeZone?.identifier
                    ))
                )
            }
        }
    }

    private static func localSearchLocation(for query: String) async -> LookupResult {
        await withCheckedContinuation { continuation in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest]
            let search = MKLocalSearch(request: request)
            let box = LocationLookupContinuationBox(continuation)
            let timeoutWorkItem = DispatchWorkItem {
                search.cancel()
                box.resume(returning: .timedOut)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + lookupTimeout, execute: timeoutWorkItem)

            search.start { response, _ in
                guard let mapItem = bestLocalSearchMatch(for: query, mapItems: response?.mapItems ?? []),
                      let coordinate = mapItem.placemark.location?.coordinate else {
                    box.resume(returning: .notFound)
                    return
                }

                box.resume(
                    returning: .found(ResolvedLocation(
                        coordinate: ResolvedLocationCoordinate(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        ),
                        timeZoneIdentifier: mapItem.timeZone?.identifier
                    ))
                )
            }
        }
    }
}

private final class LocationLookupContinuationBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: sending Value) {
        let continuationToResume: CheckedContinuation<Value, Never>?
        lock.lock()
        continuationToResume = continuation
        continuation = nil
        lock.unlock()
        continuationToResume?.resume(returning: value)
    }
}
