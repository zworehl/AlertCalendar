import EventKit
import Foundation

struct GameSaleCalendarSnapshot {
    let sale: GameSaleEvent
    let event: EKEvent
}

extension CalendarMonitor {
    func persistManagedGameSaleEventRecords(_ records: [ManagedGameSaleEventRecord]) {
        var recordsBySaleID: [String: ManagedGameSaleEventRecord] = [:]
        for record in records {
            let existing = recordsBySaleID[record.saleID]
            let candidateHasUID = !(record.eventUID ?? "").isEmpty
            let existingHasUID = !((existing?.eventUID) ?? "").isEmpty
            if existing == nil || candidateHasUID || !existingHasUID {
                recordsBySaleID[record.saleID] = record
            }
        }

        let normalized = recordsBySaleID.values.sorted { lhs, rhs in
            if lhs.sale.startDate != rhs.sale.startDate {
                return lhs.sale.startDate < rhs.sale.startDate
            }
            return lhs.saleID < rhs.saleID
        }
        guard normalized != managedGameSaleEventRecords else { return }

        managedGameSaleEventRecords = normalized
        if normalized.isEmpty {
            defaults.removeObject(forKey: DefaultsKeys.managedGameSaleEventRecords)
        } else if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: DefaultsKeys.managedGameSaleEventRecords)
        }
    }

    func managedGameSaleRecord(for sale: GameSaleEvent) -> ManagedGameSaleEventRecord? {
        managedGameSaleEventRecords.first { record in
            record.saleID == sale.id || Self.gameSalesSemanticallyMatch(record.sale, sale)
        }
    }

    func managedGameSaleRecord(for event: EKEvent) -> ManagedGameSaleEventRecord? {
        let eventIdentifier = event.eventIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventUID = normalizedEventUID(for: event)

        return managedGameSaleEventRecords.first { record in
            if let eventUID, record.eventUID == eventUID {
                return true
            }
            if let eventIdentifier, record.eventIdentifier == eventIdentifier {
                return true
            }
            guard let snapshot = gameSaleSnapshot(for: event) else { return false }
            return record.calendarIdentifier == event.calendar?.calendarIdentifier
                && Self.gameSalesSemanticallyMatch(record.sale, snapshot.sale)
        }
    }

    func resolveManagedGameSaleEvent(for record: ManagedGameSaleEventRecord) -> EKEvent? {
        if let eventIdentifier = record.eventIdentifier,
           let event = eventStore.calendarItem(withIdentifier: eventIdentifier) as? EKEvent {
            return event
        }

        let calendar = Calendar.current
        let searchStart = calendar.date(byAdding: .day, value: -2, to: record.sale.startDate)
            ?? record.sale.startDate.addingTimeInterval(-2 * 86_400)
        let searchEnd = calendar.date(byAdding: .day, value: 2, to: record.sale.endDateExclusive)
            ?? record.sale.endDateExclusive.addingTimeInterval(2 * 86_400)
        let targetCalendars = eventStore.calendars(for: .event).filter {
            $0.calendarIdentifier == record.calendarIdentifier
        }

        if let eventUID = record.eventUID {
            let globalPredicate = eventStore.predicateForEvents(
                withStart: searchStart,
                end: searchEnd,
                calendars: nil
            )
            if let event = eventStore.events(matching: globalPredicate).first(where: {
                normalizedEventUID(for: $0) == eventUID
            }) {
                return event
            }
        }

        guard !targetCalendars.isEmpty else { return nil }
        let originalCalendarPredicate = eventStore.predicateForEvents(
            withStart: searchStart,
            end: searchEnd,
            calendars: targetCalendars
        )
        return eventStore.events(matching: originalCalendarPredicate).first { event in
            guard let snapshot = gameSaleSnapshot(for: event) else { return false }
            return Self.gameSalesSemanticallyMatch(record.sale, snapshot.sale)
        }
    }

    func gameSaleCalendarSnapshots(now: Date) -> [GameSaleCalendarSnapshot] {
        guard hasEventsAccess, let targetCalendar = resolvedGameSaleTargetCalendar() else { return [] }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .year, value: -1, to: now)
            ?? now.addingTimeInterval(-366 * 86_400)
        let end = calendar.date(byAdding: .year, value: 3, to: now)
            ?? now.addingTimeInterval(3 * 366 * 86_400)
        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: [targetCalendar]
        )

        return eventStore.events(matching: predicate).compactMap(gameSaleSnapshot(for:))
    }

    func gameSaleSnapshot(for event: EKEvent) -> GameSaleCalendarSnapshot? {
        guard event.isAllDay,
              let title = AlertCalendarString.trimmedNonEmpty(event.title),
              let startDate = event.startDate,
              let rawEndDate = event.endDate,
              let officialURL = event.url,
              let store = Self.gameStore(for: officialURL)
        else {
            return nil
        }

        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = Self.gameSaleExclusiveEndDate(rawEndDate, calendar: calendar)
        guard normalizedEnd > normalizedStart else { return nil }

        let sourceID = Self.calendarGameSaleSourceID(
            eventUID: normalizedEventUID(for: event),
            title: title,
            startDate: normalizedStart,
            calendar: calendar
        )
        let sale = GameSaleEvent(
            store: store,
            sourceID: sourceID,
            title: title,
            startDate: normalizedStart,
            endDateExclusive: normalizedEnd,
            officialURL: officialURL
        )
        return GameSaleCalendarSnapshot(sale: sale, event: event)
    }

    func refreshGameSaleTrackingSnapshot(now: Date) {
        let snapshots = gameSaleCalendarSnapshots(now: now)
        var allSales = fetchedGameSales.filter { $0.endDateExclusive > now }

        for record in managedGameSaleEventRecords where record.sale.endDateExclusive > now {
            if !allSales.contains(where: { Self.gameSalesSemanticallyMatch($0, record.sale) }) {
                allSales.append(record.sale)
            }
        }
        for snapshot in snapshots where snapshot.sale.endDateExclusive > now {
            if !allSales.contains(where: { Self.gameSalesSemanticallyMatch($0, snapshot.sale) }) {
                allSales.append(snapshot.sale)
            }
        }

        allSales.sort { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        var presenceByID: [String: GameSalePresence] = [:]
        for sale in allSales {
            guard let matchingSnapshot = snapshots.first(where: {
                Self.gameSalesSemanticallyMatch($0.sale, sale)
            }) else {
                presenceByID[sale.id] = .absent
                continue
            }

            let isManaged = managedGameSaleEventRecords.contains { record in
                Self.gameSalesSemanticallyMatch(record.sale, sale)
                    && (record.eventIdentifier == matchingSnapshot.event.eventIdentifier
                        || record.eventUID == normalizedEventUID(for: matchingSnapshot.event))
            }
            presenceByID[sale.id] = isManaged ? .managed : .external
        }

        gameSales = allSales
        gameSalePresenceByID = presenceByID
    }

    func isGameSalePresent(_ sale: GameSaleEvent) -> Bool {
        gameSalePresenceByID[sale.id] != .absent && gameSalePresenceByID[sale.id] != nil
    }

    func isGameSaleManaged(_ sale: GameSaleEvent) -> Bool {
        gameSalePresenceByID[sale.id] == .managed
    }

    nonisolated static func gameSalesSemanticallyMatch(
        _ lhs: GameSaleEvent,
        _ rhs: GameSaleEvent,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Bool {
        lhs.store == rhs.store
            && normalizedGameSaleTitle(lhs.title, store: lhs.store)
                == normalizedGameSaleTitle(rhs.title, store: rhs.store)
            && calendar.isDate(lhs.startDate, inSameDayAs: rhs.startDate)
            && calendar.isDate(lhs.endDateExclusive, inSameDayAs: rhs.endDateExclusive)
    }

    nonisolated static func normalizedGameSaleTitle(_ title: String, store: GameStore) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let normalized = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : " "
        }
        var words = String(normalized).split(whereSeparator: \Character.isWhitespace).map(String.init)
        let prefixes: [[String]]
        switch store {
        case .steam:
            prefixes = [["steam"]]
        case .xbox:
            prefixes = [["xbox"], ["microsoft", "store"]]
        case .playStation:
            prefixes = [["playstation"], ["ps", "store"]]
        case .nintendoSwitch:
            prefixes = [["nintendo", "switch"], ["nintendo"], ["eshop"]]
        }
        if let prefix = prefixes.first(where: { words.starts(with: $0) }) {
            words.removeFirst(prefix.count)
        }
        return words.joined(separator: " ")
    }

    nonisolated static func gameSaleExclusiveEndDate(
        _ rawEndDate: Date,
        calendar: Calendar = Calendar.current
    ) -> Date {
        let startOfEndDay = calendar.startOfDay(for: rawEndDate)
        if abs(rawEndDate.timeIntervalSince(startOfEndDay)) < 1 {
            return startOfEndDay
        }
        return calendar.date(byAdding: .day, value: 1, to: startOfEndDay)
            ?? startOfEndDay.addingTimeInterval(86_400)
    }

    nonisolated static func gameStore(for url: URL) -> GameStore? {
        GameStore.infer(from: url)
    }

    nonisolated static func calendarGameSaleSourceID(
        eventUID: String?,
        title: String,
        startDate: Date,
        calendar: Calendar
    ) -> String {
        if let eventUID = AlertCalendarString.trimmedNonEmpty(eventUID) {
            return "calendar-\(eventUID)"
        }
        let year = calendar.component(.year, from: startDate)
        let normalizedTitle = normalizedGameSaleTitle(title, store: .steam)
            .replacingOccurrences(of: " ", with: "-")
        return "calendar-\(normalizedTitle)-\(year)"
    }
}
