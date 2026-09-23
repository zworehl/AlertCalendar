import AppIntents
import Combine
import Foundation

struct FocusFilterRuntimeState {
    var observer: AnyCancellable?
    var refreshTask: Task<Void, Never>?
    var revision = UUID()
}

extension CalendarMonitor {
    func startFocusFilterObserver() {
        focusFilterRuntime.observer = DistributedNotificationCenter.default()
            .publisher(for: FocusCalendarFilterStateStore.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshFocusCalendarFilterStateFromDefaults()
            }
    }

    func refreshFocusCalendarFilterStateFromDefaults() {
        applyFocusCalendarFilterState(FocusCalendarFilterStateStore.load(defaults: defaults))
    }

    func scheduleFocusFilterRefresh() {
        focusFilterRuntime.refreshTask?.cancel()
        focusFilterRuntime.refreshTask = Task { [weak self] in
            await self?.refreshFocusCalendarFilterStateFromSystem()
        }
    }

    func refreshFocusCalendarFilterStateFromSystem() async {
        refreshFocusCalendarFilterStateFromDefaults()
        let revision = focusFilterRuntime.revision
        do {
            let current = try await AlertCalendarFocusFilter.current
            guard !Task.isCancelled, revision == focusFilterRuntime.revision else { return }
            let state = AlertCalendarFocusFilter.state(from: current)
            FocusCalendarFilterStateStore.save(state, defaults: defaults)
            applyFocusCalendarFilterState(state)
        } catch let error as SetFocusFilterIntentError where error == .notFound {
            guard !Task.isCancelled, revision == focusFilterRuntime.revision else { return }
            FocusCalendarFilterStateStore.save(nil, defaults: defaults)
            applyFocusCalendarFilterState(nil)
        } catch {
            // Keep the last delivered filter if the system is temporarily unavailable.
        }
    }

    func applyFocusCalendarFilterState(_ state: FocusCalendarFilterState?) {
        guard state != activeFocusCalendarFilterState else { return }
        focusFilterRuntime.revision = UUID()
        activeFocusCalendarFilterState = state
        cancelReminderRefresh(clearCachedItems: false)
        cancelAgendaSummary()

        // Remove hidden items immediately, before an asynchronous calendar refresh.
        let settings = snapshotSettings()
        let eventIDs = focusVisibleCalendarIDs(for: .event, baseIDs: settings.selectedEventCalendarIDs)
        let reminderIDs = focusVisibleCalendarIDs(for: .reminder, baseIDs: settings.selectedReminderCalendarIDs)
        func isVisible(_ item: UpcomingItem) -> Bool {
            guard let calendarID = item.calendarID else { return true }
            return (item.kind == .reminder ? reminderIDs : eventIDs).contains(calendarID)
        }
        upcomingItems = upcomingItems.filter(isVisible)
        allDayEventItems = allDayEventItems.filter(isVisible)
        let now = fixedSecondNow()
        pruneAlertCaches(using: upcomingItems)
        evaluateAlert(now: now, settings: settings)
        updateMenuBarState(now: now, settings: settings)
        enqueueRefresh(reason: .focusFilterChanged)
    }

    func focusVisibleCalendarIDs(for kind: CalendarItemKind, baseIDs: Set<String>) -> Set<String> {
        let calendars = kind == .event ? availableEventCalendars : availableReminderCalendars
        return FocusCalendarFilterStateStore.effectiveSelectedCalendarIDs(
            baseSelectedIDs: baseIDs,
            availableIDs: Set(calendars.map(\.id)),
            focusOverride: activeFocusCalendarFilterState?.selection(for: kind)
        )
    }
}
