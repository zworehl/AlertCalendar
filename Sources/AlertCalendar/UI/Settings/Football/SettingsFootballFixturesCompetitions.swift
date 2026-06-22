import AppKit
import Combine
import SwiftUI

extension SettingsFootballFixturesSectionView {
    nonisolated static let competitionOffseasonFeedbackTitle = "Offseason"

    var competitionListPanel: some View {
        HStack(alignment: .top, spacing: 16) {
            competitionSelectionContentPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            competitionFiltersPanel
                .frame(width: 280, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var competitionSelectionContentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let section = selectedCompetitionSection {
                let visibleMatches = displayedMatches(section.matches)

                HStack(spacing: 8) {
                    competitionSelectionHeader(for: section)

                    Spacer()

                    if !visibleMatches.isEmpty {
                        competitionBulkActionButton(for: visibleMatches)
                    }

                    if section.isLoading && !section.hasLoaded && section.matches.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                    } else if section.errorMessage != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else if Self.isCompetitionOffseason(section) {
                        Text(Self.competitionOffseasonFeedbackTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else if section.hasLoaded {
                        Text("\(visibleMatches.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Load")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                competitionContent(for: section, visibleMatches: visibleMatches)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                emptyState("Choose a competition from the panel on the right.")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelChrome)
    }

    func competitionSelectionHeader(for section: FootballMenuCompetitionSection) -> some View {
        let logoSource = competitionHeaderLogoSource(for: section)

        return HStack(alignment: .center, spacing: 10) {
            FootballCompetitionLogoView(
                localPath: logoSource?.localPath,
                remoteURL: logoSource?.remoteURL,
                size: 38,
                placeholderSymbolSize: 18
            )
            .frame(width: 38, height: 38, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                Text(section.competition.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let region = selectedCompetitionRegionEntry?.region {
                    Text(region.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var competitionFiltersPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("Browse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Toggle("Show FT matches", isOn: $showFinishedFootballMatches)
                    .toggleStyle(.checkbox)
                    .font(.subheadline.weight(.medium))
            }

            if showFinishedFootballMatches {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("FT lookback")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(Self.matchWindowValueText(days: normalizedFinishedMatchLookbackDays))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: finishedMatchLookbackDaysBinding,
                        in: Double(Self.minimumFootballWindowDays) ... Double(Self.maximumFootballWindowDays),
                        step: 1
                    )

                    Text("Finished matches stay visible until their estimated end time is older than this window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Ahead window")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(Self.matchWindowValueText(days: normalizedMatchLookaheadDays))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: matchLookaheadDaysBinding,
                    in: Double(Self.minimumFootballWindowDays) ... Double(Self.maximumFootballWindowDays),
                    step: 1
                )

                Text("Scheduled matches beyond this window are hidden from the browse list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Region")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(competitionSectionsByRegion, id: \.region.id) { entry in
                    competitionRegionFilterButton(entry)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Competition")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if selectedCompetitionSections.isEmpty {
                    emptyState("No competitions are available for the selected region.")
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(selectedCompetitionSections) { section in
                                competitionSelectionButton(section)
                            }
                        }
                        .padding(.trailing, 2)
                    }
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelChrome)
    }

    @ViewBuilder
    func competitionContent(
        for section: FootballMenuCompetitionSection,
        visibleMatches: [FootballFixtureMatch]
    ) -> some View {
        if section.isLoading && !section.hasLoaded && section.matches.isEmpty {
            loadingState("Loading fixtures for \(section.competition.title)...")
        } else if let errorMessage = section.errorMessage {
            feedbackState(
                title: "Could not load \(section.competition.title)",
                text: errorMessage,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                buttonTitle: "Retry",
                isButtonDisabled: section.isLoading
            ) {
                await loadCompetitionFixtures(section)
            }
        } else if !section.hasLoaded && !section.isLoading && section.matches.isEmpty {
            feedbackState(
                title: "No matches loaded yet",
                text: "Use Load Fixtures to fetch the \(FootballCompetitionPreset.suggestionWindowDescription) for this competition.",
                systemImage: FootballFixtureFormatter.footballLocationSymbolName,
                tint: .secondary,
                buttonTitle: "Load Fixtures"
            ) {
                await loadCompetitionFixtures(section)
            }
        } else if Self.isCompetitionOffseason(section) {
            feedbackState(
                title: Self.competitionOffseasonFeedbackTitle,
                text: Self.competitionOffseasonFeedbackText(for: section.competition),
                systemImage: "pause.circle.fill",
                tint: .secondary,
                buttonTitle: "Refresh Fixtures",
                isButtonDisabled: section.isLoading
            ) {
                await loadCompetitionFixtures(section)
            }
        } else if visibleMatches.isEmpty {
            emptyState(showFinishedFootballMatches
                ? "No matches are available inside the current FT lookback and ahead windows."
                : "No unfinished matches available in the \(FootballCompetitionPreset.suggestionWindowDescription)."
            )
        } else {
            matchCardsViewport(visibleMatches, showsCompetitionName: false)
        }
    }

    func competitionRegionFilterButton(_ entry: (region: FootballCompetitionRegion, sections: [FootballMenuCompetitionSection])) -> some View {
        let isSelected = entry.region.id == selectedCompetitionRegionEntry?.region.id

        return Button {
            selectedCompetitionRegionID = entry.region.id
            selectedCompetitionID = entry.sections.first?.id
        } label: {
            HStack(spacing: 8) {
                Text(entry.region.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("\(entry.sections.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.92) : .secondary)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    func competitionSelectionButton(_ section: FootballMenuCompetitionSection) -> some View {
        let isSelected = section.id == selectedCompetitionSection?.id
        let visibleMatchCount = displayedMatches(section.matches).count

        return Button {
            selectedCompetitionRegionID = section.competition.region.id
            selectedCompetitionID = section.id
        } label: {
            HStack(spacing: 8) {
                Text(section.competition.title)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if section.isLoading && !section.hasLoaded && section.matches.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                } else if section.errorMessage != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if Self.isCompetitionOffseason(section) {
                    Text(Self.competitionOffseasonFeedbackTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? .white.opacity(0.92) : .secondary)
                } else if section.hasLoaded {
                    Text("\(visibleMatchCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? .white.opacity(0.92) : .secondary)
                } else {
                    Text("Load")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? .white.opacity(0.92) : .secondary)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var competitionListFeedback: some View {
        if !hasAnyCompetitionCards && !competitionSectionsWithErrors.isEmpty {
            feedbackState(
                title: "Could not load football fixtures",
                text: competitionRetryMessage,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                buttonTitle: "Retry Failed Loads",
                isButtonDisabled: footballMenuSections.contains(where: \.isLoading)
            ) {
                await retryFailedCompetitionLoads()
            }
        } else if !hasAnyCompetitionCards && !hasAttemptedCompetitionLoads {
            feedbackState(
                title: "No football cards loaded yet",
                text: "Expand a competition below to load its matches. If a request fails, you will see a retry button in that section.",
                systemImage: FootballFixtureFormatter.footballLocationSymbolName,
                tint: .secondary
            )
        }
    }

    var competitionRetryMessage: String {
        if competitionSectionsWithErrors.count == 1,
           let errorMessage = competitionSectionsWithErrors.first?.errorMessage {
            return errorMessage
        }

        return "Several competitions could not be loaded right now. Try again in a moment."
    }

    nonisolated static func isCompetitionOffseason(_ section: FootballMenuCompetitionSection) -> Bool {
        section.hasLoaded
            && !section.isLoading
            && section.errorMessage == nil
            && section.matches.isEmpty
    }

    nonisolated static func competitionOffseasonFeedbackText(for competition: FootballCompetitionPreset) -> String {
        "No fixtures are available for \(competition.title) in the "
            + "\(FootballCompetitionPreset.suggestionWindowDescription). "
            + "This competition appears to be in its offseason."
    }
}
