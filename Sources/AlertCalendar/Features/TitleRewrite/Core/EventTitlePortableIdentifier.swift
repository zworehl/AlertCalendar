import Foundation

enum EventTitlePortableIdentifier {
    private static let patterns = [
        #"(?<![\p{L}\p{N}])(?:[\p{L}][\p{L}\p{N}]{1,11}-\d{2,})(?![\p{L}\p{N}])"#,
        #"(?<![\p{L}\p{N}])#\d{3,}(?!\d)"#,
    ]

    static func values(
        in value: String,
        maximumCount: Int? = nil
    ) -> [String] {
        let nsValue = value as NSString
        var matches: [(location: Int, value: String)] = []
        var seen: Set<String> = []

        for pattern in patterns {
            guard let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                continue
            }
            for match in expression.matches(
                in: value,
                range: NSRange(location: 0, length: nsValue.length)
            ) {
                let identifier = nsValue.substring(with: match.range)
                let identity = identifier.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: nil
                )
                if seen.insert(identity).inserted {
                    matches.append((match.range.location, identifier))
                }
            }
        }

        let values = matches
            .sorted { $0.location < $1.location }
            .map(\.value)
        guard let maximumCount else { return values }
        return Array(values.prefix(max(0, maximumCount)))
    }
}
