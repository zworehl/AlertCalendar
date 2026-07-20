import SwiftUI

extension SettingsGameSalesSectionView {
    var introductionPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("Game Sales")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Text("Track scheduled store campaigns and manage their all-day events in Apple Calendar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(panelChrome)
    }

    var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    targetCalendarControl
                        .frame(maxWidth: 320, alignment: .leading)

                    calendarAlertControl
                        .frame(maxWidth: 300, alignment: .leading)

                    Spacer(minLength: 0)

                    browseControls
                        .frame(maxWidth: 430, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 12) {
                    targetCalendarControl
                    calendarAlertControl
                    browseControls
                        .frame(maxWidth: 430, alignment: .leading)
                }
            }

            Divider()

            automationControls
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelChrome)
    }

    var targetCalendarControl: some View {
        controlField(
            title: "Add To",
            helpText: "New managed sale campaigns are written to this Apple Calendar."
        ) {
            Picker("Game sales calendar", selection: $targetCalendarID) {
                Text("Choose a calendar…").tag("")
                ForEach(writableCalendars) { calendar in
                    Text(calendar.title).tag(calendar.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    var calendarAlertControl: some View {
        controlField(
            title: "Calendar Alert",
            helpText: "Applies one Apple Calendar alert to every sale managed by Alert Calendar."
        ) {
            Picker("Game sale alert", selection: calendarAlertBinding) {
                ForEach(GameSaleCalendarAlertOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    var browseControls: some View {
        HStack(spacing: 10) {
            Picker("Game sales view", selection: $browseMode) {
                ForEach(BrowseMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("Store", selection: $storeFilter) {
                ForEach(StoreFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
        }
    }

    var automationControls: some View {
        ViewThatFits(in: .horizontal) {
            automationRow

            ScrollView(.horizontal, showsIndicators: false) {
                automationRow
            }
        }
    }

    var automationRow: some View {
        HStack(alignment: .top, spacing: 22) {
            automationTitle
                .frame(width: Self.inlineFieldLabelWidth, alignment: .leading)

            storeAutomationRow

            Divider()
                .frame(height: 34)

            Toggle("Notify when sales are added", isOn: $enableAutoAddNotifications)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .disabled(autoAddStores.isEmpty)
                .fixedSize()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    var automationTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Automation")
                .font(.caption.weight(.semibold))
            Text("New campaigns")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    var storeAutomationRow: some View {
        HStack(alignment: .top, spacing: 22) {
            ForEach(GameStore.allCases) { store in
                autoAddToggle(for: store)
            }
        }
    }

    func autoAddToggle(for store: GameStore) -> some View {
        Toggle(
            "Auto-add \(automationStoreTitle(for: store))",
            isOn: Binding(
                get: { autoAddStores.contains(store) },
                set: { setAutoAddEnabled($0, for: store) }
            )
        )
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .disabled(targetCalendarID.isEmpty)
        .fixedSize()
        .help(automationHelp(for: store))
    }

    func setAutoAddEnabled(_ isEnabled: Bool, for store: GameStore) {
        if isEnabled {
            autoAddStores.insert(store)
        } else {
            autoAddStores.remove(store)
        }
    }

    func automationStoreTitle(for store: GameStore) -> String {
        switch store {
        case .steam:
            return "Steam"
        case .xbox:
            return "Xbox"
        case .playStation:
            return "PlayStation"
        case .nintendoSwitch:
            return "Nintendo Switch"
        }
    }

    func automationHelp(for store: GameStore) -> String {
        switch store {
        case .steam:
            return "Automatically add campaigns from Steam's complete official published schedule."
        case .xbox, .playStation, .nintendoSwitch:
            return "Automatically add campaigns announced with explicit start and end dates by the official store. Announcement coverage may be incomplete."
        }
    }

    func controlField<Content: View>(
        title: String,
        helpText: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "questionmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help(helpText)
            }
            content()
        }
    }

    var panelChrome: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}
