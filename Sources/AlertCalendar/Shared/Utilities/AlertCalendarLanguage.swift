import Foundation

enum AlertCalendarLanguage {
    static let english = Locale(identifier: "en_US_POSIX")
    private static let state = LanguageState()

    static var current: AppLanguage {
        get { state.get() }
        set {
            guard state.get() != newValue else { return }
            state.set(newValue)
            NotificationCenter.default.post(name: .alertCalendarLanguageDidChange, object: nil)
        }
    }
    static var locale: Locale { current.locale }

    static func uses24HourTime(_ locale: Locale = .autoupdatingCurrent) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "h a"
        return !format.contains("a")
    }

    static func dateFormatter(template: String, clockLocale: Locale, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        let template = uses24HourTime(clockLocale)
            ? template.replacingOccurrences(of: "h:mm a", with: "HH:mm") : template
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    /// System error descriptions follow macOS's language. Keep app-authored
    /// errors, and give system failures a localized explanation plus their code.
    static func errorMessage(_ error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription { return description }
        let error = error as NSError
        switch (error.domain, error.code) {
        case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet): return L10n.text("The internet connection appears to be offline.")
        case (NSURLErrorDomain, NSURLErrorTimedOut): return L10n.text("The request timed out. Try again.")
        case (NSURLErrorDomain, NSURLErrorCancelled): return L10n.text("The request was canceled.")
        default: return L10n.text("The operation could not be completed (\(error.domain), code \(error.code)).")
        }
    }
}

private final class LanguageState: @unchecked Sendable {
    private let lock = NSLock()
    private var language: AppLanguage = .english

    func get() -> AppLanguage {
        lock.lock()
        defer { lock.unlock() }
        return language
    }

    func set(_ value: AppLanguage) {
        lock.lock()
        defer { lock.unlock() }
        language = value
    }
}

extension Notification.Name {
    static let alertCalendarLanguageDidChange = Notification.Name("AlertCalendar.languageDidChange")
}
