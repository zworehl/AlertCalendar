import Foundation

extension AppleIntelligenceAgendaSummaryClient {
    static func deterministicFallback(for request: AgendaSummaryRequest) -> String {
        let timeZone = TimeZone(identifier: request.timeZoneIdentifier) ?? .autoupdatingCurrent
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayCount = Set(request.items.map { calendar.startOfDay(for: $0.startsAt) }).count
        let itemWord = request.items.count == 1 ? "item" : "items"
        let dayWord = dayCount == 1 ? "day" : "days"
        var sentences = ["Your agenda includes \(request.items.count) \(itemWord) across \(dayCount) \(dayWord)."]

        var selectedItems: [AgendaSummaryRequest.Item] = []
        if let firstItem = request.items.first {
            selectedItems.append(firstItem)
        }
        if let enrichedItem = request.items.dropFirst().first(where: { fallbackDetail(for: $0) != nil }) {
            selectedItems.append(enrichedItem)
        } else if request.items.count > 1 {
            selectedItems.append(request.items[1])
        }

        for item in selectedItems {
            let scheduleSentence = fallbackScheduleSentence(
                for: item,
                request: request,
                calendar: calendar,
                timeZone: timeZone
            )
            let detailSentence = fallbackDetail(for: item)
            let detailedCandidate = [scheduleSentence, detailSentence]
                .compactMap { $0 }
                .joined(separator: " ")

            if wordCount(sentences.joined(separator: " ") + " " + detailedCandidate)
                <= request.maximumWords {
                sentences.append(detailedCandidate)
            } else if wordCount(sentences.joined(separator: " ") + " " + scheduleSentence)
                <= request.maximumWords {
                sentences.append(scheduleSentence)
            }
        }

        let result = sentences.joined(separator: " ")
        precondition(result.split(whereSeparator: \Character.isWhitespace).count <= request.maximumWords)
        return result
    }

    static func containsMetadataInventoryLanguage(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return [
            "relevant context",
            "context includes",
            "metadata includes",
            "linked-page preview",
            "linked page preview",
            "personalized preview",
            "personalized previews",
        ].contains(where: normalized.contains)
    }

    private static func fallbackScheduleSentence(
        for item: AgendaSummaryRequest.Item,
        request: AgendaSummaryRequest,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> String {
        let today = calendar.startOfDay(for: request.now)
        let itemDay = calendar.startOfDay(for: item.startsAt)
        let dayOffset = calendar.dateComponents([.day], from: today, to: itemDay).day
        let dayText: String
        switch dayOffset {
        case 0:
            dayText = "Today"
        case 1:
            dayText = "Tomorrow"
        default:
            let dateFormatter = DateFormatter()
            dateFormatter.calendar = calendar
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = timeZone
            dateFormatter.dateFormat = "EEE, MMM d"
            dayText = dateFormatter.string(from: item.startsAt)
        }

        let title = firstWords(of: safeFallbackText(item.title), maximum: 8)
        guard !item.isAllDay else {
            return "\(dayText), all day: \(title)."
        }

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = request.uses24HourTime ? "HH:mm" : "h:mm a"
        return "\(dayText) at \(timeFormatter.string(from: item.startsAt)): \(title)."
    }

    private static func fallbackDetail(for item: AgendaSummaryRequest.Item) -> String? {
        let rawDetails = [
            item.description,
            item.linkedPagePreview,
            item.location.map { location in
                if let travelTimeMinutes = item.travelTimeMinutes {
                    return "At \(location); allow \(travelTimeMinutes) minutes for travel"
                }
                return "At \(location)"
            },
            item.travelTimeMinutes.map { "Allow \($0) minutes for travel" },
            item.personalizedContext,
        ]

        for rawDetail in rawDetails.compactMap({ $0 }) {
            let cleaned = safeFallbackText(rawDetail)
                .replacingOccurrences(
                    of: #"(?i)\b(?:page title|page description|page excerpt):\s*"#,
                    with: "",
                    options: .regularExpression
                )
                .replacingOccurrences(
                    of: #"(?i)\bpersonalized\s+[a-z ]+\s+preview:\s*"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            guard !cleaned.isEmpty, !containsMetadataInventoryLanguage(cleaned) else { continue }

            let firstSentence: String
            if let ending = cleaned.range(of: #"[.!?](?:\s|$)"#, options: .regularExpression) {
                firstSentence = String(cleaned[..<ending.lowerBound])
            } else {
                firstSentence = cleaned
            }
            let excerpt = firstWords(of: firstSentence, maximum: 14)
            guard !excerpt.isEmpty else { continue }
            return excerpt.prefix(1).uppercased() + String(excerpt.dropFirst()) + "."
        }
        return nil
    }

    private static func safeFallbackText(_ value: String) -> String {
        var sanitized = value
        for url in MeetingURLResolver.allURLs(in: sanitized) {
            sanitized = sanitized.replacingOccurrences(of: url.absoluteString, with: " ")
        }
        sanitized = sanitized.replacingOccurrences(
            of: #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            with: " ",
            options: .regularExpression
        )
        sanitized = sanitized.replacingOccurrences(of: "[link]", with: " ")
        return sanitized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstWords(of value: String, maximum: Int) -> String {
        value.split(whereSeparator: \Character.isWhitespace)
            .prefix(maximum)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wordCount(_ value: String) -> Int {
        value.split(whereSeparator: \Character.isWhitespace).count
    }
}
