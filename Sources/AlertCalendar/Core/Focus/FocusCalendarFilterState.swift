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
        !calendarIDs.isEmpty
    }

    func normalized(availableIDs: Set<String>) -> FocusCalendarSelectionOverride? {
        let filteredIDs = calendarIDs.intersection(availableIDs)
        guard !filteredIDs.isEmpty else { return nil }

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
        guard let data = defaults.data(forKey: DefaultsKeys.activeFocusCalendarFilterState) else {
            return nil
        }

        return try? JSONDecoder().decode(FocusCalendarFilterState.self, from: data)
    }

    static func save(_ state: FocusCalendarFilterState?, defaults: UserDefaults = .standard) {
        if let state {
            guard let encoded = try? JSONEncoder().encode(state) else { return }
            let existing = defaults.data(forKey: DefaultsKeys.activeFocusCalendarFilterState)
            guard existing != encoded else { return }
            defaults.set(encoded, forKey: DefaultsKeys.activeFocusCalendarFilterState)
        } else {
            guard defaults.object(forKey: DefaultsKeys.activeFocusCalendarFilterState) != nil else { return }
            defaults.removeObject(forKey: DefaultsKeys.activeFocusCalendarFilterState)
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
