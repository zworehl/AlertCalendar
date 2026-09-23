import Foundation
import SwiftUI

extension MenuContentView {
    struct BirthdayGroup: Identifiable {
        let id: String
        let date: Date
        let items: [UpcomingItem]
    }

    enum UpcomingQueueEntry: Identifiable {
        case item(UpcomingItem)
        case birthdayGroup(BirthdayGroup)

        var id: String {
            switch self {
            case .item(let item):
                return "item|\(item.notificationKey)"
            case .birthdayGroup(let group):
                return group.id
            }
        }
    }

    nonisolated static func upcomingQueueEntries(
        from items: [UpcomingItem],
        birthdayCalendarIDs: Set<String>,
        calendar: Calendar = .current
    ) -> [UpcomingQueueEntry] {
        var birthdayItemsByDay: [Date: [UpcomingItem]] = [:]

        for item in items where isBirthdayItem(item, birthdayCalendarIDs: birthdayCalendarIDs) {
            birthdayItemsByDay[calendar.startOfDay(for: item.date), default: []].append(item)
        }

        var emittedBirthdayDays: Set<Date> = []
        var entries: [UpcomingQueueEntry] = []
        entries.reserveCapacity(items.count)

        for item in items {
            let day = calendar.startOfDay(for: item.date)
            guard isBirthdayItem(item, birthdayCalendarIDs: birthdayCalendarIDs),
                  let birthdayItems = birthdayItemsByDay[day],
                  birthdayItems.count > 1 else {
                entries.append(.item(item))
                continue
            }

            guard emittedBirthdayDays.insert(day).inserted else { continue }
            entries.append(
                .birthdayGroup(
                    BirthdayGroup(
                        id: "birthday-group|\(day.timeIntervalSinceReferenceDate)",
                        date: day,
                        items: birthdayItems
                    )
                )
            )
        }

        return entries
    }

    nonisolated static func isBirthdayItem(
        _ item: UpcomingItem,
        birthdayCalendarIDs: Set<String>
    ) -> Bool {
        guard item.kind == .event, let calendarID = item.calendarID else { return false }
        return birthdayCalendarIDs.contains(calendarID)
    }

    nonisolated static func birthdayGroupTitle(itemCount: Int) -> String {
        itemCount == 1 ? "1 birthday" : "\(itemCount) birthdays"
    }

    nonisolated static func birthdayGroupNames(_ group: BirthdayGroup) -> String {
        group.items.map(\.title).joined(separator: " · ")
    }

    nonisolated static func compactBirthdayTitle(_ title: String) -> String {
        EventTitlePresentationResolver.birthdayName(from: title)
    }

    nonisolated static func birthdayGroupShowsChevron(isHovered: Bool) -> Bool {
        isHovered
    }

    nonisolated static func birthdayGroupTimingText(
        startDate: Date,
        endDate: Date?,
        now: Date,
        simplified: Bool,
        calendar: Calendar = .current
    ) -> String {
        CalendarMonitor.allDayLabel(
            startDate: startDate,
            endDate: endDate,
            now: now,
            simplified: simplified,
            calendar: calendar
        )
    }

    func birthdayGroupRows(_ group: BirthdayGroup) -> AnyView {
        let isExpanded = expandedBirthdayGroupIDs.contains(group.id)

        return AnyView(
            VStack(spacing: 0) {
                birthdayGroupRow(group, isExpanded: isExpanded)

                if isExpanded {
                    birthdayExpandedItemsBar(group)
                    .padding(.top, 4)
                    .padding(.leading, 20)
                    .padding(.bottom, 4)
                }
            }
        )
    }

    func birthdayExpandedItemsBar(_ group: BirthdayGroup) -> AnyView {
        AnyView(
            VStack(spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.notificationKey) { index, item in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 8)
                    }

                    birthdayExpandedItemRow(item)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        )
    }

    func birthdayExpandedItemRow(_ item: UpcomingItem) -> some View {
        return MenuContentHoverContainer { isHovered in
            HStack(alignment: .center, spacing: 8) {
                Text(settings.useEventTitleEllipsis && settings.useRewrittenEventTitlesInDropdown
                     ? (EventBirthdayTitle.parse(item.title, knownBirthday: true)?
                        .compactName(maximumCharacters: settings.eventTitleMaxCharacters) ?? item.title) : item.title)
                    .font(MenuMarkerMetrics.rowTitleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(item.title)
                    .accessibilityLabel(item.title)

                Spacer(minLength: 8)

                if isHovered {
                    skipActionButton(for: item)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .menuRowHoverBackground(isHovered: isHovered, cornerRadius: 0)
            .contentShape(Rectangle())
        }
    }

    func birthdayGroupRow(
        _ group: BirthdayGroup,
        isExpanded: Bool
    ) -> some View {
        let timingText = Self.birthdayGroupTimingText(
            startDate: group.date,
            endDate: group.items.first?.endDate,
            now: displayReferenceDate,
            simplified: settings.useSimplifiedCountdown
        )

        return MenuContentHoverContainer { isHovered in
            Button {
                if isExpanded {
                    expandedBirthdayGroupIDs.remove(group.id)
                } else {
                    expandedBirthdayGroupIDs.insert(group.id)
                }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "gift.circle.fill")
                        .font(.system(size: MenuMarkerMetrics.symbolSize, weight: .regular))
                        .frame(width: MenuMarkerMetrics.symbolSize, height: MenuMarkerMetrics.symbolSize)
                        .foregroundStyle(Color(nsColor: group.items[0].calendarColor.nsColor))

                    Text(Self.birthdayGroupTitle(itemCount: group.items.count))
                        .font(MenuMarkerMetrics.rowTitleFont)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    if Self.birthdayGroupShowsChevron(isHovered: isHovered) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 10, height: 12)
                    } else {
                        Text(timingText)
                            .font(MenuMarkerMetrics.rowDetailFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .menuRowHoverBackground(isHovered: isHovered)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide birthdays" : "Show birthdays")
            .accessibilityLabel(
                "\(Self.birthdayGroupTitle(itemCount: group.items.count)): \(Self.birthdayGroupNames(group))"
            )
        }
    }
}
