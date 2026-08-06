import Foundation
import SwiftUI

extension SettingsGameSalesSectionView {
    @ViewBuilder
    var salesContent: some View {
        if monitor.gameSales.isEmpty, monitor.isRefreshingGameSales {
            feedbackPanel(
                title: "Loading game sales",
                detail: "Checking official schedules and matching Apple Calendar events.",
                systemImage: "arrow.triangle.2.circlepath",
                tint: .secondary
            )
        } else if monitor.gameSales.isEmpty,
                  let errorDescription = monitor.gameSalesErrorDescription {
            feedbackPanel(
                title: "Game sales unavailable",
                detail: errorDescription,
                systemImage: "exclamationmark.triangle",
                tint: .orange
            )
        } else if displayedSales.isEmpty {
            feedbackPanel(
                title: browseMode == .added ? "No added sales" : "No matching sales",
                detail: emptySalesDetail,
                systemImage: browseMode == .added ? "calendar.badge.plus" : "line.3.horizontal.decrease.circle",
                tint: .secondary
            )
        } else {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(
                            minimum: Self.minimumCardWidth,
                            maximum: Self.preferredCardWidth
                        ),
                        spacing: 12,
                        alignment: .top
                    ),
                ],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(displayedSales) { sale in
                    GameSaleCardView(
                        sale: sale,
                        now: visibleNow,
                        isPresent: monitor.isGameSalePresent(sale),
                        isManaged: monitor.isGameSaleManaged(sale),
                        canAdd: !targetCalendarID.isEmpty,
                        onAdd: {
                            Task {
                                _ = await monitor.addGameSaleToCalendar(sale)
                            }
                        },
                        onRemove: {
                            monitor.removeGameSaleFromCalendar(sale)
                        },
                        onOpen: {
                            monitor.openGameSaleInCalendar(sale)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !monitor.gameSales.isEmpty,
           let errorDescription = monitor.gameSalesErrorDescription {
            Label(errorDescription, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    var emptySalesDetail: String {
        if browseMode == .added {
            return "Add a campaign from Upcoming, or choose another store filter."
        }
        if storeFilter != .all {
            return "No active or upcoming campaigns match the selected store."
        }
        return "No active or upcoming campaigns are available right now."
    }

    func feedbackPanel(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(SettingsVisualMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelChrome)
    }
}

private struct GameSaleCardView: View {
    let sale: GameSaleEvent
    let now: Date
    let isPresent: Bool
    let isManaged: Bool
    let canAdd: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                storeBadge

                Spacer(minLength: 4)

                ZStack(alignment: .trailing) {
                    statusBadge
                        .opacity(isHovered ? 0 : 1)
                        .scaleEffect(isHovered ? 0.96 : 1)

                    cardActions(isVisible: isHovered)
                }
                .animation(.easeInOut(duration: 0.14), value: isHovered)
            }

            Text(sale.title)
                .font(SettingsTypography.itemTitle)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .accessibilityHidden(true)
                Text(dateRangeText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(SettingsTypography.itemDetail)
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text(isActive ? "Ends \(formattedEndDate)" : "Starts \(formattedStartDate)")
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Link(destination: sale.officialURL) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .help("Open the official campaign page")
            }
            .font(.caption2.weight(.medium))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovered ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.14), value: isHovered)
    }

    var isActive: Bool {
        sale.startDate <= now && now < sale.endDateExclusive
    }

    var inclusiveEndDate: Date {
        sale.endDateExclusive.addingTimeInterval(-1)
    }

    var formattedStartDate: String {
        compactDateText(sale.startDate)
    }

    var formattedEndDate: String {
        compactDateText(inclusiveEndDate)
    }

    var dateRangeText: String {
        let calendar = Calendar.autoupdatingCurrent
        return AlertCalendarDateRangeFormatter.compactAllDayRange(
            startDay: calendar.startOfDay(for: sale.startDate),
            lastInclusiveDay: calendar.startOfDay(for: inclusiveEndDate),
            calendar: calendar
        )
    }

    func compactDateText(_ date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.startOfDay(for: date)
        return AlertCalendarDateRangeFormatter.compactAllDayRange(
            startDay: day,
            lastInclusiveDay: day,
            calendar: calendar
        )
    }

    var cardBorderColor: Color {
        if isHovered {
            return Color.accentColor.opacity(0.22)
        }
        if isManaged {
            return Color.green.opacity(0.30)
        }
        if isPresent {
            return Color.blue.opacity(0.22)
        }
        return Color.primary.opacity(0.06)
    }

    var statusBadge: some View {
        Text(isActive ? "ACTIVE" : "UPCOMING")
            .font(SettingsTypography.metadataEmphasized)
            .foregroundStyle(isActive ? Color.green : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill((isActive ? Color.green : Color.secondary).opacity(0.10))
            )
    }

    var storeBadge: some View {
        HStack(spacing: 5) {
            GameStoreIconView(store: sale.store, size: 12)

            Text(storeTitle)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(storeTint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(storeTint.opacity(0.10))
        )
    }

    @ViewBuilder
    func cardActions(isVisible: Bool) -> some View {
        HStack(spacing: 5) {
            if isPresent {
                SettingsCalendarCardActionButton(
                    calendarAction: .open,
                    isVisible: isVisible,
                    action: onOpen
                )
            }

            if isManaged {
                SettingsCalendarCardActionButton(
                    calendarAction: .remove,
                    isVisible: isVisible,
                    action: onRemove
                )
            } else if !isPresent {
                SettingsCalendarCardActionButton(
                    calendarAction: .add,
                    isVisible: isVisible,
                    action: onAdd
                )
                .disabled(!canAdd)
            }
        }
    }

    var storeTitle: String {
        sale.store.title
    }

    var storeTint: Color {
        Color(nsColor: GameStoreSymbolProvider.brandColor(for: sale.store))
    }
}
