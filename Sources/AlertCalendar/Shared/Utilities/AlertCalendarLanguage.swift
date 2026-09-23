import Foundation

enum AlertCalendarLanguage {
    static let english = Locale(identifier: "en_US_POSIX")

    static func uses24HourTime(_ locale: Locale = .autoupdatingCurrent) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "h a"
        return !format.contains("a")
    }

    static func dateFormatter(template: String, clockLocale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = english
        formatter.timeZone = timeZone
        let template = uses24HourTime(clockLocale)
            ? template.replacingOccurrences(of: "h:mm a", with: "HH:mm") : template
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    /// System error descriptions follow macOS's language. Keep app-authored
    /// errors, and give system failures an English explanation plus their code.
    static func errorMessage(_ error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription { return description }
        let error = error as NSError
        switch (error.domain, error.code) {
        case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet): return "The internet connection appears to be offline."
        case (NSURLErrorDomain, NSURLErrorTimedOut): return "The request timed out. Try again."
        case (NSURLErrorDomain, NSURLErrorCancelled): return "The request was canceled."
        default: return "The operation could not be completed (\(error.domain), code \(error.code))."
        }
    }
}
