#if canImport(AppIntents)
import AppIntents
import EventKit
import Foundation

@available(macOS 13.0, *)
enum AlertCalendarFocusFilterAction: String, CaseIterable, AppEnum {
    case hideSelected
    case showOnlySelected

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Calendar Focus Rule")

    static let caseDisplayRepresentations: [AlertCalendarFocusFilterAction: DisplayRepresentation] = [
        .hideSelected: "Hide selected",
        .showOnlySelected: "Show only selected",
    ]

    var selectionAction: FocusCalendarSelectionAction {
        switch self {
        case .hideSelected:
            return .hideSelected
        case .showOnlySelected:
            return .showOnlySelected
        }
    }
}

@available(macOS 13.0, *)
struct FocusEventCalendarQuery: EntityQuery {
    func entities(for identifiers: [FocusEventCalendarEntity.ID]) async throws -> [FocusEventCalendarEntity] {
        let available = Dictionary(uniqueKeysWithValues: FocusEventCalendarEntity.availableEntities().map { ($0.id, $0) })
        return identifiers.map { available[$0] ?? FocusEventCalendarEntity(id: $0, title: "Unavailable calendar", accountTitle: "") }
    }

    func suggestedEntities() async throws -> [FocusEventCalendarEntity] {
        FocusEventCalendarEntity.availableEntities()
    }
}

@available(macOS 13.0, *)
struct FocusReminderCalendarQuery: EntityQuery {
    func entities(for identifiers: [FocusReminderCalendarEntity.ID]) async throws -> [FocusReminderCalendarEntity] {
        let available = Dictionary(uniqueKeysWithValues: FocusReminderCalendarEntity.availableEntities().map { ($0.id, $0) })
        return identifiers.map { available[$0] ?? FocusReminderCalendarEntity(id: $0, title: "Unavailable list", accountTitle: "") }
    }

    func suggestedEntities() async throws -> [FocusReminderCalendarEntity] {
        FocusReminderCalendarEntity.availableEntities()
    }
}

@available(macOS 13.0, *)
struct FocusEventCalendarEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Event Calendar")
    static let defaultQuery = FocusEventCalendarQuery()

    let id: String
    let title: String
    let accountTitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: LocalizedStringResource(stringLiteral: accountTitle)
        )
    }

    static func availableEntities() -> [FocusEventCalendarEntity] {
        FocusCalendarEntityLoader.availableCalendars(for: .event).map {
            FocusEventCalendarEntity(
                id: $0.id,
                title: $0.title,
                accountTitle: $0.accountTitle
            )
        }
    }
}

@available(macOS 13.0, *)
struct FocusReminderCalendarEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Reminder List")
    static let defaultQuery = FocusReminderCalendarQuery()

    let id: String
    let title: String
    let accountTitle: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: LocalizedStringResource(stringLiteral: accountTitle)
        )
    }

    static func availableEntities() -> [FocusReminderCalendarEntity] {
        FocusCalendarEntityLoader.availableCalendars(for: .reminder).map {
            FocusReminderCalendarEntity(
                id: $0.id,
                title: $0.title,
                accountTitle: $0.accountTitle
            )
        }
    }
}

@available(macOS 13.0, *)
private enum FocusCalendarEntityLoader {
    static func availableCalendars(for kind: CalendarItemKind) -> [AvailableCalendar] {
        guard hasAccess(to: kind) else { return [] }

        let store = EKEventStore()
        let entityType: EKEntityType = kind == .event ? .event : .reminder

        return store.calendars(for: entityType)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map {
                AvailableCalendar(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    color: .systemGray,
                    kind: kind,
                    accountTitle: normalizedAccountTitle(for: $0),
                    isSubscribed: $0.type == .subscription
                )
            }
    }

    private static func hasAccess(to kind: CalendarItemKind) -> Bool {
        let entityType: EKEntityType = kind == .event ? .event : .reminder
        let status = EKEventStore.authorizationStatus(for: entityType)

        switch status {
        case .authorized:
            return true
        case .fullAccess:
            return true
        default:
            return false
        }
    }

    private static func normalizedAccountTitle(for calendar: EKCalendar) -> String {
        let raw = calendar.source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "Other Account" : raw
    }
}

@available(macOS 13.0, *)
struct AlertCalendarFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Filter calendars for this Focus"
    static let description: IntentDescription? = IntentDescription(
        "Hide selected calendars or show only selected calendars while this Focus is active."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Event calendar rule", default: .hideSelected)
    var eventCalendarRule: AlertCalendarFocusFilterAction

    @Parameter(title: "Event calendars")
    var eventCalendars: [FocusEventCalendarEntity]?

    @Parameter(title: "Reminder list rule", default: .hideSelected)
    var reminderCalendarRule: AlertCalendarFocusFilterAction

    @Parameter(title: "Reminder lists")
    var reminderCalendars: [FocusReminderCalendarEntity]?

    var displayRepresentation: DisplayRepresentation {
        let eventSummary = summaryLabel(
            for: eventCalendarRule,
            count: eventCalendars?.count ?? 0,
            singular: "event calendar",
            plural: "event calendars"
        )
        let reminderSummary = summaryLabel(
            for: reminderCalendarRule,
            count: reminderCalendars?.count ?? 0,
            singular: "reminder list",
            plural: "reminder lists"
        )

        if eventSummary.isEmpty && reminderSummary.isEmpty {
            return "Use default calendar selection"
        }

        let joined = [eventSummary, reminderSummary]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")

        return DisplayRepresentation(
            title: "Adjust calendar visibility",
            subtitle: LocalizedStringResource(stringLiteral: joined)
        )
    }

    func perform() async throws -> some IntentResult {
        FocusCalendarFilterStateStore.save(Self.state(from: self))
        return .result()
    }

    static func state(from filter: AlertCalendarFocusFilter) -> FocusCalendarFilterState? {
        let state = FocusCalendarFilterState(
            eventSelection: selectionOverride(
                action: filter.eventCalendarRule.selectionAction,
                ids: filter.eventCalendars?.map(\.id) ?? []
            ),
            reminderSelection: selectionOverride(
                action: filter.reminderCalendarRule.selectionAction,
                ids: filter.reminderCalendars?.map(\.id) ?? []
            )
        )

        return state.hasActiveOverrides ? state : nil
    }

    private static func selectionOverride(
        action: FocusCalendarSelectionAction,
        ids: [String]
    ) -> FocusCalendarSelectionOverride? {
        let selectedIDs = Set(ids)
        guard action == .showOnlySelected || !selectedIDs.isEmpty else { return nil }

        return FocusCalendarSelectionOverride(
            action: action,
            calendarIDs: selectedIDs
        )
    }

    private func summaryLabel(
        for rule: AlertCalendarFocusFilterAction,
        count: Int,
        singular: String,
        plural: String
    ) -> String {
        guard count > 0 else { return rule == .showOnlySelected ? "Show no \(plural)" : "" }

        let noun = count == 1 ? singular : plural
        switch rule {
        case .hideSelected:
            return "Hide \(count) \(noun)"
        case .showOnlySelected:
            return "Show only \(count) \(noun)"
        }
    }
}
#endif
