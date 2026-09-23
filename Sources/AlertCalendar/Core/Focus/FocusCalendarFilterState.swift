import Foundation

enum FocusCalendarSelectionAction: String, CaseIterable, Codable, Sendable {
    case hideSelected
    case showOnlySelected

    var title: String {
        switch self {
        case .hideSelected:
            return "Hide selected"
        case .showOnlySelected:
            return "Show only selected"
        }
    }
}

struct FocusCalendarSelectionOverride: Codable, Equatable, Sendable {
    var action: FocusCalendarSelectionAction
    var calendarIDs: Set<String>

    var isActive: Bool {
        action == .showOnlySelected || !calendarIDs.isEmpty
    }

    func normalized(availableIDs: Set<String>) -> FocusCalendarSelectionOverride? {
        let filteredIDs = calendarIDs.intersection(availableIDs)
        guard action == .showOnlySelected || !filteredIDs.isEmpty else { return nil }

        return FocusCalendarSelectionOverride(
            action: action,
            calendarIDs: filteredIDs
        )
    }
}

struct FocusCalendarFilterState: Codable, Equatable, Sendable {
    var eventSelection: FocusCalendarSelectionOverride?
    var reminderSelection: FocusCalendarSelectionOverride?

    var hasActiveOverrides: Bool {
        selection(for: .event) != nil || selection(for: .reminder) != nil
    }

    func selection(for kind: CalendarItemKind) -> FocusCalendarSelectionOverride? {
        let selection: FocusCalendarSelectionOverride?
        switch kind {
        case .event:
            selection = eventSelection
        case .reminder:
            selection = reminderSelection
        }

        guard let selection, selection.isActive else { return nil }
        return selection
    }

    func normalized(
        availableEventIDs: Set<String>,
        availableReminderIDs: Set<String>
    ) -> FocusCalendarFilterState? {
        let normalizedState = FocusCalendarFilterState(
            eventSelection: eventSelection?.normalized(availableIDs: availableEventIDs),
            reminderSelection: reminderSelection?.normalized(availableIDs: availableReminderIDs)
        )

        return normalizedState.hasActiveOverrides ? normalizedState : nil
    }
}

enum FocusCalendarFilterStateStore {
    static func load(defaults: UserDefaults = .standard) -> FocusCalendarFilterState? {
        guard let data = defaults.data(forKey: DefaultsKeys.focusCalendarFilterState) else {
            return nil
        }

        return try? JSONDecoder().decode(FocusCalendarFilterState.self, from: data)
    }

    static let didChangeNotification = Notification.Name("com.zworehl.alertcalendar.focusFilterChanged")

    static func save(_ state: FocusCalendarFilterState?, defaults: UserDefaults = .standard) {
        guard load(defaults: defaults) != state
            || (state == nil && defaults.object(forKey: DefaultsKeys.focusCalendarFilterState) != nil) else { return }
        if let state {
            guard let encoded = try? JSONEncoder().encode(state) else { return }
            defaults.set(encoded, forKey: DefaultsKeys.focusCalendarFilterState)
        } else {
            defaults.removeObject(forKey: DefaultsKeys.focusCalendarFilterState)
        }
        if defaults === UserDefaults.standard {
            DistributedNotificationCenter.default().postNotificationName(
                didChangeNotification, object: nil, userInfo: nil, deliverImmediately: true
            )
        }
    }

    static func effectiveSelectedCalendarIDs(
        baseSelectedIDs: Set<String>,
        availableIDs: Set<String>,
        focusOverride: FocusCalendarSelectionOverride?
    ) -> Set<String> {
        let normalizedBaseSelection = baseSelectedIDs.intersection(availableIDs)
        guard let focusOverride = focusOverride?.normalized(availableIDs: availableIDs) else {
            return normalizedBaseSelection
        }

        switch focusOverride.action {
        case .hideSelected:
            return normalizedBaseSelection.subtracting(focusOverride.calendarIDs)
        case .showOnlySelected:
            return focusOverride.calendarIDs
        }
    }
}
