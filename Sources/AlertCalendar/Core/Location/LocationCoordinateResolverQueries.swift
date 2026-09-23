import Foundation

extension LocationCoordinateResolver {
    private static let venueQualifierPrefixes = [
        "Stadium",
    ]
    private static let venueQualifierSuffixes = [
        "Stadium",
        "Arena",
        "Ground",
    ]
    static let venueDescriptorTokens = [
        "arena",
        "ballpark",
        "centre",
        "center",
        "circuit",
        "coliseum",
        "court",
        "dome",
        "field",
        "ground",
        "park",
        "stadium",
        "track",
        "velodrome",
    ]

    static func searchQueries(from rawText: String) -> [String] {
        searchQueries(from: rawText, allowsLooseFallbacks: true)
    }

    static func strictSearchQueries(from rawText: String) -> [String] {
        searchQueries(from: rawText, allowsLooseFallbacks: false)
    }

    static func searchQueries(from rawText: String, allowsLooseFallbacks: Bool) -> [String] {
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

        if allowsLooseFallbacks, commaSeparatedParts.count >= 2 {
            appendIfNeeded(commaSeparatedParts.suffix(3).joined(separator: ", "))
        }

        if let first = commaSeparatedParts.first {
            let strippedFirst = strippingParentheticalAliases(from: first)
            let aliases = parentheticalAliases(in: first)
            for alias in aliases {
                if !trailingContext.isEmpty {
                    appendIfNeeded("\(alias), \(trailingContext)")
                }
                if allowsLooseFallbacks || trailingContext.isEmpty {
                    appendIfNeeded(alias)
                }
            }

            if !trailingContext.isEmpty {
                appendIfNeeded("\(strippedFirst), \(trailingContext)")
            }

            if allowsLooseFallbacks || trailingContext.isEmpty {
                appendIfNeeded(strippedFirst)
                appendIfNeeded(first)
            }
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
