import Foundation

#if canImport(AppIntents)
import AppKit
import AppIntents
#endif

extension CalendarMonitor {
    func refreshFocusCalendarFilterStateFromDefaults() {
        let nextState = FocusCalendarFilterStateStore.load(defaults: defaults)
        if activeFocusCalendarFilterState != nextState {
            activeFocusCalendarFilterState = nextState
        }
    }

    func refreshFocusCalendarFilterStateFromSystemIfPossible() async {
        refreshFocusCalendarFilterStateFromDefaults()

        #if canImport(AppIntents)
        guard #available(macOS 13.0, *) else { return }
        guard NSApplication.shared.isActive else { return }

        do {
            let currentFilter = try await AlertCalendarFocusFilter.current
            let nextState = AlertCalendarFocusFilter.state(from: currentFilter)
            FocusCalendarFilterStateStore.save(nextState, defaults: defaults)
            if activeFocusCalendarFilterState != nextState {
                activeFocusCalendarFilterState = nextState
            }
        } catch let error as SetFocusFilterIntentError where error == .notFound {
            FocusCalendarFilterStateStore.save(nil, defaults: defaults)
            if activeFocusCalendarFilterState != nil {
                activeFocusCalendarFilterState = nil
            }
        } catch {
            refreshFocusCalendarFilterStateFromDefaults()
        }
        #endif
    }
}
