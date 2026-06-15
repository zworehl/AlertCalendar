import Foundation

extension FootballDataAPIClient {
    static func venueLocationText(from competition: [String: Any]) -> String? {
        venueLocationText(fromVenue: competition["venue"] as? [String: Any])
    }

    static func summaryVenueLocationText(from root: [String: Any], competition: [String: Any]) -> String? {
        let headerVenue = venueLocationText(from: competition)
        let gameInfoVenue = venueLocationText(
            fromVenue: ((root["gameInfo"] as? [String: Any])?["venue"] as? [String: Any])
        )

        return bestAvailableLocationText(
            reportedLocationText: gameInfoVenue,
            fallbackLocationText: headerVenue
        )
    }

    static func bestAvailableLocationText(
        reportedLocationText: String?,
        fallbackLocationText: String?
    ) -> String? {
        let normalizedReported = normalizedLocationTextValue(reportedLocationText)
        let normalizedFallback = normalizedLocationTextValue(fallbackLocationText)

        switch (normalizedReported, normalizedFallback) {
        case let (reported?, fallback?):
            if reported.caseInsensitiveCompare(fallback) == .orderedSame {
                return reported
            }
            return locationTextSpecificityScore(reported) >= locationTextSpecificityScore(fallback)
                ? reported
                : fallback
        case let (reported?, nil):
            return reported
        case let (nil, fallback?):
            return fallback
        case (nil, nil):
            return nil
        }
    }

    static func venueLocationText(fromVenue venue: [String: Any]?) -> String? {
        let address = venue?["address"] as? [String: Any]
        let rawVenueName = stringValue(venue?["fullName"])

        // ESPN sometimes marks unknown venues as TBD/TBC while still attaching loose address data.
        // In those cases we prefer leaving the event location empty rather than storing a misleading placeholder.
        if let rawVenueName, isPlaceholderLocationText(rawVenueName) {
            return nil
        }

        let candidates = [
            rawVenueName,
            stringValue(address?["city"]),
            stringValue(address?["state"]),
            stringValue(address?["country"]),
        ]

        var components: [String] = []
        var seen = Set<String>()
        for candidate in candidates.compactMap(normalizedLocationTextValue) {
            let normalized = candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard seen.insert(normalized).inserted else { continue }
            components.append(candidate)
        }

        guard !components.isEmpty else { return nil }
        let fallbackLocationText = components.joined(separator: ", ")
        return FootballVenueCanonicalizer.locationText(
            from: venue,
            fallbackLocationText: fallbackLocationText
        )
    }

    static func normalizedLocationTextValue(_ rawValue: String?) -> String? {
        guard let trimmed = AlertCalendarString.trimmedNonEmpty(rawValue) else { return nil }
        guard !isPlaceholderLocationText(trimmed) else { return nil }
        return trimmed
    }

    static func locationTextSpecificityScore(_ locationText: String) -> Int {
        let normalized = locationText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()

        let placeholderTokens = [
            "TBC",
            "TBD",
            "TO BE CONFIRMED",
            "TO BE ANNOUNCED",
            "VENUE TBC",
            "VENUE TBD",
        ]

        if placeholderTokens.contains(where: { normalized == $0 || normalized.contains($0) }) {
            return 0
        }

        let commaSeparatedParts = locationText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let wordCount = locationText
            .split(whereSeparator: \.isWhitespace)
            .count

        let aliasBonus = (locationText.contains("(") && locationText.contains(")")) ? 5 : 0
        return (commaSeparatedParts.count * 10) + wordCount + aliasBonus
    }

    static func resolvedClubCountryName(
        venueCountry: String?,
        inferredLeagueCountry: String?,
        sanitizedClubLocation: String?,
        teamName: String?,
        teamLocation: String?,
        teamAbbreviation: String?,
        venueCity: String?
    ) -> String? {
        if let venueCountry,
           shouldTrustClubVenueCountry(
               venueCountry: venueCountry,
               inferredLeagueCountry: inferredLeagueCountry,
               sanitizedClubLocation: sanitizedClubLocation,
               teamName: teamName,
               teamLocation: teamLocation,
               teamAbbreviation: teamAbbreviation,
               venueCity: venueCity
           ) {
            return venueCountry
        }

        return inferredLeagueCountry ?? sanitizedClubLocation ?? venueCountry
    }

    static func shouldTrustClubVenueCountry(
        venueCountry: String?,
        inferredLeagueCountry: String?,
        sanitizedClubLocation: String?,
        teamName: String?,
        teamLocation: String?,
        teamAbbreviation: String?,
        venueCity: String?
    ) -> Bool {
        guard let venueCountry = stringValue(venueCountry) else { return false }
        guard let inferredLeagueCountry = stringValue(inferredLeagueCountry) else { return true }

        if countryNamesMatch(venueCountry, inferredLeagueCountry) {
            return true
        }

        if let sanitizedClubLocation,
           countryNamesMatch(venueCountry, sanitizedClubLocation) {
            return true
        }

        if clubVenueMatchesIdentity(
            teamName: teamName,
            teamLocation: teamLocation,
            teamAbbreviation: teamAbbreviation,
            venueCity: venueCity,
            venueCountry: venueCountry
        ) {
            return true
        }

        return areRelatedBritishFootballCountries(venueCountry, inferredLeagueCountry)
    }

    static func countryNamesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        let normalizedLeft = normalizedCountryIdentityKey(lhs)
        let normalizedRight = normalizedCountryIdentityKey(rhs)

        guard !normalizedLeft.isEmpty, !normalizedRight.isEmpty else { return false }
        return normalizedLeft == normalizedRight
    }

    static func areRelatedBritishFootballCountries(_ lhs: String?, _ rhs: String?) -> Bool {
        let normalizedLeft = normalizedCountryIdentityKey(lhs)
        let normalizedRight = normalizedCountryIdentityKey(rhs)

        guard !normalizedLeft.isEmpty, !normalizedRight.isEmpty else { return false }
        guard britishFootballCountries.contains(normalizedLeft),
              britishFootballCountries.contains(normalizedRight) else {
            return false
        }

        return true
    }

    static func clubVenueMatchesIdentity(
        teamName: String?,
        teamLocation: String?,
        teamAbbreviation: String?,
        venueCity: String?,
        venueCountry: String?
    ) -> Bool {
        let identityTokens = clubIdentityTokens(
            teamName: teamName,
            teamLocation: teamLocation,
            teamAbbreviation: teamAbbreviation
        )
        guard !identityTokens.isEmpty else { return false }

        let localityTokens = locationIdentityTokens(venueCity).union(locationIdentityTokens(venueCountry))
        guard !localityTokens.isEmpty else { return false }
        return !identityTokens.isDisjoint(with: localityTokens)
    }

    static func isPlaceholderLocationText(_ rawValue: String) -> Bool {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()

        guard !normalized.isEmpty else { return false }

        let compactWhitespace = normalized.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        let placeholderTokens = [
            "TBC",
            "TBD",
            "TO BE ANNOUNCED",
            "TO BE CONFIRMED",
            "TO BE DETERMINED",
            "VENUE TBC",
            "VENUE TBD",
            "VENUE TO BE ANNOUNCED",
            "VENUE TO BE CONFIRMED",
            "VENUE TO BE DETERMINED",
            "LOCATION TBC",
            "LOCATION TBD",
            "UNKNOWN",
        ]

        return placeholderTokens.contains(where: { token in
            compactWhitespace == token || compactWhitespace.contains(token)
        })
    }

    static func teamAbbreviation(from team: [String: Any], fallbackName: String) -> String {
        stringValue(team["abbreviation"]) ?? String(fallbackName.prefix(3)).uppercased()
    }

    static func teamLogoURL(from team: [String: Any]) -> URL? {
        if let direct = safeURL(from: stringValue(team["logo"])) {
            return direct
        }

        let logos = team["logos"] as? [[String: Any]] ?? []
        if let preferred = logos.first(where: { (($0["rel"] as? [String]) ?? []).contains("default") }),
           let href = safeURL(from: stringValue(preferred["href"])) {
            return href
        }

        return logos.first.flatMap { safeURL(from: stringValue($0["href"])) }
    }

    static func stringValue(_ raw: Any?) -> String? {
        if let value = raw as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = raw as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int {
            return value
        }
        if let value = raw as? NSNumber {
            return value.intValue
        }
        if let value = stringValue(raw), let integer = Int(value) {
            return integer
        }
        if let value = stringValue(raw), let doubleValue = Double(value) {
            return Int(doubleValue)
        }
        return nil
    }

    static func safeURL(from raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        let normalized = raw.replacingOccurrences(of: "http://", with: "https://")
        return URL(string: normalized)
    }

    static func sanitizedCountryCandidate(
        _ raw: String?,
        teamName: String?,
        teamAbbreviation: String?
    ) -> String? {
        guard let candidate = stringValue(raw) else { return nil }
        let normalizedCandidate = normalizedLookupKey(candidate)

        if normalizedCandidate == normalizedLookupKey(teamName)
            || normalizedCandidate == normalizedLookupKey(teamAbbreviation) {
            return nil
        }

        return candidate
    }

    static func inferredNationalCountryName(
        displayName: String?,
        location: String?
    ) -> String? {
        let displayKey = normalizedCountryIdentityKey(displayName)
        let locationKey = normalizedCountryIdentityKey(location)

        if !locationKey.isEmpty,
           locationKey == displayKey,
           recognizedCountryLookupKeys.contains(locationKey) {
            return stringValue(location) ?? stringValue(displayName)
        }

        if !locationKey.isEmpty, recognizedCountryLookupKeys.contains(locationKey) {
            return stringValue(location)
        }

        if !displayKey.isEmpty, recognizedCountryLookupKeys.contains(displayKey) {
            return stringValue(displayName)
        }

        return nil
    }

    static func normalizedLookupKey(_ raw: String?) -> String {
        guard let raw = stringValue(raw) else { return "" }
        return raw
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .joined(separator: " ")
            .lowercased()
    }

    static func normalizedCountryIdentityKey(_ raw: String?) -> String {
        let normalized = normalizedLookupKey(raw)
        guard !normalized.isEmpty else { return "" }
        return countryIdentityAliases[normalized] ?? normalized
    }

    static func clubIdentityTokens(
        teamName: String?,
        teamLocation: String?,
        teamAbbreviation: String?
    ) -> Set<String> {
        locationIdentityTokens(teamName)
            .union(locationIdentityTokens(teamLocation))
            .subtracting(locationIdentityTokens(teamAbbreviation))
    }

    static func locationIdentityTokens(_ raw: String?) -> Set<String> {
        let normalized = normalizedLookupKey(raw)
        guard !normalized.isEmpty else { return [] }
        return Set(
            normalized
                .split(separator: " ")
                .map(String.init)
                .filter { token in
                    token.count > 1 && !genericClubIdentityTokens.contains(token)
                }
        )
    }

    static func jsonDictionary(from data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw NSError(domain: "FootballDataAPIClient", code: 1)
        }
        return dictionary
    }
}
