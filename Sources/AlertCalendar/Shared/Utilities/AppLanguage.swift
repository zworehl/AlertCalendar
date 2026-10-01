import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case spanishLatinAmerica = "es-419"

    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .english: "English"
        case .spanishLatinAmerica: "Español (Latinoamérica)"
        }
    }
    var locale: Locale {
        Locale(identifier: self == .english ? "en_US_POSIX" : "es_419")
    }
    var summaryLanguage: String {
        self == .english ? "English" : "Latin American Spanish"
    }
}
