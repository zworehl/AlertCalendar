import Foundation

enum AppSettingsRules {
    static let minimumFootballWindowDays = 1
    static let maximumFootballWindowDays = 45
    static let dropdownListItemOptions = Array(stride(from: 5, through: 100, by: 5))
    static let defaultMaximumDropdownItems = 10
    static let defaultDropdownWindowHours = 24
    static let dropdownWindowHourOptions = Array(1 ... 23)
        + (1 ... 6).map { $0 * 24 }
        + (1 ... 3).map { $0 * 7 * 24 }
        + (1 ... 6).map { $0 * 30 * 24 }
    static let agendaSummaryMaximumWordOptions = Array(stride(from: 30, through: 100, by: 10))
    static let defaultAgendaSummaryMaximumWords = 60
    static let slackStatusLeadMinuteOptions = [5, 10, 15, 30]
    static let defaultSlackStatusLeadMinutes = 10

    static func roundedCoordinate(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    static func normalizedDropdownWindowHours(_ value: Int) -> Int {
        nearestOption(
            to: value,
            in: dropdownWindowHourOptions,
            fallback: defaultDropdownWindowHours
        )
    }

    static func adjustedDropdownWindowHours(currentValue: Int, incrementing: Bool) -> Int {
        let normalized = normalizedDropdownWindowHours(currentValue)
        guard let index = dropdownWindowHourOptions.firstIndex(of: normalized) else {
            return defaultDropdownWindowHours
        }
        let offset = incrementing ? 1 : -1
        let adjustedIndex = max(0, min(dropdownWindowHourOptions.count - 1, index + offset))
        return dropdownWindowHourOptions[adjustedIndex]
    }

    static func normalizedMaximumDropdownItems(_ value: Int) -> Int {
        nearestOption(
            to: value,
            in: dropdownListItemOptions,
            fallback: defaultMaximumDropdownItems
        )
    }

    static func maximumMenuBarRotationWindowMinutes(dropdownWindowHours: Int) -> Int {
        let normalizedDropdownHours = normalizedDropdownWindowHours(dropdownWindowHours)
        if normalizedDropdownHours == 1 {
            return 55
        }

        return min(720, (normalizedDropdownHours - 1) * 60)
    }

    static func maximumContextualPreviewLeadMinutes(dropdownWindowHours: Int) -> Int {
        normalizedDropdownWindowHours(dropdownWindowHours) * 60
    }

    static func normalizedMenuBarRotationWindowMinutes(_ value: Int, dropdownWindowHours: Int) -> Int {
        let upperBound = maximumMenuBarRotationWindowMinutes(dropdownWindowHours: dropdownWindowHours)
        let fallback = min(60, upperBound)
        let candidate = value > 0 ? value : fallback
        let clamped = max(5, min(upperBound, candidate))

        if clamped < 60 {
            return Int((Double(clamped) / 5.0).rounded()) * 5
        }

        return Int((Double(clamped) / 60.0).rounded()) * 60
    }

    static func normalizedContextualPreviewLeadMinutes(_ value: Int, dropdownWindowHours: Int) -> Int {
        let upperBound = maximumContextualPreviewLeadMinutes(dropdownWindowHours: dropdownWindowHours)
        let fallback = min(120, upperBound)
        let candidate = value > 0 ? value : fallback
        let clamped = max(60, min(upperBound, candidate))
        return Int((Double(clamped) / 60.0).rounded()) * 60
    }

    static func adjustedMenuBarRotationWindowMinutes(
        currentValue: Int,
        incrementing: Bool,
        dropdownWindowHours: Int
    ) -> Int {
        let normalizedCurrentValue = normalizedMenuBarRotationWindowMinutes(
            currentValue,
            dropdownWindowHours: dropdownWindowHours
        )
        let upperBound = maximumMenuBarRotationWindowMinutes(dropdownWindowHours: dropdownWindowHours)

        if incrementing {
            if normalizedCurrentValue < 55 {
                return min(55, normalizedCurrentValue + 5)
            }
            if normalizedCurrentValue < 60 {
                return min(60, upperBound)
            }
            return min(upperBound, normalizedCurrentValue + 60)
        }

        if normalizedCurrentValue <= 60 {
            return max(5, normalizedCurrentValue - 5)
        }

        let nextValue = normalizedCurrentValue - 60
        return max(60, nextValue)
    }

    static func normalizedAlertLeadMinutes(_ value: Int) -> Int {
        max(1, value)
    }

    static func normalizedConcurrentEventRotationSeconds(_ value: Int) -> Int {
        max(5, value)
    }

    static func normalizedEventTitleMaxCharacters(_ value: Int) -> Int {
        max(1, value)
    }

    static func normalizedAgendaSummaryMaximumWords(_ value: Int) -> Int {
        nearestOption(
            to: value,
            in: agendaSummaryMaximumWordOptions,
            fallback: defaultAgendaSummaryMaximumWords
        )
    }

    static func normalizedSlackStatusLeadMinutes(_ value: Int) -> Int {
        nearestOption(
            to: value,
            in: slackStatusLeadMinuteOptions,
            fallback: defaultSlackStatusLeadMinutes
        )
    }

    private static func nearestOption(to value: Int, in options: [Int], fallback: Int) -> Int {
        let candidate = value > 0 ? value : fallback
        return options.min { lhs, rhs in
            let lhsDistance = abs(lhs - candidate)
            let rhsDistance = abs(rhs - candidate)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            return lhs < rhs
        } ?? fallback
    }

    static func normalizedFootballWindowDays(_ value: Int) -> Int {
        max(minimumFootballWindowDays, min(maximumFootballWindowDays, value))
    }
}
