import SwiftUI

extension MenuContentView {
    func agendaSummaryRequest(snapshot: LayoutSnapshot) -> AgendaSummaryRequest {
        let personalizedContexts = snapshot.displayedContextualActionItems.reduce(
            into: [String: String]()
        ) { result, item in
            if let context = Self.agendaSummaryPersonalizedContext(
                    for: item,
                    previewKind: snapshot.contextualPreviewKind(for: item)
            ) {
                result[item.notificationKey] = context
            }
        }
        return AgendaSummaryRequest(
            now: displayReferenceDate,
            maximumWords: settings.agendaSummaryMaximumWords,
            upcomingItems: Self.agendaSummaryItems(
                contextualItems: snapshot.displayedContextualActionItems,
                queueItems: snapshot.queueItemsForActions
            ),
            personalizedContextByItemKey: personalizedContexts
        )
    }

    nonisolated static func agendaSummaryItems(
        contextualItems: [UpcomingItem],
        queueItems: [UpcomingItem]
    ) -> [UpcomingItem] {
        var seenKeys: Set<String> = []
        return (contextualItems + queueItems).filter { item in
            seenKeys.insert(item.notificationKey).inserted
        }
    }

    nonisolated static func agendaSummaryPersonalizedContext(
        for item: UpcomingItem,
        previewKind: ContextualPreviewKind?
    ) -> String? {
        if let match = item.footballMatch {
            let score = match.hasVisibleScore
                ? "; score \(match.homeScore)-\(match.awayScore)"
                : ""
            return "Personalized football preview: \(match.homeTeam.name) vs "
                + "\(match.awayTeam.name); \(match.statusText)\(score)."
        }

        switch previewKind {
        case let .location(locationText):
            return "Personalized location and map preview for \(locationText)."
        case let .attendees(organizer, attendees):
            let responseOrder: [MeetingAttendeeResponse] = [
                .accepted,
                .tentative,
                .declined,
                .pending,
            ]
            let responseSummary = responseOrder.compactMap { response -> String? in
                let count = attendees.filter { $0.response == response }.count
                return count > 0 ? "\(count) \(response.rawValue)" : nil
            }.joined(separator: ", ")
            let organizerText = organizer == nil ? "" : " organizer available;"
            return "Personalized attendee preview:\(organizerText) \(attendees.count) attendees"
                + (responseSummary.isEmpty ? "." : " (\(responseSummary)).")
        case let .daylight(moment):
            return "Personalized daylight preview for \(moment.rawValue)."
        case nil:
            return nil
        }
    }

    func agendaSummarySection(snapshot: LayoutSnapshot) -> some View {
        calendarSectionContainer {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "text.append")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("Agenda Summary")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    if monitor.agendaSummaryState == .idle || monitor.agendaSummaryState == .loading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Summarizing your schedule")
                    }
                }

                switch monitor.agendaSummaryState {
                case .idle, .loading:
                    Text("Reviewing your upcoming schedule…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .ready(let summary):
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                case .unavailable:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.18), value: monitor.agendaSummaryState)
        }
    }
}
