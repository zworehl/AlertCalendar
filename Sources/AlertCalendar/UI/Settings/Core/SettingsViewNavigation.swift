import SwiftUI

extension SettingsView {
    @ViewBuilder
    var settingsNavigationControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                settingsTabPicker
                    .frame(maxWidth: 620, alignment: .leading)

                if selectedTab == .feeds {
                    Spacer(minLength: 0)
                    feedsSubsectionPicker
                        .frame(width: 330)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                settingsTabPicker
                    .frame(maxWidth: 620, alignment: .leading)

                if selectedTab == .feeds {
                    feedsSubsectionPicker
                        .frame(maxWidth: 330, alignment: .leading)
                }
            }
        }
    }

    private var settingsTabPicker: some View {
        Picker("Settings section", selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                Label(tab.rawValue, systemImage: tab.symbolName)
                    .tag(tab)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    private var feedsSubsectionPicker: some View {
        Picker("Feeds subsection", selection: $selectedFeedsSubsection) {
            ForEach(FeedsSubsection.allCases) { subsection in
                Label(subsection.rawValue, systemImage: subsection.symbolName)
                    .tag(subsection)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }
}
