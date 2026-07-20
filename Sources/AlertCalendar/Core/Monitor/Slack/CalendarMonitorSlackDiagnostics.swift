import Foundation

extension CalendarMonitor {
    func managedSlackItemTitles(
        from items: [UpcomingItem],
        rules: [SlackStatusSyncRule],
        now: Date
    ) -> String {
        let titles = items.compactMap { item -> String? in
            guard Self.isSlackStatusMeetingItem(item) else { return nil }
            let endDate = item.endDate ?? item.date.addingTimeInterval(60 * 60)
            if item.date <= now && endDate > now {
                return "active[\(item.calendarName): \(item.title)]"
            }

            guard item.date > now else { return nil }
            guard let calendarID = item.calendarID else { return nil }
            guard rules.contains(where: { rule in
                rule.calendarID == calendarID &&
                    rule.startsBeforeEvent &&
                    Self.slackStatusLeadDate(for: item, rule: rule) <= now
            }) else { return nil }
            return "upcoming[\(item.calendarName): \(item.title)]"
        }

        guard !titles.isEmpty else { return "none" }
        return titles.joined(separator: " | ")
    }

    func formattedSlackTransitionDate(_ date: Date?) -> String {
        guard let date else { return "none" }
        return Self.slackRuntimeDateFormatter.string(from: date)
    }

    func describeSlackTargets(_ targets: [SlackStatusSyncTarget]) -> String {
        guard !targets.isEmpty else { return "[]" }
        return targets.map { target in
            switch target.mode {
            case .clear:
                return "{\(target.connection.displayLabel): clear}"
            case let .meeting(snapshot):
                return "{\(target.connection.displayLabel): meeting[\(snapshot.statusText) \(snapshot.statusEmoji) exp=\(snapshot.statusExpiration)]}"
            }
        }
        .joined(separator: ", ")
    }

    func appendSlackDiagnosticsLog(_ message: String) {
        guard let logURL = slackDiagnosticsLogURL() else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = "[\(formatter.string(from: fixedSecondNow()))] \(message)\n"
        let lineData = Data(line.utf8)
        let fileManager = FileManager.default

        do {
            let directoryURL = logURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            if
                let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
                let fileSize = attributes[.size] as? NSNumber,
                fileSize.intValue > Self.slackDiagnosticsLogSizeLimit
            {
                try? fileManager.removeItem(at: logURL)
            }

            if !fileManager.fileExists(atPath: logURL.path) {
                fileManager.createFile(atPath: logURL.path, contents: nil)
            }

            let fileHandle = try FileHandle(forWritingTo: logURL)
            defer {
                try? fileHandle.close()
            }
            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: lineData)
        } catch {
            // Best effort diagnostics only.
        }
    }

    func slackDiagnosticsLogURL() -> URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/AlertCalendar", isDirectory: true)
            .appendingPathComponent("slack-sync.log", isDirectory: false)
    }
}
