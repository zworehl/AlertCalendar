import AppKit
import EventKit
import Foundation

extension CalendarMonitor {
    func isCalendarSelected(_ calendar: AvailableCalendar) -> Bool {
        selectedCalendarIDs(for: calendar.kind).contains(calendar.id)
    }

    func setCalendarSelected(_ calendar: AvailableCalendar, isSelected: Bool) {
        var settings = snapshotSettings()
        var ids = calendar.kind == .event ? settings.selectedEventCalendarIDs : settings.selectedReminderCalendarIDs
        if isSelected {
            ids.insert(calendar.id)
        } else {
            ids.remove(calendar.id)
        }

        if calendar.kind == .event {
            settings.selectedEventCalendarIDs = ids
        } else {
            settings.selectedReminderCalendarIDs = ids
        }
        persistSettings(settings)
        refreshNow(reason: .calendarSelectionChanged)
    }

    func refreshAvailableCalendars() {
        if hasEventsAccess {
            let eventCalendars = eventStore.calendars(for: .event)
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            birthdayCalendarIDs = Set(
                eventCalendars
                    .filter { $0.type == .birthday }
                    .map(\.calendarIdentifier)
            )
            let nextAvailableEventCalendars = eventCalendars.map {
                AvailableCalendar(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    color: color(from: $0),
                    kind: .event,
                    accountTitle: normalizedAccountTitle(for: $0),
                    isSubscribed: $0.type == .subscription,
                    allowsContentModifications: $0.allowsContentModifications
                )
            }
            if availableEventCalendars != nextAvailableEventCalendars {
                availableEventCalendars = nextAvailableEventCalendars
            }
            syncStoredSelection(
                for: .event,
                availableIDs: Set(eventCalendars.map(\.calendarIdentifier))
            )
            syncStoredSlackStatusSyncRules(
                availableIDs: Set(eventCalendars.map(\.calendarIdentifier))
            )
        } else {
            if !availableEventCalendars.isEmpty {
                availableEventCalendars = []
            }
            birthdayCalendarIDs = []
        }

        if hasRemindersAccess {
            let reminderCalendars = eventStore.calendars(for: .reminder)
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            let nextAvailableReminderCalendars = reminderCalendars.map {
                AvailableCalendar(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    color: color(from: $0),
                    kind: .reminder,
                    accountTitle: normalizedAccountTitle(for: $0),
                    isSubscribed: $0.type == .subscription,
                    allowsContentModifications: $0.allowsContentModifications
                )
            }
            if availableReminderCalendars != nextAvailableReminderCalendars {
                availableReminderCalendars = nextAvailableReminderCalendars
            }
            syncStoredSelection(
                for: .reminder,
                availableIDs: Set(reminderCalendars.map(\.calendarIdentifier))
            )
        } else {
            if !availableReminderCalendars.isEmpty {
                availableReminderCalendars = []
            }
        }
    }

    func calendarsForSelection(kind: CalendarItemKind, selectedIDs: Set<String>) -> [EKCalendar] {
        let entityType: EKEntityType = kind == .event ? .event : .reminder
        let calendars = eventStore.calendars(for: entityType)
        let visibleIDs = FocusCalendarFilterStateStore.effectiveSelectedCalendarIDs(
            baseSelectedIDs: selectedIDs,
            availableIDs: Set(calendars.map(\.calendarIdentifier)),
            focusOverride: activeFocusCalendarFilterState?.selection(for: kind)
        )
        return calendars.filter { visibleIDs.contains($0.calendarIdentifier) }
    }

    func syncStoredSelection(for kind: CalendarItemKind, availableIDs: Set<String>) {
        syncStoredSelection(
            selectedKey: kind == .event ? DefaultsKeys.selectedEventCalendarIDs : DefaultsKeys.selectedReminderCalendarIDs,
            availableIDs: availableIDs
        )
    }

    func selectedCalendarIDs(for kind: CalendarItemKind) -> Set<String> {
        settingsStore.selectedCalendarIDs(for: kind)
    }

    private func syncStoredSelection(selectedKey: String, availableIDs: Set<String>) {
        guard !availableIDs.isEmpty else { return }

        let sortedAvailableIDs = Array(availableIDs).sorted()
        let recoveryKey = selectedKey == DefaultsKeys.selectedEventCalendarIDs
            ? DefaultsKeys.didAutoRecoverEmptyEventCalendarSelection
            : DefaultsKeys.didAutoRecoverEmptyReminderCalendarSelection

        if defaults.object(forKey: selectedKey) == nil {
            defaults.set(sortedAvailableIDs, forKey: selectedKey)
        } else if let stored = defaults.stringArray(forKey: selectedKey) {
            let filtered = stored.filter { availableIDs.contains($0) }
            if filtered.isEmpty,
               !stored.isEmpty,
               !defaults.bool(forKey: recoveryKey) {
                defaults.set(sortedAvailableIDs, forKey: selectedKey)
                defaults.set(true, forKey: recoveryKey)
            } else if filtered.isEmpty,
                      stored.isEmpty,
                      !defaults.bool(forKey: recoveryKey) {
                defaults.set(sortedAvailableIDs, forKey: selectedKey)
                defaults.set(true, forKey: recoveryKey)
            } else if filtered != stored {
                defaults.set(filtered, forKey: selectedKey)
            }
        } else {
            defaults.set(sortedAvailableIDs, forKey: selectedKey)
        }

    }

    func normalizedAccountTitle(for calendar: EKCalendar) -> String {
        let raw = calendar.source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Other Account" : raw
    }
}
