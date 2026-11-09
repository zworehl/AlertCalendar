import SwiftUI

extension SettingsGameSalesSectionView {
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

            SettingsSectionDivider()

            automationControls
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var targetCalendarControl: some View {
        SettingsAddToCalendarPicker(
            selection: $targetCalendarID,
            calendars: writableCalendars,
            pickerTitle: L10n.text("Game sales calendar"),
            helpText: L10n.text("New managed sale campaigns are written to this Apple Calendar."),
            emptySelectionTitle: L10n.text("Choose a calendar…")
        )
    }

    var calendarAlertControl: some View {
        SettingsLabeledMenuPicker(
            title: L10n.text("Calendar Alert"),
            pickerTitle: L10n.text("Game sale alert"),
            selection: calendarAlertBinding,
            helpText: L10n.text("Applies one Apple Calendar alert to every sale managed by Alert Calendar."),
            layout: .inline(labelWidth: SettingsVisualMetrics.calendarAlertLabelWidth)
        ) {
            ForEach(GameSaleCalendarAlertOption.allCases) { option in
                Text(option.title).tag(option)
            }
        }
    }

    var browseControls: some View {
        HStack(spacing: 10) {
            Picker(L10n.text("Game sales view"), selection: $browseMode) {
                ForEach(BrowseMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker(L10n.text("Store"), selection: $storeFilter) {
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
            HStack(alignment: .center, spacing: 16) {
                gameSalesAutoAddGroup(layout: .inline)

                SettingsVerticalDivider(height: SettingsVisualMetrics.inlineDividerHeight)

                gameSalesNotificationGroup(layout: .inline)
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 10) {
                gameSalesAutoAddGroup(layout: .adaptive)

                SettingsSectionDivider()

                gameSalesNotificationGroup(layout: .adaptive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func gameSalesAutoAddGroup(layout: SettingsLabeledCheckboxGroupLayout) -> some View {
        SettingsLabeledCheckboxGroup(title: L10n.text("Auto-add"), layout: layout) {
            ForEach(GameStore.allCases) { store in
                autoAddToggle(for: store)
            }
        }
    }

    func gameSalesNotificationGroup(layout: SettingsLabeledCheckboxGroupLayout) -> some View {
        SettingsLabeledCheckboxGroup(title: L10n.text("Notifications"), layout: layout) {
            Toggle(L10n.text("Added sales"), isOn: $enableAutoAddNotifications)
                .disabled(autoAddStores.isEmpty)
                .help(L10n.text("Notify when Alert Calendar adds a new sale campaign to Apple Calendar."))
        }
    }

    func autoAddToggle(for store: GameStore) -> some View {
        Toggle(
            automationStoreTitle(for: store),
            isOn: Binding(
                get: { autoAddStores.contains(store) },
                set: { setAutoAddEnabled($0, for: store) }
            )
        )
        .disabled(targetCalendarID.isEmpty)
        .accessibilityLabel(L10n.text("Auto-add \(automationStoreTitle(for: store))"))
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
            return L10n.text("Automatically add campaigns from Steam's complete official published schedule.")
        case .xbox, .playStation, .nintendoSwitch:
            return L10n.text("Automatically add campaigns announced with explicit start and end dates by the official store. Announcement coverage may be incomplete.")
        }
    }

}
