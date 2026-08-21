import Foundation

enum AgendaSummaryState: Equatable, Sendable {
    case idle
    case loading
    case ready(String)
    case unavailable
}

enum AgendaSummaryAvailability: Equatable, Sendable {
    case available
    case unsupportedSystem
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady

    var isAvailable: Bool {
        self == .available
    }

    var settingsAlertMessage: String? {
        switch self {
        case .available:
            return nil
        case .unsupportedSystem:
            return "Agenda Summary requires macOS 26 or later."
        case .deviceNotEligible:
            return "Apple Intelligence isn't supported on this Mac, so Agenda Summary will remain hidden."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in System Settings to show Agenda Summary."
        case .modelNotReady:
            return "Apple Intelligence is still preparing its on-device model. Agenda Summary will appear automatically when it is ready."
        }
    }
}

enum AgendaSummaryPresentationAction: Equatable, Sendable {
    case request(fingerprint: Int)
    case cancel

    static func resolve(
        isEnabled: Bool,
        availability: AgendaSummaryAvailability,
        requestFingerprint: Int
    ) -> Self {
        guard isEnabled, availability.isAvailable else { return .cancel }
        return .request(fingerprint: requestFingerprint)
    }
}

struct AgendaSummaryRequest: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        let sourceKey: String
        let title: String
        let startsAt: Date
        let endsAt: Date?
        let isAllDay: Bool
        let kind: String
        let calendarName: String
        let attention: String
        let isRecurring: Bool
        let hasAttachment: Bool
        let description: String?
        let urlCount: Int
        let urlHosts: [String]
        let linkedPageURLs: [URL]
        var linkedPagePreviews: [String]
        let hasMeetingURL: Bool
        let travelTimeMinutes: Int?
        let location: String?
        let hasMapPoint: Bool
        let personalizedContext: String?
    }

    let now: Date
    let timeZoneIdentifier: String
    let uses24HourTime: Bool
    let maximumWords: Int
    var items: [Item]

    init(
        now: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        maximumWords: Int = AppSettingsRules.defaultAgendaSummaryMaximumWords,
        upcomingItems: [UpcomingItem],
        personalizedContextByItemKey: [String: String] = [:]
    ) {
        self.now = now
        self.timeZoneIdentifier = timeZone.identifier
        self.uses24HourTime = Self.localeUses24HourTime(locale)
        self.maximumWords = AppSettingsRules.normalizedAgendaSummaryMaximumWords(maximumWords)
        self.items = upcomingItems
            .filter { item in
                (item.kind == .event || item.kind == .reminder)
                    && Self.isRelevantForSummary(item)
            }
            .sorted { left, right in
                if left.date != right.date {
                    return left.date < right.date
                }
                return left.notificationKey < right.notificationKey
            }
            .map { item in
                Item(
                    sourceKey: item.notificationKey,
                    title: Self.bounded(item.title, maximumLength: 180),
                    startsAt: item.date,
                    endsAt: item.isAllDay ? nil : item.endDate,
                    isAllDay: item.isAllDay,
                    kind: item.kind.rawValue,
                    calendarName: Self.bounded(item.calendarName, maximumLength: 80),
                    attention: Self.attentionLevel(for: item),
                    isRecurring: item.isRecurring,
                    hasAttachment: item.hasDocumentIndicator,
                    description: Self.boundedDescription(
                        item.descriptionText,
                        maximumLength: 320
                    ),
                    urlCount: item.urlCount,
                    urlHosts: item.urlHosts.map { Self.bounded($0, maximumLength: 100) },
                    linkedPageURLs: item.agendaSummaryURLCandidates,
                    linkedPagePreviews: [],
                    hasMeetingURL: item.meetingURL != nil,
                    travelTimeMinutes: item.travelTimeMinutes,
                    location: Self.boundedOptional(item.locationText, maximumLength: 180),
                    hasMapPoint: item.locationCoordinate != nil,
                    personalizedContext: Self.boundedOptional(
                        personalizedContextByItemKey[item.notificationKey],
                        maximumLength: 280
                    )
                )
            }
    }

    private static func isRelevantForSummary(_ item: UpcomingItem) -> Bool {
        item.calendarName.caseInsensitiveCompare("Astronomy") != .orderedSame
            && AstronomyMoment(eventTitle: item.title) == nil
    }

    var fingerprint: Int {
        var hasher = Hasher()
        hasher.combine(maximumWords)
        for item in items {
            hasher.combine(item.sourceKey)
            hasher.combine(item.title)
            hasher.combine(item.startsAt.timeIntervalSince1970)
            hasher.combine(item.endsAt?.timeIntervalSince1970)
            hasher.combine(item.isAllDay)
            hasher.combine(item.kind)
            hasher.combine(item.calendarName)
            hasher.combine(item.attention)
            hasher.combine(item.isRecurring)
            hasher.combine(item.hasAttachment)
            hasher.combine(item.description)
            hasher.combine(item.urlCount)
            hasher.combine(item.urlHosts)
            hasher.combine(item.linkedPageURLs)
            hasher.combine(item.linkedPagePreviews)
            hasher.combine(item.hasMeetingURL)
            hasher.combine(item.travelTimeMinutes)
            hasher.combine(item.location)
            hasher.combine(item.hasMapPoint)
            hasher.combine(item.personalizedContext)
        }
        return hasher.finalize()
    }

    func generationFingerprint(usesLinkedPagePreviews: Bool) -> Int {
        var hasher = Hasher()
        hasher.combine(fingerprint)
        hasher.combine(usesLinkedPagePreviews)
        return hasher.finalize()
    }

    func addingLinkedPagePreviews(_ previewsByItemKey: [String: [String]]) -> Self {
        var enrichedRequest = self
        enrichedRequest.items = items.map { item in
            var enrichedItem = item
            enrichedItem.linkedPagePreviews = (previewsByItemKey[item.sourceKey] ?? []).compactMap {
                Self.boundedOptional($0, maximumLength: 420)
            }
            return enrichedItem
        }
        return enrichedRequest
    }

    private static func bounded(_ value: String, maximumLength: Int) -> String {
        let normalized = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > maximumLength else { return normalized }
        return String(normalized.prefix(maximumLength))
    }

    private static func boundedOptional(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        let boundedValue = bounded(value, maximumLength: maximumLength)
        return boundedValue.isEmpty ? nil : boundedValue
    }

    private static func boundedDescription(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        var redactedValue = value
        let urlStrings = MeetingURLResolver.allURLs(in: value)
            .flatMap { url in
                [url.absoluteString, url.absoluteString.removingPercentEncoding]
                    .compactMap { $0 }
            }
            .sorted { $0.count > $1.count }

        for urlString in urlStrings where !urlString.isEmpty {
            redactedValue = redactedValue.replacingOccurrences(of: urlString, with: "[link]")
        }

        return boundedOptional(redactedValue, maximumLength: maximumLength)
    }

    private static func attentionLevel(for item: UpcomingItem) -> String {
        if item.isAllDay || item.calendarName == "Astronomy" {
            return "background"
        }
        return "primary"
    }

    private static func localeUses24HourTime(_ locale: Locale) -> Bool {
        guard let hourFormat = DateFormatter.dateFormat(
            fromTemplate: "j",
            options: 0,
            locale: locale
        ) else {
            return false
        }
        return !hourFormat.contains("a")
    }
}

protocol AgendaSummaryGenerating: Sendable {
    var availability: AgendaSummaryAvailability { get }

    func generateSummary(for request: AgendaSummaryRequest) async throws -> String
}
