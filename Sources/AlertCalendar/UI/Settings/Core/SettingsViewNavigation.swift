import AppKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var settingsNavigationLayout: some View {
        settingsNavigationSplitView
    }

    private var settingsNavigationSplitView: some View {
        NavigationSplitView(columnVisibility: $settingsColumnVisibility) {
            settingsSidebar
                .navigationSplitViewColumnWidth(
                    min: SettingsVisualMetrics.sidebarMinimumWidth,
                    ideal: SettingsVisualMetrics.sidebarIdealWidth,
                    max: SettingsVisualMetrics.sidebarMaximumWidth
                )
        } detail: {
            settingsDetailPane
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var settingsSidebar: some View {
        List(selection: settingsSidebarSelection) {
            if visiblePrimarySettingsTabs.isEmpty && visibleFeedSubsections.isEmpty {
                SettingsSidebarEmptySearchView(query: settingsSearchQuery)
                    .listRowBackground(Color.clear)
            } else {
                if !visiblePrimarySettingsTabs.isEmpty {
                    Section("Settings") {
                        ForEach(visiblePrimarySettingsTabs) { tab in
                            settingsSidebarLabel(tab.rawValue, symbolName: tab.symbolName)
                                .tag(SettingsSidebarDestination.tab(tab))
                        }
                    }
                }

                if !visibleFeedSubsections.isEmpty {
                    Section("Feeds") {
                        ForEach(visibleFeedSubsections) { subsection in
                            settingsSidebarLabel(subsection.rawValue, symbolName: subsection.symbolName)
                                .tag(SettingsSidebarDestination.feed(subsection))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(
            text: $settingsSearchQuery,
            placement: .sidebar,
            prompt: "Search Settings"
        )
        .accessibilityIdentifier("settings.sidebar")
    }

    private func settingsSidebarLabel(_ title: String, symbolName: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbolName)
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
                .frame(width: 22, height: 22)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
    }

    private var settingsSidebarSelection: Binding<SettingsSidebarDestination?> {
        Binding(
            get: {
                selectedTab == .feeds
                    ? .feed(selectedFeedsSubsection)
                    : .tab(selectedTab)
            },
            set: { destination in
                guard let destination else { return }
                switch destination {
                case .tab(let tab):
                    selectedTab = tab
                case .feed(let subsection):
                    selectedTab = .feeds
                    selectedFeedsSubsection = subsection
                }
            }
        )
    }

    private var settingsDetailPane: some View {
        VStack(spacing: 0) {
            settingsPageHeader
                .padding(.horizontal, SettingsVisualMetrics.detailHorizontalPadding)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()

            settingsDetailContent

            settingsActionBar
                .padding(.horizontal, SettingsVisualMetrics.detailHorizontalPadding)
                .padding(.vertical, 12)
                .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SettingsDetailWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        )
        .accessibilityIdentifier("settings.detail")
    }

    @ViewBuilder
    private var settingsPageHeader: some View {
        SettingsPageHeaderView(
            title: settingsPageTitle,
            subtitle: settingsPageSubtitle,
            systemImage: settingsPageSystemImage,
            tint: settingsPageTint
        )
    }

    @ViewBuilder
    private var settingsDetailContent: some View {
        Group {
            if selectedSettingsContentUsesEmbeddedScroller {
                settingsEmbeddedDetailContent
            } else {
                settingsScrollableDetailContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var settingsEmbeddedDetailContent: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
                activeSettingsContent
            }
            .padding(.horizontal, SettingsVisualMetrics.detailHorizontalPadding)
            .padding(.vertical, SettingsVisualMetrics.detailVerticalPadding)
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
        }
    }

    private var settingsScrollableDetailContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: SettingsVisualMetrics.pageSpacing) {
                activeSettingsContent
            }
            .padding(.horizontal, SettingsVisualMetrics.detailHorizontalPadding)
            .padding(.vertical, SettingsVisualMetrics.detailVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var selectedSettingsContentUsesEmbeddedScroller: Bool {
        selectedTab == .feeds && selectedFeedsSubsection.usesEmbeddedDetailScroller
    }

    private var settingsPageTitle: String {
        selectedTab == .feeds ? selectedFeedsSubsection.title : selectedTab.rawValue
    }

    private var settingsPageSubtitle: String {
        selectedTab == .feeds ? selectedFeedsSubsection.subtitle : selectedTab.subtitle
    }

    private var settingsPageSystemImage: String {
        selectedTab == .feeds ? selectedFeedsSubsection.symbolName : selectedTab.symbolName
    }

    private var settingsPageTint: Color {
        selectedTab == .feeds ? selectedFeedsSubsection.tint : selectedTab.tint
    }

    private var normalizedSettingsSearchQuery: String {
        settingsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var visiblePrimarySettingsTabs: [SettingsTab] {
        let query = normalizedSettingsSearchQuery
        let primaryTabs = SettingsTab.allCases.filter { $0 != .feeds }
        guard !query.isEmpty else { return primaryTabs }

        return primaryTabs.filter { tab in
            sidebarSearchMatches(title: tab.rawValue, subtitle: tab.subtitle, query: query)
        }
    }

    private var visibleFeedSubsections: [FeedsSubsection] {
        let query = normalizedSettingsSearchQuery
        guard !query.isEmpty else { return FeedsSubsection.allCases }

        if sidebarSearchMatches(title: SettingsTab.feeds.rawValue, subtitle: SettingsTab.feeds.subtitle, query: query) {
            return FeedsSubsection.allCases
        }

        return FeedsSubsection.allCases.filter { subsection in
            sidebarSearchMatches(title: subsection.title, subtitle: subsection.subtitle, query: query)
        }
    }

    private func sidebarSearchMatches(title: String, subtitle: String, query: String) -> Bool {
        title.lowercased().contains(query) || subtitle.lowercased().contains(query)
    }
}

private struct SettingsSidebarEmptySearchView: View {
    let query: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.tertiary)

            Text("No Settings Found")
                .font(.subheadline.weight(.semibold))

            Text("No settings match “\(query)”.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}
