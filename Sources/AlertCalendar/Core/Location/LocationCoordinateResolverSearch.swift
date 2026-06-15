import CoreLocation
import Foundation
import MapKit

extension LocationCoordinateResolver {
    private static let minimumSearchConfidenceScore = 12
    private static let minimumFirstComponentScoreWithContext = 3

    private struct LocationSearchScore: Equatable, Sendable {
        let total: Int
        let firstComponentScore: Int
        let matchedContextCount: Int
        let countryScore: Int
    }

    static func bestGeocodedLocationMatch(
        for query: String,
        placemarks: [CLPlacemark]
    ) -> CLPlacemark? {
        let queryComponents = searchQueryComponents(from: query)
        guard !queryComponents.isEmpty else { return placemarks.first }

        let ranked = placemarks.enumerated().map { index, placemark in
            (
                index: index,
                placemark: placemark,
                score: locationSearchScore(
                    candidateFields: candidateFields(for: placemark),
                    queryComponents: queryComponents
                )
            )
        }

        guard let best = ranked.max(by: rankedGeocodeCandidateSort) else { return nil }
        guard isConfidentSearchScore(best.score, queryComponents: queryComponents) else { return nil }
        return best.placemark
    }

    static func bestLocalSearchMatch(for query: String, mapItems: [MKMapItem]) -> MKMapItem? {
        guard !mapItems.isEmpty else { return nil }

        let queryComponents = searchQueryComponents(from: query)

        guard !queryComponents.isEmpty else { return mapItems.first }

        let ranked = mapItems.enumerated().map { index, item in
            (
                index: index,
                item: item,
                score: locationSearchScore(
                    candidateFields: candidateFields(for: item),
                    queryComponents: queryComponents
                )
            )
        }

        guard let best = ranked.max(by: rankedLocalSearchCandidateSort) else { return nil }
        guard isConfidentSearchScore(best.score, queryComponents: queryComponents) else { return nil }
        return best.item
    }

    static func isConfidentSearchMatch(query: String, candidateFields: [String]) -> Bool {
        let queryComponents = searchQueryComponents(from: query)
        guard !queryComponents.isEmpty else { return false }
        let score = locationSearchScore(
            candidateFields: candidateFields,
            queryComponents: queryComponents
        )
        return isConfidentSearchScore(score, queryComponents: queryComponents)
    }

    private static func locationSearchScore(
        candidateFields rawCandidateFields: [String],
        queryComponents: [String]
    ) -> LocationSearchScore {
        let fields = rawCandidateFields
            .map(normalizedSearchText)
            .filter { !$0.isEmpty }
        let fieldTokens = Set(fields.flatMap(searchTokens))
        let firstQuery = queryComponents.first ?? ""
        let contextQueries = Array(queryComponents.dropFirst())
        var total = 0
        var firstComponentScore = 0
        var matchedContextCount = 0
        var countryScore = 0

        if !firstQuery.isEmpty {
            firstComponentScore = componentMatchScore(
                for: firstQuery,
                fields: fields,
                fieldTokens: fieldTokens,
                exactScore: 22,
                containsScore: 16,
                tokenScore: 3
            )
            total += firstComponentScore
        }

        for contextQuery in contextQueries {
            let contextScore: Int
            if contextQuery == contextQueries.last {
                contextScore = countryMatchScore(
                    for: contextQuery,
                    fields: fields
                )
            } else {
                contextScore = componentMatchScore(
                    for: contextQuery,
                    fields: fields,
                    fieldTokens: fieldTokens,
                    exactScore: 10,
                    containsScore: 6,
                    tokenScore: 2
                )
            }
            total += contextScore
            if contextScore > 0 {
                matchedContextCount += 1
            }
            if contextQuery == contextQueries.last {
                countryScore = contextScore
            }
        }

        return LocationSearchScore(
            total: total,
            firstComponentScore: firstComponentScore,
            matchedContextCount: matchedContextCount,
            countryScore: countryScore
        )
    }

    private static func componentMatchScore(
        for query: String,
        fields: [String],
        fieldTokens: Set<String>,
        exactScore: Int,
        containsScore: Int,
        tokenScore: Int
    ) -> Int {
        if fields.contains(where: { $0 == query }) {
            return exactScore
        }
        if fields.contains(where: { $0.contains(query) || query.contains($0) }) {
            return containsScore
        }

        return Set(searchTokens(query)).intersection(fieldTokens).count * tokenScore
    }

    private static func countryMatchScore(
        for query: String,
        fields: [String]
    ) -> Int {
        let queryCountry = normalizedCountrySearchKey(query)
        if fields.contains(where: { normalizedCountrySearchKey($0) == queryCountry }) {
            return 10
        }

        return 0
    }

    private static func isConfidentSearchScore(
        _ score: LocationSearchScore,
        queryComponents: [String]
    ) -> Bool {
        guard score.total >= minimumSearchConfidenceScore else { return false }
        guard queryComponents.count > 1 else { return score.firstComponentScore > 0 }
        if queryComponents.count >= 3, score.countryScore <= 0 {
            return false
        }

        return score.firstComponentScore >= minimumFirstComponentScoreWithContext
            && score.matchedContextCount > 0
    }

    private static func rankedLocalSearchCandidateSort(
        _ lhs: (index: Int, item: MKMapItem, score: LocationSearchScore),
        _ rhs: (index: Int, item: MKMapItem, score: LocationSearchScore)
    ) -> Bool {
        if lhs.score.total == rhs.score.total {
            return lhs.index > rhs.index
        }
        return lhs.score.total < rhs.score.total
    }

    private static func rankedGeocodeCandidateSort(
        _ lhs: (index: Int, placemark: CLPlacemark, score: LocationSearchScore),
        _ rhs: (index: Int, placemark: CLPlacemark, score: LocationSearchScore)
    ) -> Bool {
        if lhs.score.total == rhs.score.total {
            return lhs.index > rhs.index
        }
        return lhs.score.total < rhs.score.total
    }

    private static func candidateFields(for mapItem: MKMapItem) -> [String] {
        let placemark = mapItem.placemark
        return [
            mapItem.name,
            placemark.name,
            placemark.title,
            placemark.locality,
            placemark.subLocality,
            placemark.administrativeArea,
            placemark.country,
        ].compactMap { $0 }
    }

    private static func candidateFields(for placemark: CLPlacemark) -> [String] {
        [
            placemark.name,
            placemark.thoroughfare,
            placemark.subThoroughfare,
            placemark.locality,
            placemark.subLocality,
            placemark.administrativeArea,
            placemark.country,
        ]
            .compactMap { $0 }
            + (placemark.areasOfInterest ?? [])
    }

    static func searchQueryComponents(from query: String) -> [String] {
        query
            .split(separator: ",")
            .map { normalizedSearchText(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    private static func normalizedCountrySearchKey(_ value: String) -> String {
        let normalized = normalizedSearchText(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .joined(separator: " ")

        switch normalized {
        case "us", "u s", "usa", "u s a", "united states", "united states of america":
            return "united states"
        case "uk", "u k", "great britain", "britain", "england", "scotland", "wales":
            return "united kingdom"
        default:
            return normalized
        }
    }

    static func searchTokens(_ value: String) -> [String] {
        normalizedSearchText(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    static func parseCoordinatePair(from text: String) -> ResolvedLocationCoordinate? {
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
}
