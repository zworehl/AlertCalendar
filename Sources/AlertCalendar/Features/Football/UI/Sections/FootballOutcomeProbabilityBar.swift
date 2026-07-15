import SwiftUI

struct FootballOutcomeProbabilityPresentation: Equatable {
    enum Outcome: Equatable {
        case homeWin
        case draw
        case awayWin
    }

    struct Item: Equatable {
        let outcome: Outcome
        let probability: Double
        let percentagePoints: Int

        var percentageText: String {
            guard probability > 0 else { return "0%" }
            if probability < 0.01 {
                return "<1%"
            }
            if percentagePoints == 100, probability < 1 {
                return ">99%"
            }
            return "\(percentagePoints)%"
        }

        var accessibilityPercentageText: String {
            guard probability > 0 else { return "0 percent" }
            if probability < 0.01 {
                return "less than 1 percent"
            }
            if percentagePoints == 100, probability < 1 {
                return "more than 99 percent"
            }
            return "\(percentagePoints) percent"
        }
    }

    let scope: FootballMatchOutcomeProbabilityScope
    let source: FootballMatchOutcomeProbabilitySource
    let providerName: String?
    let items: [Item]

    init(probabilities: FootballMatchOutcomeProbabilities) {
        scope = probabilities.scope
        source = probabilities.source
        let trimmedProviderName = probabilities.providerName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        providerName = trimmedProviderName?.isEmpty == false ? trimmedProviderName : nil

        let outcomes: [Outcome]
        let values: [Double]
        switch probabilities.scope {
        case .decisiveResult:
            outcomes = [.homeWin, .awayWin]
            values = [probabilities.homeWin, probabilities.awayWin]
        case .regulationTime, .extraTimePossible:
            outcomes = [.homeWin, .draw, .awayWin]
            values = [probabilities.homeWin, probabilities.draw, probabilities.awayWin]
        }

        let normalizedValues = Self.normalizedVisibleValues(values)
        let roundedPoints = Self.roundedPercentagePoints(normalizedValues)
        items = zip(outcomes, zip(normalizedValues, roundedPoints)).map { outcome, valueAndPoints in
            Item(
                outcome: outcome,
                probability: valueAndPoints.0,
                percentagePoints: valueAndPoints.1
            )
        }
    }

    var scopeTitle: String {
        if source == .finalResult {
            return "Final result"
        }
        switch scope {
        case .regulationTime, .extraTimePossible:
            return "Regulation result"
        case .decisiveResult:
            return "Winner incl. penalties"
        }
    }

    var accessibilityScopeTitle: String {
        if source == .finalResult {
            return "Final result"
        }
        switch scope {
        case .regulationTime, .extraTimePossible:
            return "Result at the end of regulation, including added time"
        case .decisiveResult:
            return "Winner, including extra time and penalties"
        }
    }

    var sourceTitle: String {
        switch source {
        case .marketOdds:
            return providerName.map { "Market · \($0)" } ?? "Market"
        case .liveMarketOdds:
            return providerName.map { "Live market · \($0)" } ?? "Live market"
        case .heuristic:
            return providerName.map { "Model · \($0)" } ?? "Model"
        case .finalResult:
            return "Final"
        }
    }

    var sourceDescription: String {
        switch source {
        case .marketOdds:
            return providerName.map { "Pre-match market odds from \($0)" } ?? "Pre-match market odds"
        case .liveMarketOdds:
            return providerName.map { "Live market odds from \($0)" } ?? "Live market odds"
        case .heuristic:
            return providerName.map { "Model estimate using \($0) market odds" } ?? "Model estimate"
        case .finalResult:
            return "Final result"
        }
    }

    var segmentValues: [Double] {
        items.map(\.probability)
    }

    func accessibilitySummary(homeTeamName: String, awayTeamName: String) -> String {
        let outcomes = items.map { item in
            let title: String
            switch item.outcome {
            case .homeWin:
                title = "\(homeTeamName) win"
            case .draw:
                title = "Draw"
            case .awayWin:
                title = "\(awayTeamName) win"
            }
            return "\(title), \(item.accessibilityPercentageText)"
        }
        return "\(accessibilityScopeTitle). \(outcomes.joined(separator: "; "))."
    }

    static func roundedPercentagePoints(_ values: [Double]) -> [Int] {
        let normalizedValues = normalizedVisibleValues(values)
        guard !normalizedValues.isEmpty else { return [] }

        let exactPoints = normalizedValues.map { $0 * 100 }
        var roundedPoints = exactPoints.map { Int(floor($0)) }
        var pointsToAllocate = 100 - roundedPoints.reduce(0, +)

        let remainderOrder = exactPoints.indices.sorted { lhs, rhs in
            let lhsRemainder = exactPoints[lhs] - floor(exactPoints[lhs])
            let rhsRemainder = exactPoints[rhs] - floor(exactPoints[rhs])
            if abs(lhsRemainder - rhsRemainder) > 0.000_000_1 {
                return lhsRemainder > rhsRemainder
            }
            if abs(exactPoints[lhs] - exactPoints[rhs]) > 0.000_000_1 {
                return exactPoints[lhs] > exactPoints[rhs]
            }
            return lhs < rhs
        }

        var allocationIndex = 0
        while pointsToAllocate > 0, !remainderOrder.isEmpty {
            roundedPoints[remainderOrder[allocationIndex % remainderOrder.count]] += 1
            allocationIndex += 1
            pointsToAllocate -= 1
        }

        if pointsToAllocate < 0 {
            let removalOrder = remainderOrder.reversed()
            for index in removalOrder where pointsToAllocate < 0 && roundedPoints[index] > 0 {
                roundedPoints[index] -= 1
                pointsToAllocate += 1
            }
        }

        return roundedPoints
    }

    private static func normalizedVisibleValues(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [] }
        let sanitizedValues = values.map { value in
            value.isFinite ? max(0, value) : 0
        }
        let total = sanitizedValues.reduce(0, +)
        guard total > 0 else {
            let equalShare = 1 / Double(sanitizedValues.count)
            return Array(repeating: equalShare, count: sanitizedValues.count)
        }
        return sanitizedValues.map { $0 / total }
    }
}

enum FootballOutcomeProbabilitySegmentLayout {
    static func frames(values: [Double], totalWidth: CGFloat) -> [CGRect] {
        guard totalWidth > 0 else {
            return values.map { _ in .zero }
        }

        let sanitizedValues = values.map { value in
            value.isFinite ? max(0, value) : 0
        }
        let total = sanitizedValues.reduce(0, +)
        guard total > 0 else {
            return values.map { _ in .zero }
        }

        var cumulativeValue = 0.0
        return sanitizedValues.map { value in
            let start = totalWidth * CGFloat(cumulativeValue / total)
            cumulativeValue += value
            let end = totalWidth * CGFloat(cumulativeValue / total)
            return CGRect(x: start, y: 0, width: max(0, end - start), height: 1)
        }
    }
}

struct FootballOutcomeProbabilityBar: View {
    enum Style {
        case compact
        case contextual

        var barHeight: CGFloat {
            switch self {
            case .compact:
                return 5
            case .contextual:
                return 7
            }
        }

        var scopeFont: Font {
            switch self {
            case .compact:
                return .system(size: 8, weight: .semibold)
            case .contextual:
                return .caption2.weight(.semibold)
            }
        }

        var labelFont: Font {
            switch self {
            case .compact:
                return .system(size: 9, weight: .semibold)
            case .contextual:
                return .caption2.weight(.semibold)
            }
        }

        var verticalSpacing: CGFloat {
            switch self {
            case .compact:
                return 2
            case .contextual:
                return 4
            }
        }

        var estimatedHeight: CGFloat {
            switch self {
            case .compact:
                return 30
            case .contextual:
                return 41
            }
        }
    }

    let match: FootballFixtureMatch
    let display: FootballMenuBarDisplay?
    let probabilities: FootballMatchOutcomeProbabilities
    let style: Style
    var availableWidth: CGFloat? = nil

    private var presentation: FootballOutcomeProbabilityPresentation {
        FootballOutcomeProbabilityPresentation(probabilities: probabilities)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.verticalSpacing) {
            HStack(spacing: 6) {
                Text(presentation.scopeTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(presentation.sourceTitle)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
                .font(style.scopeFont)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            HStack(spacing: 6) {
                ForEach(Array(presentation.items.enumerated()), id: \.offset) { index, item in
                    probabilityLabel(
                        item: item,
                        alignment: labelAlignment(for: index, itemCount: presentation.items.count)
                    )
                }
            }
            .font(style.labelFont)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, alignment: .center)
            .clipped()

            ProbabilitySegmentBar(
                items: presentation.items,
                height: style.barHeight,
                color: outcomeColor
            )
        }
        .footballConstrainedWidth(availableWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityScopeTitle)
        .accessibilityValue(accessibilityOutcomeText)
        .accessibilityHint(presentation.sourceDescription)
        .help(helpText)
    }

    private var homeShortName: String {
        nonempty(display?.homeAbbreviation)
            ?? nonempty(match.homeTeam.abbreviation)
            ?? nonempty(match.homeTeam.name)
            ?? "Home"
    }

    private var awayShortName: String {
        nonempty(display?.awayAbbreviation)
            ?? nonempty(match.awayTeam.abbreviation)
            ?? nonempty(match.awayTeam.name)
            ?? "Away"
    }

    private var homeAccessibleName: String {
        nonempty(match.homeTeam.name) ?? homeShortName
    }

    private var awayAccessibleName: String {
        nonempty(match.awayTeam.name) ?? awayShortName
    }

    private var accessibilityOutcomeText: String {
        presentation.items.map { item in
            let title: String
            switch item.outcome {
            case .homeWin:
                title = "\(homeAccessibleName) win"
            case .draw:
                title = "Draw"
            case .awayWin:
                title = "\(awayAccessibleName) win"
            }
            return "\(title), \(item.accessibilityPercentageText)"
        }
        .joined(separator: "; ")
    }

    private var helpText: String {
        "\(presentation.accessibilitySummary(homeTeamName: homeAccessibleName, awayTeamName: awayAccessibleName)) \(presentation.sourceDescription)."
    }

    private func probabilityLabel(
        item: FootballOutcomeProbabilityPresentation.Item,
        alignment: Alignment
    ) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(outcomeColor(item.outcome))
                .frame(width: 5, height: 5)

            Text(labelTitle(for: item.outcome))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .truncationMode(.tail)

            Text(item.percentageText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: alignment)
        .clipped()
    }

    private func labelTitle(for outcome: FootballOutcomeProbabilityPresentation.Outcome) -> String {
        switch outcome {
        case .homeWin:
            return "\(homeShortName) win"
        case .draw:
            return "Draw"
        case .awayWin:
            return "\(awayShortName) win"
        }
    }

    private func labelAlignment(for index: Int, itemCount: Int) -> Alignment {
        if index == 0 {
            return .leading
        }
        if index == itemCount - 1 {
            return .trailing
        }
        return .center
    }

    private func outcomeColor(_ outcome: FootballOutcomeProbabilityPresentation.Outcome) -> Color {
        switch outcome {
        case .homeWin:
            return Color(nsColor: .systemBlue)
        case .draw:
            return Color(nsColor: .systemGray)
        case .awayWin:
            return Color(nsColor: .systemOrange)
        }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private struct ProbabilitySegmentBar: View {
    let items: [FootballOutcomeProbabilityPresentation.Item]
    let height: CGFloat
    let color: (FootballOutcomeProbabilityPresentation.Outcome) -> Color

    var body: some View {
        GeometryReader { proxy in
            let frames = FootballOutcomeProbabilitySegmentLayout.frames(
                values: items.map(\.probability),
                totalWidth: proxy.size.width
            )

            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Rectangle()
                        .fill(color(item.outcome).opacity(item.probability > 0 ? segmentOpacity(for: item.outcome) : 0))
                        .frame(width: frames[index].width, height: height)
                        .offset(x: frames[index].minX)
                }
            }
        }
        .frame(height: height)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .clipShape(Capsule(style: .continuous))
    }

    private func segmentOpacity(for outcome: FootballOutcomeProbabilityPresentation.Outcome) -> Double {
        outcome == .draw ? 0.75 : 0.82
    }
}
