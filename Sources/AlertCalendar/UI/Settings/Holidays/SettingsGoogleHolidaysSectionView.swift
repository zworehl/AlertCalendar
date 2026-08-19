import Combine
import SwiftUI

struct SettingsGoogleHolidaysSectionView: View {
    let monitor: CalendarMonitor
    @Binding var selectedCountryIDs: Set<String>
    @Binding var targetCalendarID: String

    @State private var searchText = ""
    @State private var hasEventsAccess = false
    @State private var writableCalendars: [AvailableCalendar] = []
    @State private var subscribedCountryIDs: Set<String> = []
    @State private var isSyncingGoogleHolidays = false
    @State private var googleHolidaySyncErrorDescription: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !hasEventsAccess {
                feedbackPanel(
                    title: "Calendar access required",
                    detail: "Grant Calendar access to consolidate Google holidays into Apple Calendar.",
                    systemImage: "calendar.badge.exclamationmark"
                )
            } else if writableCalendars.isEmpty {
                feedbackPanel(
                    title: "No writable calendars",
                    detail: "Create or enable a writable Apple Calendar before synchronizing holidays.",
                    systemImage: "calendar.badge.minus"
                )
            } else {
                countrySelectionPanel
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear(perform: synchronizeViewState)
        .onReceive(monitor.$hasEventsAccess.removeDuplicates()) { value in
            hasEventsAccess = value
        }
        .onReceive(monitor.$availableEventCalendars.removeDuplicates()) { _ in
            synchronizeCalendars()
        }
        .onReceive(monitor.$isSyncingGoogleHolidays.removeDuplicates()) { isSyncing in
            isSyncingGoogleHolidays = isSyncing
        }
        .onReceive(monitor.$googleHolidaySyncErrorDescription.removeDuplicates()) { description in
            googleHolidaySyncErrorDescription = description
        }
    }

    private var targetCalendarControl: some View {
        SettingsAddToCalendarPicker(
            selection: $targetCalendarID,
            calendars: writableCalendars,
            pickerTitle: "Holiday destination calendar",
            helpText: "All selected country feeds are consolidated into this writable Apple Calendar.",
            emptySelectionTitle: "Choose a calendar…"
        )
    }

    private var countrySelectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            countrySelectionControls

            synchronizationFeedback

            SettingsSectionDivider()

            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 190, maximum: 280), alignment: .leading),
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(filteredCountries) { country in
                    Toggle(
                        "\(country.flag) \(country.displayName)",
                        isOn: countryBinding(country.id)
                    )
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .help("Google Calendar: Holidays in \(country.englishName)")
                }
            }
            .padding(.vertical, 2)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityLabel("Google holiday countries and territories")

            if filteredCountries.isEmpty {
                Text("No countries or territories match this search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var countrySelectionControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                targetCalendarControl
                    .frame(width: 340, alignment: .leading)

                Divider()
                    .frame(height: 36)

                countryFilterRow
            }

            VStack(alignment: .leading, spacing: 12) {
                targetCalendarControl
                    .frame(maxWidth: 520, alignment: .leading)

                Divider()

                compactCountryFilterControls
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactCountryFilterControls: some View {
        ViewThatFits(in: .horizontal) {
            countryFilterRow

            VStack(alignment: .leading, spacing: 10) {
                countrySelectionHeader

                HStack(spacing: 12) {
                    countrySearchField
                    countryActions
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                countrySelectionHeader
                countrySearchField
                countryActions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countryFilterRow: some View {
        HStack(alignment: .center, spacing: 16) {
            countrySelectionHeader
                .fixedSize(horizontal: true, vertical: false)

            countrySearchField

            countryActions
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var countrySearchField: some View {
        TextField("Search countries and territories", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 220, maxWidth: .infinity)
    }

    @ViewBuilder
    private var synchronizationFeedback: some View {
        if isSyncingGoogleHolidays {
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text("Synchronizing Google holidays…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let googleHolidaySyncErrorDescription {
            Label(
                googleHolidaySyncErrorDescription,
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var countrySelectionHeader: some View {
        SettingsSectionHeaderView(
            title: "Countries & Territories"
        )
    }

    private var countryActions: some View {
        HStack(spacing: 8) {
            if !subscribedCountryIDs.isEmpty {
                Button("Use Subscribed (\(subscribedCountryIDs.count))") {
                    selectedCountryIDs.formUnion(subscribedCountryIDs)
                }
                .help("Select countries detected from subscribed holiday calendars in Apple Calendar.")
            }

            Button("Select All") {
                selectedCountryIDs = GoogleHolidayCountry.validIDs
            }
            Button("Clear") {
                selectedCountryIDs.removeAll()
            }
            .disabled(selectedCountryIDs.isEmpty)
        }
        .controlSize(.small)
    }

    private var filteredCountries: [GoogleHolidayCountry] {
        let query = normalizedSearchText(searchText)
        guard !query.isEmpty else { return GoogleHolidayCountry.all }
        return GoogleHolidayCountry.all.filter { country in
            normalizedSearchText(country.displayName).contains(query)
                || normalizedSearchText(country.englishName).contains(query)
                || country.id.lowercased().contains(query)
        }
    }

    private func countryBinding(_ countryID: String) -> Binding<Bool> {
        Binding(
            get: { selectedCountryIDs.contains(countryID) },
            set: { isSelected in
                if isSelected {
                    selectedCountryIDs.insert(countryID)
                } else {
                    selectedCountryIDs.remove(countryID)
                }
            }
        )
    }

    private func synchronizeCalendars() {
        writableCalendars = monitor.writableGoogleHolidayTargetCalendars()
        subscribedCountryIDs = GoogleHolidayCountry.matchingSubscribedCalendarTitles(
            monitor.availableEventCalendars
                .filter(\.isSubscribed)
                .map(\.title)
        )
        if !targetCalendarID.isEmpty,
           !writableCalendars.contains(where: { $0.id == targetCalendarID }) {
            targetCalendarID = ""
        }
    }

    private func synchronizeViewState() {
        hasEventsAccess = monitor.hasEventsAccess
        isSyncingGoogleHolidays = monitor.isSyncingGoogleHolidays
        googleHolidaySyncErrorDescription = monitor.googleHolidaySyncErrorDescription
        synchronizeCalendars()
    }

    private func normalizedSearchText(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func feedbackPanel(title: String, detail: String, systemImage: String) -> some View {
        SettingsSectionHeaderView(
            title: title,
            subtitle: detail,
            systemImage: systemImage,
            iconColor: .orange
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
