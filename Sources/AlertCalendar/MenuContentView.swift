import AppKit
import CoreLocation
import MapKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var monitor: CalendarMonitor
    @Environment(\.openWindow) private var openWindow
    let kindFilter: CalendarItemKind?
    let headerTitle: String

    @AppStorage(DefaultsKeys.alertLeadMinutes) private var alertLeadMinutes = 5
    @AppStorage(DefaultsKeys.lookAheadHours) private var dropdownTimeWindowHours = 24
    @AppStorage(DefaultsKeys.maxListItems) private var maxListItems = 8
    @State private var hoveredReminderItemID: String?
    @State private var hoveredActionRowKey: String?
    @State private var splitActionsSectionHeight: CGFloat = 0
    private let upcomingListMaxHeight: CGFloat = 360
    private let splitActionsColumnWidth: CGFloat = 484
    private let splitQueueColumnWidth: CGFloat = 396

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView

            if !shouldUseSplitDropdownLayout && !filteredAlertDescriptions.isEmpty {
                alertBannerSection
            }

            if shouldUseSplitDropdownLayout {
                HStack(alignment: .top, spacing: 12) {
                    contextualActionSection
                        .frame(width: splitActionsColumnWidth, alignment: .topLeading)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: SplitDropdownSectionHeightPreferenceKey.self,
                                    value: proxy.size.height
                                )
                            }
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        if !filteredAlertDescriptions.isEmpty {
                            alertBannerSection
                        }

                        upcomingSection
                    }
                        .frame(width: splitQueueColumnWidth, alignment: .topLeading)
                        .frame(minHeight: splitActionsSectionHeight, alignment: .topLeading)
                }
            } else {
                if !contextualActionItems.isEmpty {
                    contextualActionSection
                }

                upcomingSection
            }

            HStack {
                if monitor.hasSkippedItems() {
                    Button("Restore Skipped") {
                        monitor.restoreSkippedItems()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if shouldShowSilenceButton {
                    Button("Silence Alert") {
                        monitor.silenceCurrentAlert()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: dropdownWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: alertLeadMinutes) { _ in
            monitor.refreshNow()
        }
        .onPreferenceChange(SplitDropdownSectionHeightPreferenceKey.self) { height in
            guard abs(splitActionsSectionHeight - height) > 0.5 else { return }
            splitActionsSectionHeight = height
        }
    }

    private var alertBannerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(filteredAlertDescriptions, id: \.self) { alertText in
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 20, height: 20, alignment: .center)

                    Text(alertText)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.10))
        )
    }

    private var headerView: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.headerDateFormatter.string(from: Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(headerTitle)
                    .font(.title3.weight(.semibold))
            }

            Spacer()

            Button {
                monitor.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh")

            Button {
                DispatchQueue.main.async {
                    let appDelegate = NSApp.delegate as? AppDelegate
                    appDelegate?.prepareForSettingsPresentation()
                    openWindow(id: WindowMetadata.preferencesID)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if appDelegate?.revealSettingsWindowIfPresent() != true {
                            appDelegate?.showSettingsWindow(monitor: monitor)
                        }
                    }
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
    }

    private func calendarSectionContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var dropdownWidth: CGFloat {
        shouldUseSplitDropdownLayout ? 916 : 520
    }

    private var shouldUseSplitDropdownLayout: Bool {
        guard !queueItemsForActions.isEmpty else { return false }
        if contextualActionItems.count > 1 {
            return true
        }
        return contextualActionItems.count == 1 && contextualActionItems.first?.footballMatch != nil
    }

    private var sharedContextualFootballMatches: [FootballFixtureMatch]? {
        guard !contextualActionItems.isEmpty else { return nil }

        let footballMatches = contextualActionItems.compactMap(\.footballMatch)
        guard footballMatches.count == contextualActionItems.count else { return nil }

        return footballMatches
    }

    private var sharedContextualFootballCompetitionTitle: String? {
        guard let sharedContextualFootballMatches else { return nil }
        return FootballFixtureFormatter.sharedCompetitionTitle(for: sharedContextualFootballMatches)
    }

    private var sharedContextualFootballCompetitionLogoPath: String? {
        guard sharedContextualFootballCompetitionTitle != nil else { return nil }
        return contextualActionItems.first?.footballMenuBarDisplay?.competitionLocalLogoPath
    }

    private var sharedContextualFootballCompetitionLogoURL: URL? {
        guard let sharedContextualFootballMatches,
              sharedContextualFootballCompetitionTitle != nil else {
            return nil
        }

        return sharedContextualFootballMatches.first?.competitionLogoURL
    }

    private var contextualSharedCompetitionHeader: some View {
        HStack(spacing: 6) {
            FootballCompetitionLogoView(
                localPath: sharedContextualFootballCompetitionLogoPath,
                remoteURL: sharedContextualFootballCompetitionLogoURL,
                placeholderSymbolSize: 11
            )

            Text("All listed matches are from \(sharedContextualFootballCompetitionTitle ?? "")")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var contextualSharedCompetitionIsActive: Bool {
        sharedContextualFootballCompetitionTitle != nil
    }

    private enum FootballContextualContentLevel {
        case statsAndGoals
        case goalsOnly
        case compact

        var showsStats: Bool {
            switch self {
            case .statsAndGoals:
                return true
            case .goalsOnly, .compact:
                return false
            }
        }

        var showsGoalScorers: Bool {
            switch self {
            case .statsAndGoals, .goalsOnly:
                return true
            case .compact:
                return false
            }
        }
    }

    private var contextualFootballContentLevel: FootballContextualContentLevel {
        Self.contextualFootballContentLevel(for: contextualActionItems.count)
    }

    private static func contextualFootballContentLevel(for itemCount: Int) -> FootballContextualContentLevel {
        switch max(1, itemCount) {
        case 1:
            return .statsAndGoals
        case 2:
            return .goalsOnly
        default:
            return .compact
        }
    }

    private var contextualActionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            calendarSectionContainer {
                VStack(alignment: .leading, spacing: 8) {
                    if contextualSharedCompetitionIsActive {
                        contextualSharedCompetitionHeader
                    }

                    ForEach(Array(contextualActionItems.enumerated()), id: \.element.notificationKey) { index, item in
                        contextualActionCard(
                            for: item,
                            showsFootballCompetitionLine: !contextualSharedCompetitionIsActive
                        )

                        if index < contextualActionItems.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("UPCOMING")
            calendarSectionContainer {
                if queueItemsForActions.isEmpty {
                    emptySectionRow("No upcoming items")
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            ForEach(Array(queueItemsForActions.enumerated()), id: \.element.notificationKey) { index, item in
                                if index > 0 {
                                    Divider()
                                }
                                actionRow(item: item, actions: [.skip])
                            }
                        }
                    }
                    .frame(
                        maxHeight: shouldUseSplitDropdownLayout ? .infinity : upcomingListMaxHeight,
                        alignment: .top
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: shouldUseSplitDropdownLayout ? .infinity : nil,
                alignment: .topLeading
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: shouldUseSplitDropdownLayout ? .infinity : nil,
            alignment: .topLeading
        )
    }

    private var filteredAlertDescriptions: [String] {
        let now = Date()
        let leadSeconds = TimeInterval(max(1, alertLeadMinutes) * 60)
        let items = monitor.upcomingItems.filter { item in
            guard AstronomyMoment(eventTitle: item.title) == nil else { return false }
            if let kindFilter, item.kind != kindFilter {
                return false
            }
            let remaining = item.date.timeIntervalSince(now)
            return remaining > 0 && remaining <= leadSeconds
        }

        return items.map { item in
            let seconds = max(0, Int(item.date.timeIntervalSince(now)))
            if seconds < 60 {
                return "\(item.title) starts in \(seconds)s."
            }
            let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))
            return "\(item.title) starts in \(minutes) minute\(minutes == 1 ? "" : "s")."
        }
    }

    private var shouldShowSilenceButton: Bool {
        guard let activeAlertItem = monitor.activeAlertItem else { return false }
        guard let kindFilter else { return true }
        return activeAlertItem.kind == kindFilter
    }

    private var allEventItemsForContextualActions: [UpcomingItem] {
        let now = Date()
        let allDayItems = monitor.allDayEventItems
        let timedItems = monitor.upcomingItems.filter {
            $0.kind == .event && Self.shouldIncludeInDropdownTimeWindow(
                $0,
                now: now,
                futureWindowEnd: dropdownFutureWindowEnd(now: now)
            )
        }
        return deduplicatedItems((allDayItems + timedItems).sorted { $0.date < $1.date })
    }

    private var queueItemsForActions: [UpcomingItem] {
        let now = Date()
        let allDayItems = monitor.allDayEventItems
        let timedItems = monitor.upcomingItems.filter {
            ($0.kind == .event || $0.kind == .reminder) && Self.shouldIncludeInDropdownTimeWindow(
                $0,
                now: now,
                futureWindowEnd: dropdownFutureWindowEnd(now: now)
            )
        }
        let combined = deduplicatedItems((allDayItems + timedItems).sorted { $0.date < $1.date })
        return Self.queueItemsForActions(
            from: combined,
            contextualItems: contextualActionItems,
            now: now,
            futureWindowEnd: dropdownFutureWindowEnd(now: now),
            maxItems: max(1, maxListItems)
        )
    }

    private func dropdownFutureWindowEnd(now: Date) -> Date {
        now.addingTimeInterval(Double(max(1, dropdownTimeWindowHours)) * 3600)
    }

    nonisolated static func queueItemsForActions(
        from items: [UpcomingItem],
        contextualItems: [UpcomingItem],
        now: Date,
        futureWindowEnd: Date,
        maxItems: Int
    ) -> [UpcomingItem] {
        let contextualFootballMatchIDs = Set(contextualItems.compactMap { $0.footballMatch?.id })
        let filtered = items.filter { item in
            shouldIncludeInUpcomingQueue(
                item,
                contextualFootballMatchIDs: contextualFootballMatchIDs,
                now: now,
                futureWindowEnd: futureWindowEnd
            )
        }
        return Array(filtered.prefix(max(1, maxItems)))
    }

    nonisolated static func shouldIncludeInDropdownTimeWindow(
        _ item: UpcomingItem,
        now: Date,
        futureWindowEnd: Date
    ) -> Bool {
        if item.isAllDay {
            return true
        }

        if item.kind == .reminder, item.date <= now {
            return true
        }

        if item.kind == .event,
           let endDate = item.endDate,
           item.date <= now,
           endDate > now {
            return true
        }

        return item.date >= now && item.date <= futureWindowEnd
    }

    nonisolated static func shouldIncludeInUpcomingQueue(
        _ item: UpcomingItem,
        contextualFootballMatchIDs: Set<String>,
        now: Date,
        futureWindowEnd: Date
    ) -> Bool {
        guard shouldIncludeInDropdownTimeWindow(item, now: now, futureWindowEnd: futureWindowEnd) else {
            return false
        }

        guard let footballMatch = item.footballMatch else {
            return true
        }

        if contextualFootballMatchIDs.contains(footballMatch.id) {
            return false
        }

        if footballMatch.statusState == .inProgress || item.date <= now {
            return false
        }

        return true
    }

    private func deduplicatedItems(_ items: [UpcomingItem]) -> [UpcomingItem] {
        var seen: Set<String> = []
        var unique: [UpcomingItem] = []
        unique.reserveCapacity(items.count)

        for item in items {
            if seen.insert(item.notificationKey).inserted {
                unique.append(item)
            }
        }
        return unique
    }

    private enum MenuAction {
        case skip
        case complete
    }

    @ViewBuilder
    private func actionRow(item: UpcomingItem, actions: [MenuAction]) -> some View {
        let isHovered = hoveredActionRowKey == item.notificationKey
        ZStack(alignment: .trailing) {
            if item.kind == .reminder {
                Button {
                    monitor.markReminderCompleted(item)
                } label: {
                    rowPrimaryContent(for: item, hideTimeDetails: isHovered)
                }
                .buttonStyle(.plain)
            } else {
                rowPrimaryContent(for: item, hideTimeDetails: isHovered)
            }

            if isHovered {
                HStack(spacing: 4) {
                    if let meetingURL = item.meetingURL {
                        Button {
                            NSWorkspace.shared.open(meetingURL)
                        } label: {
                            actionPill {
                                HStack(spacing: 4) {
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Join")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Join")
                    }

                    ForEach(actions.indices, id: \.self) { index in
                        switch actions[index] {
                        case .skip:
                            Button {
                                monitor.skipItem(item)
                            } label: {
                                actionPill {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .frame(width: 12, height: 12)
                                }
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .help("Skip")
                        case .complete:
                            Button {
                                monitor.markReminderCompleted(item)
                            } label: {
                                reminderCompletionActionLabel(color: Color(nsColor: item.calendarColor))
                            }
                            .buttonStyle(.plain)
                            .controlSize(.small)
                            .help("Complete")
                        }
                    }
                }
                .frame(minWidth: 30, alignment: .trailing)
                .padding(.trailing, 2)
            }
        }
        .font(.caption)
        .padding(.vertical, 0)
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredActionRowKey = isHovering ? item.notificationKey : nil
            if item.kind == .reminder {
                hoveredReminderItemID = isHovering ? item.id : nil
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
    }

    private func emptySectionRow(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func timeRangeText(for item: UpcomingItem) -> String? {
        guard !item.isAllDay else { return nil }
        let startText = Self.menuTimeFormatter.string(from: item.date)
        guard let endDate = item.endDate, endDate > item.date else {
            return startText
        }
        let endText = Self.menuTimeFormatter.string(from: endDate)
        return "\(startText)-\(endText)"
    }

    @ViewBuilder
    private func actionPill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(height: 18)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                    )
            )
    }

    private func reminderCompletionActionLabel(color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.92), lineWidth: 1.6)

            Circle()
                .fill(color.opacity(0.10))
                .padding(3)

            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color.opacity(0.92))
        }
        .frame(width: 18, height: 18)
    }

    private static let menuTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        return formatter
    }()

    private func timeText(_ date: Date) -> String {
        Self.menuTimeFormatter.string(from: date)
    }

    private func eventTravelStartDate(for item: UpcomingItem) -> Date? {
        guard let travelMinutes = item.travelTimeMinutes, travelMinutes > 0 else { return nil }
        return item.date.addingTimeInterval(TimeInterval(-travelMinutes * 60))
    }

    private func displayLocationName(from rawLocation: String) -> String {
        let trimmed = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return rawLocation }

        let primary = trimmed
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? trimmed

        return primary.isEmpty ? trimmed : primary
    }

    private func shouldShowLocationRow(locationName: String, meetingURL: URL?) -> Bool {
        let normalizedLocation = locationName.lowercased()
        guard !normalizedLocation.isEmpty else { return false }

        // Keep virtual labels/links out of the physical location row.
        if monitor.isVirtualLocationText(locationName) {
            return false
        }

        guard let meetingURL else { return true }

        if normalizedLocation.contains("microsoft teams"),
           meetingServiceName(for: meetingURL) == "Microsoft Teams" {
            return false
        }

        return true
    }

    @ViewBuilder
    private func rowPrimaryContent(for item: UpcomingItem, hideTimeDetails: Bool = false) -> some View {
        let accentColor = Color(nsColor: item.calendarColor)
        let titleColor: Color = .primary
        let detailTextColor: Color = .secondary
        let tertiaryTextColor: Color = .secondary.opacity(0.85)
        let titleFont = Font.system(size: 12, weight: .semibold)
        let detailFont = Font.system(size: 11, weight: .medium)
        let detailIconFont = Font.system(size: 12, weight: .regular)
        let hasVirtualLocation = monitor.isVirtualLocationText(item.locationText)
        let usesEventStyleLayout = item.kind == .event
        let showTravelTime = item.kind == .event
            && !item.isAllDay
            && item.meetingURL == nil
            && !hasVirtualLocation
            && (item.travelTimeMinutes ?? 0) > 0
        let allDayRightLabel = monitor.allDayLabel(for: item)
        let showRightTimeColumn = usesEventStyleLayout && (!item.isAllDay || allDayRightLabel != nil)
        let textBlock = HStack(alignment: .top, spacing: 8) {
            if let markerSymbol = markerSymbolName(for: item) {
                Image(systemName: markerSymbol)
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 12, height: 12)
                    .foregroundStyle(accentColor)
                    .padding(.top, markerTopPadding(for: item))
            } else if let image = markerImage(for: item) {
                let markerSize = markerImageSize(for: item)
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: markerSize.width, height: markerSize.height)
                    .padding(.top, markerTopPadding(for: item))
            } else {
                Capsule()
                    .fill(Color(nsColor: item.calendarColor))
                    .frame(width: 4)
                    .padding(.vertical, 1)
            }

            if usesEventStyleLayout {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let footballMatch = item.footballMatch {
                            footballEventTextBlock(
                                item: item,
                                match: footballMatch,
                                accentColor: accentColor,
                                titleFont: titleFont,
                                detailFont: detailFont,
                                detailIconFont: detailIconFont,
                                detailTextColor: detailTextColor
                            )
                        } else {
                            if showTravelTime, let travelMinutes = item.travelTimeMinutes {
                                HStack(alignment: .center, spacing: 4) {
                                    Image(systemName: "car.fill")
                                        .font(detailIconFont)
                                        .frame(width: 12, height: 12, alignment: .center)
                                        .foregroundStyle(accentColor)
                                    Text("\(travelMinutes) min travel time")
                                        .font(detailFont)
                                        .foregroundStyle(detailTextColor)
                                }
                            }

                            Text(item.title)
                                .font(titleFont)
                                .foregroundStyle(titleColor)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            if !item.isAllDay, let locationText = item.locationText {
                                let locationName = displayLocationName(from: locationText)
                                if shouldShowLocationRow(locationName: locationName, meetingURL: item.meetingURL) {
                                    HStack(alignment: .center, spacing: 4) {
                                        Image(systemName: locationSymbolName(for: item))
                                            .font(detailIconFont)
                                            .frame(width: 12, height: 12, alignment: .center)
                                            .foregroundStyle(accentColor)
                                        Text(locationName)
                                            .font(detailFont)
                                            .foregroundStyle(detailTextColor)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                            }

                            if let meetingURL = item.meetingURL {
                                HStack(alignment: .center, spacing: 4) {
                                    Image(systemName: "video")
                                        .font(detailIconFont)
                                        .frame(width: 12, height: 12, alignment: .center)
                                        .foregroundStyle(accentColor)
                                    Text(meetingServiceName(for: meetingURL))
                                        .font(detailFont)
                                        .foregroundStyle(detailTextColor)
                                }
                            }
                        }
                    }

                    if showRightTimeColumn && !hideTimeDetails {
                        Spacer(minLength: 6)

                        VStack(alignment: .trailing, spacing: 0) {
                            if showTravelTime, let travelStart = eventTravelStartDate(for: item) {
                                Text(timeText(travelStart))
                                    .font(detailFont)
                                    .foregroundStyle(tertiaryTextColor)
                            }

                            if item.isAllDay {
                                if let allDayRightLabel {
                                    Text(allDayRightLabel)
                                        .font(detailFont)
                                        .foregroundStyle(detailTextColor)
                                }
                            } else {
                                Text(timeText(item.date))
                                    .font(detailFont)
                                    .foregroundStyle(detailTextColor)
                            }

                            if !item.isAllDay, let endDate = item.endDate, endDate > item.date {
                                Text(timeText(endDate))
                                    .font(detailFont)
                                    .foregroundStyle(tertiaryTextColor)
                            }
                        }
                    }
                }
            } else {
                if item.kind == .reminder {
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.title)
                                .font(titleFont)
                                .foregroundStyle(titleColor)

                            if !item.isAllDay, let locationText = item.locationText {
                                let locationName = displayLocationName(from: locationText)
                                if shouldShowLocationRow(locationName: locationName, meetingURL: item.meetingURL) {
                                    HStack(alignment: .center, spacing: 4) {
                                        Image(systemName: locationSymbolName(for: item))
                                            .font(detailIconFont)
                                            .frame(width: 12, height: 12, alignment: .center)
                                            .foregroundStyle(accentColor)
                                        Text(locationName)
                                            .font(detailFont)
                                            .foregroundStyle(detailTextColor)
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }

                            if let meetingURL = item.meetingURL {
                                HStack(alignment: .center, spacing: 4) {
                                    Image(systemName: "video")
                                        .font(detailIconFont)
                                        .frame(width: 12, height: 12, alignment: .center)
                                        .foregroundStyle(accentColor)
                                    Text(meetingServiceName(for: meetingURL))
                                        .font(detailFont)
                                        .foregroundStyle(detailTextColor)
                                }
                            }
                        }

                        Spacer(minLength: 4)

                        if !hideTimeDetails {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(timeText(item.date))
                                    .font(detailFont)
                                    .foregroundStyle(detailTextColor)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.title)
                            .font(titleFont)
                            .foregroundStyle(titleColor)

                            if !hideTimeDetails,
                               let detailTime = timeRangeText(for: item) {
                            HStack(alignment: .center, spacing: 4) {
                                Image(systemName: "clock")
                                    .font(detailIconFont)
                                    .frame(width: 12, height: 12, alignment: .center)
                                    .foregroundStyle(accentColor)
                                Text(detailTime)
                                    .font(detailFont)
                                    .foregroundStyle(detailTextColor)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            let now = Date()
            let settings = monitor.snapshotSettings()
            let visual = monitor.segmentBackgroundVisual(for: item, now: now, settings: settings)

            if hoveredActionRowKey == item.notificationKey {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.10))
            }

            if visual.color.alphaComponent > 0.01 {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: visual.color).opacity(0.08))
            }
        }
        .overlay(alignment: .leading) {
            let now = Date()
            let settings = monitor.snapshotSettings()
            if let progress = monitor.activeEventProgress(for: item, now: now, settings: settings), progress > 0 {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: item.calendarColor).opacity(0.22))
                        .frame(width: max(10, proxy.size.width * progress))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))

        textBlock
    }

    @ViewBuilder
    private func footballEventTextBlock(
        item: UpcomingItem,
        match: FootballFixtureMatch,
        accentColor: Color,
        titleFont: Font,
        detailFont: Font,
        detailIconFont: Font,
        detailTextColor: Color
    ) -> some View {
        footballFixtureHeadline(
            match: match,
            display: item.footballMenuBarDisplay,
            font: titleFont,
            showsCardBadges: false,
            showsStatusAccessories: false
        )

        if !item.isAllDay, let locationText = item.locationText {
            let locationName = displayLocationName(from: locationText)
            if shouldShowLocationRow(locationName: locationName, meetingURL: item.meetingURL) {
                HStack(alignment: .center, spacing: 4) {
                    Image(systemName: locationSymbolName(for: item))
                        .font(detailIconFont)
                        .frame(width: 12, height: 12, alignment: .center)
                        .foregroundStyle(accentColor)
                    Text(locationName)
                        .font(detailFont)
                        .foregroundStyle(detailTextColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    @ViewBuilder
    private func footballCompetitionLine(
        match: FootballFixtureMatch,
        display: FootballMenuBarDisplay?,
        font: Font
    ) -> some View {
        HStack(alignment: .center, spacing: 4) {
            FootballCompetitionLogoView(
                localPath: display?.competitionLocalLogoPath,
                remoteURL: match.competitionLogoURL,
                placeholderSymbolSize: 11
            )

            Text(footballCompetitionDetailText(match: match, display: display))
                .font(font)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private func footballFixtureHeadline(
        match: FootballFixtureMatch,
        display: FootballMenuBarDisplay?,
        font: Font,
        showsCardBadges: Bool,
        showsStatusAccessories: Bool
    ) -> some View {
        let accessories = FootballStatusAccessoriesView.accessories(for: match)

        HStack(alignment: .center, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                footballTeamLabel(
                    abbreviation: display?.homeAbbreviation ?? FootballFixtureFormatter.teamDisplayIdentifier(for: match.homeTeam),
                    localLogoPath: display?.homeLocalLogoPath,
                    remoteLogoURL: FootballFixtureFormatter.isUnknownTeam(match.homeTeam) ? nil : match.homeTeam.logoURL,
                    isUnknown: FootballFixtureFormatter.isUnknownTeam(match.homeTeam),
                    logoLeading: false,
                    yellowCards: match.homeYellowCards,
                    redCards: match.homeRedCards,
                    showsCardBadges: showsCardBadges,
                    font: font
                )

                if match.hasVisibleScore {
                    HStack(spacing: 0) {
                        Text(FootballFixtureFormatter.scoreText(match.homeScore))
                            .frame(minWidth: 10, alignment: .center)

                        Text("-")
                            .foregroundStyle(.secondary)

                        Text(FootballFixtureFormatter.scoreText(match.awayScore))
                            .frame(minWidth: 10, alignment: .center)
                    }
                } else {
                    Text("-")
                        .foregroundStyle(.secondary)
                }

                footballTeamLabel(
                    abbreviation: display?.awayAbbreviation ?? FootballFixtureFormatter.teamDisplayIdentifier(for: match.awayTeam),
                    localLogoPath: display?.awayLocalLogoPath,
                    remoteLogoURL: FootballFixtureFormatter.isUnknownTeam(match.awayTeam) ? nil : match.awayTeam.logoURL,
                    isUnknown: FootballFixtureFormatter.isUnknownTeam(match.awayTeam),
                    logoLeading: true,
                    yellowCards: match.awayYellowCards,
                    redCards: match.awayRedCards,
                    showsCardBadges: showsCardBadges,
                    font: font
                )
            }
            .fixedSize(horizontal: true, vertical: false)

            if showsStatusAccessories && accessories.hasAccessories {
                FootballStatusAccessoriesView(data: accessories)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .font(font)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func footballTeamLabel(
        abbreviation: String,
        localLogoPath: String?,
        remoteLogoURL: URL?,
        isUnknown: Bool,
        logoLeading: Bool,
        yellowCards: Int,
        redCards: Int,
        showsCardBadges: Bool,
        font: Font
    ) -> some View {
        HStack(spacing: 4) {
            if showsCardBadges && !logoLeading {
                footballCardBadges(yellowCards: yellowCards, redCards: redCards)
            }

            if logoLeading {
                FootballTeamLogoView(
                    localPath: localLogoPath,
                    remoteURL: remoteLogoURL,
                    isUnknown: isUnknown
                )
                Text(abbreviation)
                    .font(font)
            } else {
                Text(abbreviation)
                    .font(font)
                FootballTeamLogoView(
                    localPath: localLogoPath,
                    remoteURL: remoteLogoURL,
                    isUnknown: isUnknown
                )
            }

            if showsCardBadges && logoLeading {
                footballCardBadges(yellowCards: yellowCards, redCards: redCards)
            }
        }
    }

    @ViewBuilder
    private func footballCardBadges(yellowCards: Int, redCards: Int) -> some View {
        if yellowCards > 0 || redCards > 0 {
            HStack(spacing: 3) {
                if yellowCards > 0 {
                    footballCardBadge(count: yellowCards, tint: Color(red: 0.95, green: 0.79, blue: 0.26))
                }
                if redCards > 0 {
                    footballCardBadge(count: redCards, tint: Color(red: 0.88, green: 0.24, blue: 0.21))
                }
            }
        }
    }

    private func footballCardBadge(count: Int, tint: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(tint)
                .frame(width: 7, height: 10)

            if count != 1 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func footballCompetitionDetailText(match: FootballFixtureMatch, display: FootballMenuBarDisplay?) -> String {
        FootballFixtureFormatter.competitionDetailText(for: match, display: display)
    }

    private func locationSymbolName(for item: UpcomingItem) -> String {
        item.footballMatch == nil ? "mappin.circle" : FootballFixtureFormatter.footballLocationSymbolName
    }

    private func footballContextualVenueName(for item: UpcomingItem, match: FootballFixtureMatch) -> String? {
        let rawLocation = item.locationText ?? match.locationText
        guard let rawLocation else { return nil }

        let locationName = displayLocationName(from: rawLocation)
        guard shouldShowLocationRow(locationName: locationName, meetingURL: item.meetingURL) else {
            return nil
        }

        return locationName
    }

    nonisolated static func footballContextualScheduleText(
        for match: FootballFixtureMatch,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        guard match.statusState == .scheduled, match.startDate > now, !match.hasInterruptedStatus else {
            return nil
        }

        return CalendarMonitor.footballScheduleText(
            for: match,
            now: now,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
    }

    private func markerImage(for item: UpcomingItem) -> NSImage? {
        if item.kind == .reminder {
            return reminderMarkerImage(
                color: item.calendarColor,
                isFilled: hoveredReminderItemID == item.id
            )
        }
        guard let moment = AstronomyMoment(eventTitle: item.title) else { return nil }
        return astronomyMarkerImage(for: moment)
    }

    private func reminderMarkerImage(color: NSColor, isFilled: Bool) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        if isFilled {
            let filledCircle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.9, dy: 0.9))
            color.withAlphaComponent(0.95).setFill()
            filledCircle.fill()

            let checkPath = NSBezierPath()
            checkPath.lineWidth = 1.55
            checkPath.lineCapStyle = .round
            checkPath.lineJoinStyle = .round
            checkPath.move(to: NSPoint(x: 3.2, y: 6.1))
            checkPath.line(to: NSPoint(x: 5.0, y: 7.9))
            checkPath.line(to: NSPoint(x: 8.6, y: 4.3))
            NSColor.white.withAlphaComponent(0.98).setStroke()
            checkPath.stroke()
        } else {
            let outerPath = NSBezierPath(ovalIn: rect.insetBy(dx: 0.9, dy: 0.9))
            outerPath.lineWidth = 1.6
            color.withAlphaComponent(0.82).setStroke()
            outerPath.stroke()
        }

        return image
    }

    private func markerSymbolName(for item: UpcomingItem) -> String? {
        if monitor.isBirthdayItem(item) {
            return "gift.circle.fill"
        }
        if item.kind == .event, item.isAllDay {
            return "calendar.circle.fill"
        }
        return nil
    }

    private func astronomyMarkerImage(for moment: AstronomyMoment) -> NSImage {
        if let image = AstronomyIconProvider.image(for: moment, pointSize: 13) {
            return image
        }
        return NSImage(size: NSSize(width: 16, height: 12))
    }

    private func markerTopPadding(for item: UpcomingItem) -> CGFloat {
        item.kind == .reminder ? 0 : 2
    }

    private func markerImageSize(for item: UpcomingItem) -> CGSize {
        if AstronomyMoment(eventTitle: item.title) != nil {
            return CGSize(width: 14, height: 14)
        }
        return CGSize(width: 12, height: 12)
    }

    private var contextualActionItems: [UpcomingItem] {
        let candidates = allEventItemsForContextualActions.filter { item in
            guard let locationText = locationTextForMenuBarItem(item) else { return false }
            return shouldShowPhysicalMap(for: item, locationText: locationText)
        }
        return Self.contextualActionItems(from: candidates, now: Date())
    }

    nonisolated static func contextualActionItems(
        from candidates: [UpcomingItem],
        now: Date,
        calendar: Calendar = .current
    ) -> [UpcomingItem] {
        let sortedCandidates = candidates.sorted { left, right in
            if left.date != right.date {
                return left.date < right.date
            }
            if left.kind != right.kind {
                return left.kind.rawValue < right.kind.rawValue
            }
            let titleOrder = left.title.localizedCaseInsensitiveCompare(right.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return left.notificationKey < right.notificationKey
        }

        let activeCandidates = sortedCandidates.filter { item in
            guard let endDate = item.endDate else { return false }
            return item.date <= now && endDate > now
        }
        if !activeCandidates.isEmpty {
            return activeCandidates
        }

        guard let anchor = sortedCandidates.first else { return [] }
        let concurrent = sortedCandidates.filter {
            calendar.isDate($0.date, equalTo: anchor.date, toGranularity: .minute)
        }
        return concurrent.isEmpty ? [anchor] : concurrent
    }

    private func meetingServiceName(for url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        let scheme = (url.scheme ?? "").lowercased()
        let absolute = url.absoluteString.lowercased()

        if host.contains("meet.google.") {
            return "Meet"
        }
        if host.contains("zoom.") || host.contains("us02web.zoom.") {
            return "Zoom"
        }
        if scheme == "msteams"
            || scheme == "microsoftteams"
            || host.contains("teams.")
            || host.contains("teams.microsoft.")
            || host.contains("teams.live.")
            || host.contains("teams.office.")
            || host.contains("aka.ms")
            || host.contains("microsoftteams.")
            || host.contains("teams.ms")
            || absolute.contains("meetup-join")
            || absolute.contains("teams.microsoft.com")
            || absolute.contains("teams.live.com")
            || absolute.contains("teams.office.com") {
            return "Microsoft Teams"
        }
        if host.contains("webex.") {
            return "Webex"
        }
        if host.contains("whereby.") {
            return "Whereby"
        }
        if host.contains("jitsi.") || host.contains("meet.jit.si") {
            return "Jitsi"
        }
        if host.contains("chime.aws") || host.contains("amazonchime.") {
            return "Amazon Chime"
        }

        return "Meeting Link"
    }

    private func mapURL(for locationText: String) -> URL? {
        guard let encoded = locationText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "http://maps.apple.com/?q=\(encoded)")
    }

    private func shouldShowPhysicalMap(for item: UpcomingItem, locationText: String?) -> Bool {
        guard item.meetingURL == nil else { return false }
        guard let locationText else { return false }
        return !monitor.isVirtualLocationText(locationText)
    }

    private func locationTextForMenuBarItem(_ item: UpcomingItem) -> String? {
        if let locationText = item.locationText {
            if monitor.isVirtualLocationText(locationText) {
                return nil
            }
            return locationText
        }
        return nil
    }

    @ViewBuilder
    private func contextualActionCard(
        for item: UpcomingItem,
        showsFootballCompetitionLine: Bool
    ) -> some View {
        let locationText = locationTextForMenuBarItem(item)
        let shouldShowMapForItem = shouldShowPhysicalMap(for: item, locationText: locationText)
        let locationPreviewHeight: CGFloat = shouldUseSplitDropdownLayout ? 90 : 100
        let footballContentLevel = contextualFootballContentLevel
        let now = Date()

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let footballMatch = item.footballMatch {
                    let scheduleText = Self.footballContextualScheduleText(for: footballMatch, now: now)
                    let venueName = footballContextualVenueName(for: item, match: footballMatch)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .top, spacing: 10) {
                            footballFixtureHeadline(
                                match: footballMatch,
                                display: item.footballMenuBarDisplay,
                                font: .subheadline.weight(.semibold),
                                showsCardBadges: true,
                                showsStatusAccessories: true
                            )
                        }

                        if let venueName {
                            HStack(alignment: .center, spacing: 4) {
                                Image(systemName: locationSymbolName(for: item))
                                    .font(.system(size: 12, weight: .regular))
                                    .frame(width: 12, height: 12, alignment: .center)
                                    .foregroundStyle(.secondary)

                                Text(venueName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer(minLength: 8)

                                if let scheduleText,
                                   !scheduleText.isEmpty {
                                    Text(scheduleText)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.trailing)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        } else if let scheduleText,
                                  !scheduleText.isEmpty {
                            HStack {
                                Spacer(minLength: 0)
                                Text(scheduleText)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }

                        if showsFootballCompetitionLine {
                            footballCompetitionLine(
                                match: footballMatch,
                                display: item.footballMenuBarDisplay,
                                font: .caption
                            )
                        }
                    }
                } else {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Button {
                        monitor.skipItem(item)
                    } label: {
                        Label("Skip", systemImage: "forward.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if shouldShowMapForItem,
                       let locationText,
                       let mapURL = mapURL(for: locationText) {
                        Button {
                            NSWorkspace.shared.open(mapURL)
                        } label: {
                            Label("Map", systemImage: "map")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            if shouldShowMapForItem,
               let locationText {
                MiniLocationMapView(
                    locationText: locationText,
                    preferredHeight: locationPreviewHeight
                )
                    .id("\(item.notificationKey)|\(locationText)")
            }

            if let footballMatch = item.footballMatch {
                if footballContentLevel.showsStats {
                    FootballMatchStatsSection(match: footballMatch)
                }

                if footballContentLevel.showsGoalScorers,
                   footballMatch.totalGoals > 0 {
                    FootballGoalScorersSection(match: footballMatch)
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MiniLocationMapView: View {
    let locationText: String
    let preferredHeight: CGFloat
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 18.4655, longitude: -66.1057),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @State private var marker: MapMarkerItem?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Location Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                if let marker {
                    Map(
                        coordinateRegion: $region,
                        annotationItems: [marker]
                    ) { item in
                        MapMarker(coordinate: item.coordinate, tint: .red)
                    }
                    .allowsHitTesting(false)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                    Text(isLoading ? "Loading map..." : "Map unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: preferredHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onAppear {
            resolveLocation()
        }
        .onChange(of: locationText) { _ in
            resolveLocation()
        }
    }

    private func resolveLocation() {
        let requestedLocation = locationText
        let trimmed = requestedLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            isLoading = false
            marker = nil
            return
        }

        isLoading = true
        Task {
            let coordinate = await LocationCoordinateResolver.shared.coordinate(for: requestedLocation)
            await MainActor.run {
                guard requestedLocation == locationText else { return }
                isLoading = false
                guard let coordinate else {
                    marker = nil
                    return
                }
                setMarker(at: coordinate.clCoordinate)
            }
        }
    }

    private func setMarker(at coordinate: CLLocationCoordinate2D) {
        marker = MapMarkerItem(coordinate: coordinate)
        region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    }
}

private struct FootballMatchStatsSection: View {
    @EnvironmentObject private var monitor: CalendarMonitor
    let match: FootballFixtureMatch

    @State private var statistics: [FootballMatchStatistic] = []
    @State private var isLoading = false
    @State private var hasAttemptedLoad = false
    @State private var loadTask: Task<Void, Never>?

    private var requestKey: String {
        let statusPeriod = match.statusPeriod.map(String.init) ?? "n/a"
        return "\(match.id)|\(match.homeScore)|\(match.awayScore)|\(match.statusText)|\(statusPeriod)"
    }

    var body: some View {
        Group {
            if match.statusState == .scheduled {
                EmptyView()
            } else if statistics.isEmpty && (!hasAttemptedLoad || isLoading) {
                FootballMatchStatsLoadingView()
            } else if !statistics.isEmpty {
                FootballMatchStatsView(stats: statistics)
            }
        }
        .onAppear {
            startLoadingStatistics()
        }
        .onChange(of: requestKey) { _ in
            startLoadingStatistics()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func startLoadingStatistics() {
        loadTask?.cancel()

        guard match.statusState != .scheduled else {
            statistics = []
            isLoading = false
            hasAttemptedLoad = true
            return
        }

        let currentRequestKey = requestKey
        let footballClient = monitor.footballClient
        let hadStatistics = !statistics.isEmpty
        isLoading = true
        if !hadStatistics {
            hasAttemptedLoad = false
        }

        loadTask = Task {
            do {
                let fetchedStatistics = try await footballClient.fetchMatchStatistics(for: match)
                await MainActor.run {
                    guard currentRequestKey == requestKey else { return }
                    statistics = fetchedStatistics
                    isLoading = false
                    hasAttemptedLoad = true
                }
            } catch {
                await MainActor.run {
                    guard currentRequestKey == requestKey else { return }
                    isLoading = false
                    hasAttemptedLoad = true
                }
            }
        }
    }
}

private struct FootballMatchStatsView: View {
    let stats: [FootballMatchStatistic]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Match Stats")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(stats) { stat in
                    HStack(spacing: 8) {
                        Text(stat.homeValue)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(stat.label.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(stat.awayValue)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )
                }
            }
        }
    }
}

private struct FootballMatchStatsLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Match Stats")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(0..<10, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 22)
                }
            }
        }
    }
}

private struct FootballGoalScorersSection: View {
    @EnvironmentObject private var monitor: CalendarMonitor
    let match: FootballFixtureMatch

    @State private var scorers: FootballMatchGoalScorers?
    @State private var isLoading = false
    @State private var hasAttemptedLoad = false
    @State private var loadTask: Task<Void, Never>?

    private var requestKey: String {
        let statusDetail = match.statusDetailText ?? ""
        let statusPeriod = match.statusPeriod.map(String.init) ?? "n/a"
        return "\(match.id)|\(match.homeScore)|\(match.awayScore)|\(match.statusText)|\(statusDetail)|\(statusPeriod)"
    }

    var body: some View {
        Group {
            if match.totalGoals <= 0 {
                EmptyView()
            } else if scorers == nil && (!hasAttemptedLoad || isLoading) {
                FootballGoalScorersLoadingView()
            } else if let scorers,
                      !scorers.home.isEmpty || !scorers.away.isEmpty {
                FootballGoalScorersView(match: match, scorers: scorers)
            }
        }
        .onAppear {
            startLoadingScorers()
        }
        .onChange(of: requestKey) { _ in
            startLoadingScorers()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func startLoadingScorers() {
        loadTask?.cancel()

        guard match.totalGoals > 0 else {
            scorers = nil
            isLoading = false
            hasAttemptedLoad = true
            return
        }

        let currentRequestKey = requestKey
        let footballClient = monitor.footballClient
        let hadScorers = scorers != nil
        isLoading = true
        if !hadScorers {
            hasAttemptedLoad = false
        }

        loadTask = Task {
            do {
                let fetchedScorers = try await footballClient.fetchGoalScorers(for: match)
                await MainActor.run {
                    guard currentRequestKey == requestKey else { return }
                    scorers = fetchedScorers
                    isLoading = false
                    hasAttemptedLoad = true
                }
            } catch {
                await MainActor.run {
                    guard currentRequestKey == requestKey else { return }
                    isLoading = false
                    hasAttemptedLoad = true
                }
            }
        }
    }
}

private struct FootballGoalScorersView: View {
    let match: FootballFixtureMatch
    let scorers: FootballMatchGoalScorers

    var body: some View {
        let homeScorers = sortedScorers(scorers.home)
        let awayScorers = sortedScorers(scorers.away)
        let targetRowCount = max(homeScorers.count, awayScorers.count, 1)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                scorerColumn(
                    title: match.homeTeam.abbreviation,
                    scorers: homeScorers,
                    targetRowCount: targetRowCount
                )

                scorerColumn(
                    title: match.awayTeam.abbreviation,
                    scorers: awayScorers,
                    targetRowCount: targetRowCount
                )
            }
        }
    }

    @ViewBuilder
    private func scorerColumn(
        title: String,
        scorers: [FootballMatchGoalScorer],
        targetRowCount: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))

            ForEach(scorers) { scorer in
                HStack(spacing: 6) {
                    Text(scorer.minute ?? "—")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: 34, alignment: .center)

                    Text(scorer.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ForEach(0..<max(0, targetRowCount - scorers.count), id: \.self) { _ in
                scorerPlaceholderRow()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private func sortedScorers(_ scorers: [FootballMatchGoalScorer]) -> [FootballMatchGoalScorer] {
        scorers.sorted { lhs, rhs in
            scorerEventIndex(lhs.id) < scorerEventIndex(rhs.id)
        }
    }

    private func scorerPlaceholderRow() -> some View {
        HStack(spacing: 6) {
            Text("88'")
                .font(.caption2.weight(.semibold))
                .frame(width: 34, alignment: .center)
                .hidden()

            Text("Placeholder")
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
        }
    }

    private func scorerEventIndex(_ scorerID: String) -> Int {
        guard let token = scorerID.split(separator: "-").last,
              let index = Int(token) else {
            return .max
        }
        return index
    }
}

private struct FootballGoalScorersLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 18)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    )
                }
            }
        }
    }
}

private struct SplitDropdownSectionHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MapMarkerItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
