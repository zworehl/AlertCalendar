import SwiftUI

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
    }

    let match: FootballFixtureMatch
    let display: FootballMenuBarDisplay?
    let probabilities: FootballMatchOutcomeProbabilities
    let style: Style
    var availableWidth: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: style.verticalSpacing) {
            HStack(spacing: 6) {
                probabilityLabel(
                    title: nil,
                    value: probabilities.homeWin,
                    color: homeColor,
                    alignment: .leading
                )

                probabilityLabel(
                    title: drawTitle,
                    value: probabilities.draw,
                    color: drawColor,
                    alignment: .center
                )

                probabilityLabel(
                    title: nil,
                    value: probabilities.awayWin,
                    color: awayColor,
                    alignment: .trailing
                )
            }
            .font(style.labelFont)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .center)
            .clipped()

            ProbabilitySegmentBar(
                homeValue: probabilities.homeWin,
                drawValue: probabilities.draw,
                awayValue: probabilities.awayWin,
                height: style.barHeight,
                homeColor: homeColor,
                drawColor: drawColor,
                awayColor: awayColor
            )
        }
        .footballConstrainedWidth(availableWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .help(accessibilityText)
    }

    private var drawTitle: String {
        switch probabilities.scope {
        case .extraTimePossible:
            return "90' draw"
        case .decisiveResult:
            return "Draw"
        case .regulationTime:
            return "Draw"
        }
    }

    private var homeColor: Color {
        Color(nsColor: .systemBlue)
    }

    private var drawColor: Color {
        Color(nsColor: .systemGray)
    }

    private var awayColor: Color {
        Color(nsColor: .systemOrange)
    }

    private var accessibilityText: String {
        let home = display?.homeAbbreviation ?? match.homeTeam.abbreviation
        let away = display?.awayAbbreviation ?? match.awayTeam.abbreviation
        return "\(home) \(percentText(probabilities.homeWin)), \(drawTitle) \(percentText(probabilities.draw)), \(away) \(percentText(probabilities.awayWin))"
    }

    private func probabilityLabel(
        title: String?,
        value: Double,
        color: Color,
        alignment: Alignment
    ) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)

            Text(probabilityLabelText(title: title, value: value))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: alignment)
        .clipped()
    }

    private func probabilityLabelText(title: String?, value: Double) -> String {
        guard let title else { return percentText(value) }
        return "\(title) \(percentText(value))"
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct ProbabilitySegmentBar: View {
    let homeValue: Double
    let drawValue: Double
    let awayValue: Double
    let height: CGFloat
    let homeColor: Color
    let drawColor: Color
    let awayColor: Color

    var body: some View {
        GeometryReader { proxy in
            let widths = segmentWidths(totalWidth: proxy.size.width)

            HStack(spacing: 0) {
                Rectangle()
                    .fill(homeColor.opacity(0.82))
                .frame(width: widths.home)

                Rectangle()
                    .fill(drawColor.opacity(drawValue > 0 ? 0.75 : 0))
                    .frame(width: widths.draw)

                Rectangle()
                    .fill(awayColor.opacity(0.82))
                .frame(width: widths.away)
            }
        }
        .frame(height: height)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .clipShape(Capsule(style: .continuous))
    }

    private func segmentWidths(totalWidth: CGFloat) -> (home: CGFloat, draw: CGFloat, away: CGFloat) {
        guard totalWidth > 0 else { return (0, 0, 0) }
        let values = [homeValue, drawValue, awayValue].map { max(0, $0) }
        let total = values.reduce(0, +)
        guard total > 0 else { return (0, 0, totalWidth) }

        let normalized = values.map { $0 / total }
        var widths = normalized.map { CGFloat($0) * totalWidth }
        let minimumVisibleWidth = min(CGFloat(2), totalWidth / 6)

        for index in widths.indices where normalized[index] > 0 && widths[index] < minimumVisibleWidth {
            widths[index] = minimumVisibleWidth
        }

        let adjustedTotal = widths.reduce(0, +)
        if adjustedTotal > totalWidth {
            let scale = totalWidth / adjustedTotal
            widths = widths.map { $0 * scale }
        } else {
            widths[2] += totalWidth - adjustedTotal
        }

        return (widths[0], widths[1], widths[2])
    }
}
