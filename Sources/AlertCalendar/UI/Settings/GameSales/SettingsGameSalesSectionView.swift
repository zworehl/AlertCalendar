import AppKit
import Combine
import SwiftUI

struct SettingsGameSalesSectionView: View {
    enum BrowseMode: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming"
        case added = "Added"

        var id: String { rawValue }
    }

    enum StoreFilter: String, CaseIterable, Identifiable {
        case all = "All Stores"
        case steam = "Steam"
        case xbox = "Xbox"
        case playStation = "PlayStation"
        case nintendoSwitch = "Nintendo Switch"

        var id: String { rawValue }

        func includes(_ store: GameStore) -> Bool {
            switch self {
            case .all:
                return true
            case .steam:
                return store == .steam
            case .xbox:
                return store == .xbox
            case .playStation:
                return store == .playStation
            case .nintendoSwitch:
                return store == .nintendoSwitch
            }
        }
    }

    static let minimumCardWidth: CGFloat = 272
    static let preferredCardWidth: CGFloat = 306
    static let inlineFieldLabelWidth: CGFloat = 92

    @ObservedObject var monitor: CalendarMonitor

    @AppStorage(DefaultsKeys.gameSaleTargetCalendarID) var targetCalendarID = ""
    @AppStorage(DefaultsKeys.gameSaleCalendarAlertOption) var calendarAlertOptionRaw = GameSaleCalendarAlertOption.fifteenMinutesBefore.rawValue
    @AppStorage(DefaultsKeys.enableGameSaleAutoAddNotifications) var enableAutoAddNotifications = true

    @State var browseMode: BrowseMode = .upcoming
    @State var storeFilter: StoreFilter = .all
    @State var autoAddStores: Set<GameStore> = []
    @State var writableCalendars: [AvailableCalendar] = []
    @State var visibleNow = AlertCalendarClock.nowRoundedToSecond()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            introductionPanel

            if !monitor.hasEventsAccess {
                feedbackPanel(
                    title: "Calendar access required",
                    detail: "Grant Calendar access to add and manage scheduled game sales.",
                    systemImage: "calendar.badge.exclamationmark",
                    tint: .orange
                )
            } else if writableCalendars.isEmpty {
                feedbackPanel(
                    title: "No writable calendars",
                    detail: "Create or enable a writable Apple Calendar before adding game sales.",
                    systemImage: "calendar.badge.minus",
                    tint: .orange
                )
            } else {
                controlsPanel
                salesContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            synchronizeCalendarConfiguration()
            autoAddStores = monitor.gameSaleAutoAddStores()
        }
        .task {
            await monitor.refreshGameSales(forceRefresh: false)
        }
        .onChange(of: calendarAlertOptionRaw) { _ in
            monitor.applyManagedGameSaleAlertConfiguration()
        }
        .onChange(of: targetCalendarID) { identifier in
            guard !identifier.isEmpty else { return }
            monitor.refreshNow(reason: .calendarSelectionChanged)
        }
        .onReceive(monitor.$availableEventCalendars.removeDuplicates()) { _ in
            synchronizeCalendarConfiguration()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let nextStores = monitor.gameSaleAutoAddStores()
            guard nextStores != autoAddStores else { return }
            autoAddStores = nextStores
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            visibleNow = AlertCalendarClock.nowRoundedToSecond()
            synchronizeCalendarConfiguration()
        }
        .onReceive(
            Timer.publish(every: 60, on: .main, in: .common).autoconnect()
        ) { now in
            visibleNow = now
        }
    }

    var displayedSales: [GameSaleEvent] {
        monitor.gameSales
            .filter { $0.endDateExclusive > visibleNow }
            .filter { storeFilter.includes($0.store) }
            .filter { sale in
                browseMode != .added || monitor.isGameSalePresent(sale)
            }
            .sorted { lhs, rhs in
                let lhsIsActive = lhs.startDate <= visibleNow
                let rhsIsActive = rhs.startDate <= visibleNow
                if lhsIsActive != rhsIsActive {
                    return lhsIsActive && !rhsIsActive
                }
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate < rhs.startDate
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    var calendarAlertOption: GameSaleCalendarAlertOption {
        GameSaleCalendarAlertOption(rawValue: calendarAlertOptionRaw) ?? .fifteenMinutesBefore
    }

    var calendarAlertBinding: Binding<GameSaleCalendarAlertOption> {
        Binding(
            get: { calendarAlertOption },
            set: { calendarAlertOptionRaw = $0.rawValue }
        )
    }

    func synchronizeCalendarConfiguration() {
        writableCalendars = monitor.writableGameSaleTargetCalendars()
        if targetCalendarID.isEmpty,
           let resolvedID = monitor.gameSaleTargetCalendarID() {
            targetCalendarID = resolvedID
        }
    }
}
