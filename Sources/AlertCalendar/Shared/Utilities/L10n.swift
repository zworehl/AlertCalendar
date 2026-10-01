import Foundation

/// Interpolation uses stable catalog keys, keeping imported titles and names as values.
struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]

    init(stringLiteral value: String) {
        key = value
        arguments = []
    }

    init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity)
            arguments.reserveCapacity(interpolationCount)
        }

        mutating func appendLiteral(_ literal: String) {
            key += literal
        }

        mutating func appendInterpolation<T>(_ value: T) {
            key += "%@"
            arguments.append(String(describing: value))
        }
    }
}

enum L10n {
    private static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues:
        AppLanguage.allCases.compactMap { language in
            guard let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return nil }
            return (language, bundle)
        }
    )

    static func lookup(_ key: String, language: AppLanguage = AlertCalendarLanguage.current) -> String {
        bundles[language]?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
    }

    static func text(_ message: LocalizedMessage, language: AppLanguage = AlertCalendarLanguage.current) -> String {
        let format = lookup(message.key, language: language)
        guard !message.arguments.isEmpty else { return format }
        // Replace placeholders without treating imported values or literal percent signs as printf syntax.
        var result = ""
        var remaining = format[...]
        for argument in message.arguments {
            guard let range = remaining.range(of: "%@") else { break }
            result += remaining[..<range.lowerBound] + argument
            remaining = remaining[range.upperBound...]
        }
        return result + remaining
    }
}
