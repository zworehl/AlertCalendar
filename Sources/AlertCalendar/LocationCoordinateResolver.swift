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

actor LocationCoordinateResolver {
    static let shared = LocationCoordinateResolver()

    private enum CacheEntry: Sendable {
        case found(ResolvedLocationCoordinate)
        case notFound
    }

    private var cache: [String: CacheEntry] = [:]

    func coordinate(for rawText: String) async -> ResolvedLocationCoordinate? {
        let cacheKey = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .autoupdatingCurrent)

        guard !cacheKey.isEmpty else { return nil }

        if let cached = cache[cacheKey] {
            switch cached {
            case .found(let coordinate):
                return coordinate
            case .notFound:
                return nil
            }
        }

        let queries = Self.locationQueries(from: rawText)
        guard !queries.isEmpty else {
            cache[cacheKey] = .notFound
            return nil
        }

        if let parsed = queries.compactMap(Self.parseCoordinatePair).first {
            cache[cacheKey] = .found(parsed)
            return parsed
        }

        for query in queries {
            if let coordinate = await Self.geocodeCoordinate(for: query) {
                cache[cacheKey] = .found(coordinate)
                return coordinate
            }

            if let coordinate = await Self.localSearchCoordinate(for: query) {
                cache[cacheKey] = .found(coordinate)
                return coordinate
            }
        }

        cache[cacheKey] = .notFound
        return nil
    }

    private static func geocodeCoordinate(for query: String) async -> ResolvedLocationCoordinate? {
        await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(query) { placemarks, _ in
                guard let coordinate = placemarks?.first?.location?.coordinate else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: ResolvedLocationCoordinate(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )
                )
            }
        }
    }

    private static func localSearchCoordinate(for query: String) async -> ResolvedLocationCoordinate? {
        await withCheckedContinuation { continuation in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest]
            MKLocalSearch(request: request).start { response, _ in
                guard let coordinate = response?.mapItems.first?.placemark.coordinate else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: ResolvedLocationCoordinate(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    )
                )
            }
        }
    }

    private static func parseCoordinatePair(from text: String) -> ResolvedLocationCoordinate? {
        let pattern = #"(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let latRange = Range(match.range(at: 1), in: text),
              let lonRange = Range(match.range(at: 2), in: text),
              let lat = Double(text[latRange]),
              let lon = Double(text[lonRange]),
              (-90 ... 90).contains(lat),
              (-180 ... 180).contains(lon) else {
            return nil
        }

        return ResolvedLocationCoordinate(latitude: lat, longitude: lon)
    }

    private static func locationQueries(from rawText: String) -> [String] {
        let textWithoutLinks = rawText.replacingOccurrences(
            of: #"https?://\S+"#,
            with: "",
            options: .regularExpression
        )
        let cleaned = textWithoutLinks
            .replacingOccurrences(of: "\n", with: ", ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return [] }

        var queries: [String] = []

        func appendIfNeeded(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            guard !queries.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
            queries.append(trimmed)
        }

        appendIfNeeded(cleaned)

        let commaSeparatedParts = cleaned
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if commaSeparatedParts.count >= 2 {
            appendIfNeeded(commaSeparatedParts.suffix(3).joined(separator: ", "))
        }

        if let first = commaSeparatedParts.first {
            appendIfNeeded(first)
        }

        return queries
    }
}
