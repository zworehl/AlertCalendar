import Foundation

struct EventMailContextRequest: Equatable, Sendable {
    static let maximumSearchTerms = 3

    let title: String
    let description: String?
    let participantEmailAddresses: [String]

    var searchTerms: [String] {
        var terms: [String] = []
        var seen: Set<String> = []

        for value in [title, description].compactMap({ $0 }) {
            for identifier in EventTitlePortableIdentifier.values(in: value) {
                let identity = identifier.lowercased()
                if seen.insert(identity).inserted {
                    terms.append(identifier)
                }
            }
        }

        if terms.isEmpty,
           let exactTitle = Self.safeExactTitleSearchTerm(title),
           seen.insert(exactTitle.lowercased()).inserted {
            terms.append(exactTitle)
        }

        return Array(terms.prefix(Self.maximumSearchTerms))
    }

    private static func safeExactTitleSearchTerm(_ value: String) -> String? {
        let normalized = AppleIntelligenceEventTitleRewriter.normalized(value)
        let wordCount = normalized.split(whereSeparator: \.isWhitespace).count
        guard normalized.count >= 16,
              normalized.count <= 160,
              wordCount >= 3 else {
            return nil
        }
        return normalized
    }
}

protocol EventMailContextProviding: Sendable {
    func contexts(for request: EventMailContextRequest) async -> [String]
}

actor AppleMailEventContextProvider: EventMailContextProviding {
    struct Message: Equatable, Sendable {
        let subject: String
        let content: String
    }

    typealias ScriptExecutor = @Sendable (_ source: String) -> [Message]

    private static let maximumMessages = 6
    private static let maximumContextCharacters = 1_200
    private static let maximumTotalCharacters = 3_600
    private let scriptExecutor: ScriptExecutor

    init(scriptExecutor: @escaping ScriptExecutor = AppleMailEventContextProvider.execute) {
        self.scriptExecutor = scriptExecutor
    }

    func contexts(for request: EventMailContextRequest) async -> [String] {
        let searchTerms = request.searchTerms
        guard !searchTerms.isEmpty else { return [] }

        let messages = scriptExecutor(Self.script(searchTerms: searchTerms))
        let referenceText = [request.title, request.description]
            .compactMap { $0 }
            + request.participantEmailAddresses
            + searchTerms
        var contexts: [String] = []
        var seen: Set<String> = []
        var usedCharacters = 0

        for message in messages.prefix(Self.maximumMessages) {
            guard let subject = boundedSubject(message.subject) else { continue }
            let excerpt = RelevantContextSelector.selectedText(
                from: message.content,
                referenceText: referenceText,
                maximumCharacters: Self.maximumContextCharacters,
                maximumSegments: 12
            )
            let context = [
                "Mail subject: \(subject)",
                excerpt.map { "Mail excerpt: \($0)" },
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
            let identity = context.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: nil
            )
            guard seen.insert(identity).inserted else { continue }

            let separatorCharacters = contexts.isEmpty ? 0 : 1
            guard usedCharacters + separatorCharacters + context.count
                    <= Self.maximumTotalCharacters else {
                continue
            }
            contexts.append(context)
            usedCharacters += separatorCharacters + context.count
        }

        return contexts
    }

    private func boundedSubject(_ value: String) -> String? {
        guard let subject = AlertCalendarString.trimmedNonEmpty(
            RelevantContextSelector.redacted(value)
        ) else {
            return nil
        }
        return String(subject.prefix(240))
    }

    nonisolated private static func script(searchTerms: [String]) -> String {
        let terms = searchTerms
            .map(appleScriptLiteral)
            .joined(separator: ", ")
        return """
        with timeout of 15 seconds
            set queryTerms to {\(terms)}
            set outputRows to {}
            set seenIDs to {}
            tell application "Mail"
                repeat with anAccount in every account
                    repeat with aMailbox in every mailbox of anAccount
                        repeat with queryTerm in queryTerms
                            try
                                set matchingMessages to every message of aMailbox whose subject contains (contents of queryTerm)
                                repeat with aMessage in matchingMessages
                                    set messageKey to ((id of aMessage) as text) & ":" & (name of aMailbox) & ":" & (name of anAccount)
                                    if seenIDs does not contain messageKey then
                                        set end of seenIDs to messageKey
                                        set messageContent to content of aMessage as text
                                        if (length of messageContent) > 5000 then
                                            set messageContent to text 1 thru 5000 of messageContent
                                        end if
                                        set end of outputRows to {(subject of aMessage as text), messageContent}
                                        if (count of outputRows) is greater than or equal to \(maximumMessages) then return outputRows
                                    end if
                                end repeat
                            end try
                        end repeat
                    end repeat
                end repeat
            end tell
            return outputRows
        end timeout
        """
    }

    nonisolated private static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }

    nonisolated private static func execute(source: String) -> [Message] {
        guard let script = NSAppleScript(source: source) else { return [] }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil, result.numberOfItems > 0 else { return [] }

        return (1 ... result.numberOfItems).compactMap { index in
            guard let row = result.atIndex(index), row.numberOfItems >= 2,
                  let subject = row.atIndex(1)?.stringValue,
                  let content = row.atIndex(2)?.stringValue else {
                return nil
            }
            return Message(subject: subject, content: content)
        }
    }
}
