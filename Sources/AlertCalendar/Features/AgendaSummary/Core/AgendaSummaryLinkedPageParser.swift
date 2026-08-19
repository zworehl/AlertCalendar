import Foundation

enum AgendaSummaryLinkedPageParser {
    private static let removableBlockPattern =
        #"(?is)<!--.*?-->|<(script|style|noscript|svg|template)\b[^>]*>.*?</\1>"#

    static func preview(
        from data: Data,
        mimeType: String?,
        textEncodingName: String?
    ) -> String? {
        let source = decodedString(from: data, encodingName: textEncodingName)
        guard !source.isEmpty else { return nil }

        if mimeType?.lowercased() == "text/plain" {
            return labeledPreview(title: nil, description: nil, excerpt: source)
        }

        let cleanedHTML = replacingMatches(
            in: source,
            pattern: removableBlockPattern,
            with: " "
        )
        let title = firstCapturedValue(in: cleanedHTML, pattern: #"(?is)<title\b[^>]*>(.*?)</title>"#)
            ?? metaContent(named: ["og:title", "twitter:title"], in: cleanedHTML)
        let description = metaContent(
            named: ["description", "og:description", "twitter:description"],
            in: cleanedHTML
        )
        let body = firstCapturedValue(in: cleanedHTML, pattern: #"(?is)<body\b[^>]*>(.*?)</body>"#)
            ?? cleanedHTML
        return labeledPreview(title: title, description: description, excerpt: body)
    }

    private static func labeledPreview(
        title: String?,
        description: String?,
        excerpt: String
    ) -> String? {
        let normalizedTitle = normalizedText(title, maximumLength: 120)
        let normalizedDescription = normalizedText(description, maximumLength: 240)
        let normalizedExcerpt = normalizedText(excerpt, maximumLength: 240)

        var parts: [String] = []
        if let normalizedTitle {
            parts.append("Page title: \(normalizedTitle)")
        }
        if let normalizedDescription,
           normalizedDescription.caseInsensitiveCompare(normalizedTitle ?? "") != .orderedSame {
            parts.append("Page description: \(normalizedDescription)")
        } else if parts.isEmpty, let normalizedExcerpt {
            parts.append("Page excerpt: \(normalizedExcerpt)")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ". ") + "."
    }

    private static func metaContent(named names: Set<String>, in html: String) -> String? {
        for tag in matches(in: html, pattern: #"(?is)<meta\b[^>]*>"#) {
            let attributes = attributePairs(in: tag).reduce(into: [String: String]()) { result, pair in
                let key = pair.0.lowercased()
                if result[key] == nil {
                    result[key] = pair.1
                }
            }
            let identifier = (attributes["name"] ?? attributes["property"])?.lowercased()
            if let identifier, names.contains(identifier), let content = attributes["content"] {
                return content
            }
        }
        return nil
    }

    private static func attributePairs(in tag: String) -> [(String, String)] {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?is)\b([a-z_:][-a-z0-9_:.]*)\s*=\s*(["'])(.*?)\2"#
        ) else { return [] }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        return expression.matches(in: tag, range: range).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: tag),
                  let valueRange = Range(match.range(at: 3), in: tag) else { return nil }
            return (String(tag[nameRange]), String(tag[valueRange]))
        }
    }

    private static func normalizedText(_ value: String?, maximumLength: Int) -> String? {
        guard let value else { return nil }
        var normalized = replacingMatches(in: value, pattern: #"(?is)<[^>]+>"#, with: " ")
        normalized = decodeCommonEntities(normalized)
        for url in MeetingURLResolver.allURLs(in: normalized) {
            normalized = normalized.replacingOccurrences(of: url.absoluteString, with: "[link]")
        }
        normalized = replacingMatches(
            in: normalized,
            pattern: #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            with: "[email]"
        )
        normalized = normalized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return normalized.count <= maximumLength
            ? normalized
            : String(normalized.prefix(maximumLength)).trimmingCharacters(in: .whitespaces)
    }

    private static func decodedString(from data: Data, encodingName: String?) -> String {
        let encoding: String.Encoding
        switch encodingName?.lowercased() {
        case "iso-8859-1", "latin1": encoding = .isoLatin1
        case "us-ascii", "ascii": encoding = .ascii
        case "windows-1252": encoding = .windowsCP1252
        default: encoding = .utf8
        }
        return String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
    }

    private static func firstCapturedValue(in value: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
              ),
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[range])
    }

    private static func matches(in value: String, pattern: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            Range(match.range, in: value).map { String(value[$0]) }
        }
    }

    private static func replacingMatches(in value: String, pattern: String, with replacement: String) -> String {
        value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    private static func decodeCommonEntities(_ value: String) -> String {
        let replacements = [
            ("&amp;", "&"), ("&#38;", "&"), ("&quot;", "\""), ("&#34;", "\""),
            ("&apos;", "'"), ("&#39;", "'"), ("&lt;", "<"), ("&#60;", "<"),
            ("&gt;", ">"), ("&#62;", ">"), ("&nbsp;", " "), ("&#160;", " "),
        ]
        return replacements.reduce(value) { result, replacement in
            result.replacingOccurrences(
                of: replacement.0,
                with: replacement.1,
                options: .caseInsensitive
            )
        }
    }
}
