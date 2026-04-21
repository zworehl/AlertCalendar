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
    private static let venueQualifierPrefixes = [
        "Estadio",
        "Stade",
        "Stadio",
    ]
    private static let venueQualifierSuffixes = [
        "Stadium",
        "Arena",
        "Ground",
    ]
    private static let venueDescriptorTokens = [
        "arena",
        "autodromo",
        "ballpark",
        "centre",
        "center",
        "circuit",
        "coliseo",
        "coliseum",
        "court",
        "dome",
        "estadio",
        "field",
        "ground",
        "park",
        "stadion",
        "stadium",
        "stade",
        "stadio",
        "track",
        "velodrome",
    ]

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

        let queries = Self.searchQueries(from: rawText)
        guard !queries.isEmpty else {
            cache[cacheKey] = .notFound
            return nil
        }

        if let parsed = queries.compactMap(Self.parseCoordinatePair).first {
            cache[cacheKey] = .found(parsed)
            return parsed
        }

        for query in queries {
            // Stadiums and venues behave more like POIs than postal addresses, so let Maps search first.
            if let coordinate = await Self.localSearchCoordinate(for: query) {
                cache[cacheKey] = .found(coordinate)
                return coordinate
            }

            if let coordinate = await Self.geocodeCoordinate(for: query) {
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
                guard let mapItem = bestLocalSearchMatch(for: query, mapItems: response?.mapItems ?? []),
                      let coordinate = mapItem.placemark.location?.coordinate else {
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

    private static func bestLocalSearchMatch(for query: String, mapItems: [MKMapItem]) -> MKMapItem? {
        guard !mapItems.isEmpty else { return nil }

        let queryComponents = query
            .split(separator: ",")
            .map { normalizedSearchText(String($0)) }
            .filter { !$0.isEmpty }

        guard !queryComponents.isEmpty else { return mapItems.first }

        let ranked = mapItems.enumerated().map { index, item in
            (
                index: index,
                item: item,
                score: localSearchScore(for: item, queryComponents: queryComponents)
            )
        }

        return ranked.max { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.index > rhs.index
            }
            return lhs.score < rhs.score
        }?.item
    }

    private static func localSearchScore(for mapItem: MKMapItem, queryComponents: [String]) -> Int {
        let placemark = mapItem.placemark
        let fields = [
            mapItem.name,
            placemark.name,
            placemark.title,
            placemark.locality,
            placemark.subLocality,
            placemark.administrativeArea,
            placemark.country,
        ]
            .compactMap { $0 }
            .map(normalizedSearchText)
            .filter { !$0.isEmpty }

        let fieldTokens = Set(fields.flatMap(searchTokens))
        let venueQuery = queryComponents.first ?? ""
        let contextQueries = Array(queryComponents.dropFirst())
        var score = 0

        if !venueQuery.isEmpty {
            if fields.contains(where: { $0 == venueQuery }) {
                score += 22
            } else if fields.contains(where: { $0.contains(venueQuery) || venueQuery.contains($0) }) {
                score += 16
            } else {
                score += Set(searchTokens(venueQuery)).intersection(fieldTokens).count * 3
            }
        }

        for contextQuery in contextQueries {
            if fields.contains(where: { $0 == contextQuery }) {
                score += 10
            } else if fields.contains(where: { $0.contains(contextQuery) || contextQuery.contains($0) }) {
                score += 6
            } else {
                score += Set(searchTokens(contextQuery)).intersection(fieldTokens).count * 2
            }
        }

        if let country = placemark.country, !country.isEmpty,
           let countryQuery = contextQueries.last, !countryQuery.isEmpty {
            let normalizedCountry = normalizedSearchText(country)
            if normalizedCountry == countryQuery || normalizedCountry.contains(countryQuery) {
                score += 8
            }
        }

        return score
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    private static func searchTokens(_ value: String) -> [String] {
        normalizedSearchText(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
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

    static func searchQueries(from rawText: String) -> [String] {
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

        let commaSeparatedParts = cleaned
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let trailingContext = commaSeparatedParts.dropFirst().joined(separator: ", ")

        if let first = commaSeparatedParts.first {
            let strippedFirst = strippingParentheticalAliases(from: first)
            let aliases = parentheticalAliases(in: first)
            let venueCandidates = [strippedFirst, first] + aliases

            for venueCandidate in venueCandidates {
                for variant in venueQualifiedQueries(
                    for: venueCandidate,
                    trailingContext: trailingContext
                ) {
                    appendIfNeeded(variant)
                }
            }
        }

        appendIfNeeded(cleaned)

        if commaSeparatedParts.count >= 2 {
            appendIfNeeded(commaSeparatedParts.suffix(3).joined(separator: ", "))
        }

        if let first = commaSeparatedParts.first {
            let strippedFirst = strippingParentheticalAliases(from: first)
            let aliases = parentheticalAliases(in: first)
            for alias in aliases {
                if !trailingContext.isEmpty {
                    appendIfNeeded("\(alias), \(trailingContext)")
                }
                appendIfNeeded(alias)
            }

            if !trailingContext.isEmpty {
                appendIfNeeded("\(strippedFirst), \(trailingContext)")
            }

            appendIfNeeded(strippedFirst)
            appendIfNeeded(first)
        }

        return queries
    }

    private static func venueQualifiedQueries(for venueName: String, trailingContext: String) -> [String] {
        let trimmedVenueName = venueName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVenueName.isEmpty else { return [] }

        let contextSuffix = trailingContext.isEmpty ? "" : ", \(trailingContext)"
        var variants: [String] = []
        let normalizedVenueName = normalizedSearchText(trimmedVenueName)
        let tokens = Set(searchTokens(normalizedVenueName))
        let startsWithKnownQualifier = venueQualifierPrefixes.contains { prefix in
            normalizedVenueName.hasPrefix(normalizedSearchText(prefix) + " ")
        }
        let hasVenueDescriptor = tokens.contains { venueDescriptorTokens.contains($0) }

        if !hasVenueDescriptor {
            for suffix in venueQualifierSuffixes {
                variants.append("\(trimmedVenueName) \(suffix)\(contextSuffix)")
            }
        }

        if !startsWithKnownQualifier {
            let shouldExpandWithPrefixes = !hasVenueDescriptor || tokens.contains("arena")
            if shouldExpandWithPrefixes {
                for prefix in venueQualifierPrefixes {
                    variants.append("\(prefix) \(trimmedVenueName)\(contextSuffix)")
                }
            }
        }

        return variants
    }

    private static func looksLikeQualifiedVenueName(_ venueName: String) -> Bool {
        let normalized = venueName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let tokens = normalized
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)

        return tokens.contains { venueDescriptorTokens.contains($0) }
    }

    private static func parentheticalAliases(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\(([^()]+)\)"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        return matches.compactMap { match in
            guard let aliasRange = Range(match.range(at: 1), in: text) else { return nil }
            let alias = text[aliasRange].trimmingCharacters(in: .whitespacesAndNewlines)
            return alias.isEmpty ? nil : alias
        }
    }

    private static func strippingParentheticalAliases(from text: String) -> String {
        let stripped = text.replacingOccurrences(
            of: #"\s*\([^()]+\)"#,
            with: "",
            options: .regularExpression
        )

        return stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
