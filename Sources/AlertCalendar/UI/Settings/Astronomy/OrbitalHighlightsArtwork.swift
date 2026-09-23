import AppKit
import SwiftUI

struct OrbitalHighlightsArtwork: View {
    let preview: [SettingsAstronomySectionView.AstronomyPreviewMoment]
    let date: Date
    let isEnabled: Bool

    private struct OrbitalGeometry {
        let center: CGPoint
        let semiMajorAxis: CGFloat
        let semiMinorAxis: CGFloat
        let focusOffset: CGFloat

        var rect: CGRect {
            CGRect(
                x: center.x - semiMajorAxis,
                y: center.y - semiMinorAxis,
                width: semiMajorAxis * 2,
                height: semiMinorAxis * 2
            )
        }

        var sunCenter: CGPoint {
            CGPoint(x: center.x - focusOffset, y: center.y)
        }
    }

    private struct OrbitalMilestone {
        let moment: AstronomyMoment
        let date: Date
        let label: String
        let color: Color
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                drawBackground(into: &context, rect: rect)
                drawStars(into: &context, rect: rect)
                let geometry = orbitGeometry(in: rect)
                let milestones = orbitalMilestones(for: date)
                drawOrbit(into: &context, geometry: geometry)
                drawOrbitProgress(into: &context, geometry: geometry)
                drawSun(into: &context, center: geometry.sunCenter)
                drawMilestones(into: &context, geometry: geometry, milestones: milestones)
                drawCurrentPosition(into: &context, geometry: geometry)
            }

            VStack {
                HStack {
                    if let next = preview.first {
                        highlightPill(
                            title: next.moment.title,
                            subtitle: formattedUpcomingHighlight(next.date)
                        )
                    } else {
                        highlightPill(
                            title: "Orbital Highlights",
                            subtitle: "Current position around the Sun"
                        )
                    }
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    highlightPill(
                        title: "Now",
                        subtitle: orbitProgressSummary
                    )
                }
            }
            .padding(12)

            if !isEnabled {
                Color.black.opacity(0.18)
                Text("Enable orbital highlights to show these milestones in Feeds.")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }

    private func drawBackground(into context: inout GraphicsContext, rect: CGRect) {
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.11),
                    Color(red: 0.07, green: 0.10, blue: 0.20),
                    Color(red: 0.04, green: 0.06, blue: 0.14),
                ]),
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            )
        )
    }

    private func drawStars(into context: inout GraphicsContext, rect: CGRect) {
        for star in Self.starField {
            let point = CGPoint(x: rect.minX + (star.x * rect.width), y: rect.minY + (star.y * rect.height))
            let starRect = CGRect(x: point.x - star.size / 2, y: point.y - star.size / 2, width: star.size, height: star.size)
            context.fill(Path(ellipseIn: starRect), with: .color(Color.white.opacity(star.opacity)))
        }
    }

    private func orbitGeometry(in rect: CGRect) -> OrbitalGeometry {
        let horizontalInset = rect.width * 0.12
        let verticalInset = rect.height * 0.15
        let availableWidth = max(120, rect.width - (horizontalInset * 2))
        let availableHeight = max(120, rect.height - (verticalInset * 2))
        let semiMajorAxis = min(availableWidth * 0.5, availableHeight * 0.5 / Self.earthOrbitAxisRatio)
        let semiMinorAxis = semiMajorAxis * Self.earthOrbitAxisRatio

        return OrbitalGeometry(
            center: CGPoint(x: rect.midX, y: rect.midY),
            semiMajorAxis: semiMajorAxis,
            semiMinorAxis: semiMinorAxis,
            focusOffset: semiMajorAxis * Self.earthOrbitEccentricity
        )
    }

    private func drawOrbit(into context: inout GraphicsContext, geometry: OrbitalGeometry) {
        context.stroke(
            Path(ellipseIn: geometry.rect),
            with: .color(Color.white.opacity(0.18)),
            style: StrokeStyle(lineWidth: 2)
        )
    }

    private func drawOrbitProgress(into context: inout GraphicsContext, geometry: OrbitalGeometry) {
        let progressPath = orbitalProgressPath(in: geometry, endDate: date)
        context.stroke(
            progressPath,
            with: .color(Color(nsColor: .systemOrange).opacity(0.75)),
            style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawSun(into context: inout GraphicsContext, center: CGPoint) {
        let glowRect = CGRect(x: center.x - 24, y: center.y - 24, width: 48, height: 48)
        let coreRect = CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24)
        context.fill(Path(ellipseIn: glowRect), with: .color(Color(nsColor: .systemOrange).opacity(0.26)))
        context.fill(Path(ellipseIn: coreRect), with: .color(Color(nsColor: .systemYellow)))
    }

    private func drawMilestones(
        into context: inout GraphicsContext,
        geometry: OrbitalGeometry,
        milestones: [OrbitalMilestone]
    ) {
        for milestone in milestones {
            let point = pointOnOrbit(in: geometry, date: milestone.date)
            let markerRect = CGRect(x: point.x - 4.6, y: point.y - 4.6, width: 9.2, height: 9.2)
            context.fill(Path(ellipseIn: markerRect), with: .color(milestone.color.opacity(0.96)))
            context.stroke(Path(ellipseIn: markerRect), with: .color(Color.white.opacity(0.72)), lineWidth: 1)
            drawMilestoneLabel(into: &context, point: point, milestone: milestone)
        }
    }

    private func drawMilestoneLabel(
        into context: inout GraphicsContext,
        point: CGPoint,
        milestone: OrbitalMilestone
    ) {
        let layout = milestoneLabelLayout(for: milestone.moment)
        let drawPoint = CGPoint(
            x: point.x + layout.offset.width,
            y: point.y + layout.offset.height
        )

        context.draw(
            Text(milestone.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.78)),
            at: drawPoint,
            anchor: layout.anchor
        )
    }

    private func drawCurrentPosition(
        into context: inout GraphicsContext,
        geometry: OrbitalGeometry
    ) {
        let point = pointOnOrbit(in: geometry, date: date)

        var beam = Path()
        beam.move(to: geometry.sunCenter)
        beam.addLine(to: point)
        context.stroke(beam, with: .color(Color.white.opacity(0.18)), lineWidth: 1.2)

        let glowRect = CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
        let outerRect = CGRect(x: point.x - 6.5, y: point.y - 6.5, width: 13, height: 13)
        let coreRect = CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9)
        context.fill(Path(ellipseIn: glowRect), with: .color(Color.white.opacity(0.14)))
        context.fill(Path(ellipseIn: outerRect), with: .color(Color(red: 0.14, green: 0.29, blue: 0.62)))
        context.fill(Path(ellipseIn: coreRect), with: .color(Color(red: 0.34, green: 0.71, blue: 0.42)))
        context.stroke(Path(ellipseIn: outerRect), with: .color(Color.white.opacity(0.85)), lineWidth: 1.1)

        let layout = annotationLayout(for: point, center: geometry.center)

        context.draw(
            Text("Now")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.92)),
            at: CGPoint(x: point.x + layout.offset.width, y: point.y + layout.offset.height),
            anchor: layout.anchor
        )
    }

    private func milestoneLabelLayout(for moment: AstronomyMoment) -> (offset: CGSize, anchor: UnitPoint) {
        switch moment {
        case .perihelion:
            return (CGSize(width: -12, height: 12), .topTrailing)
        case .marchEquinox:
            return (CGSize(width: 0, height: -12), .bottom)
        case .juneSolstice:
            return (CGSize(width: 14, height: -10), .bottomLeading)
        case .aphelion:
            return (CGSize(width: 14, height: 8), .topLeading)
        case .septemberEquinox:
            return (CGSize(width: 0, height: 14), .top)
        case .decemberSolstice:
            return (CGSize(width: -12, height: 10), .topTrailing)
        default:
            return (CGSize(width: 12, height: -12), .bottomLeading)
        }
    }

    private func annotationLayout(for point: CGPoint, center: CGPoint) -> (offset: CGSize, anchor: UnitPoint) {
        let isLeadingSide = point.x <= center.x
        let isTopSide = point.y <= center.y

        switch (isLeadingSide, isTopSide) {
        case (true, true):
            return (CGSize(width: -12, height: -12), .bottomTrailing)
        case (true, false):
            return (CGSize(width: -12, height: 12), .topTrailing)
        case (false, true):
            return (CGSize(width: 12, height: -12), .bottomLeading)
        case (false, false):
            return (CGSize(width: 12, height: 12), .topLeading)
        }
    }

    private func pointOnOrbit(in geometry: OrbitalGeometry, phase: CGFloat) -> CGPoint {
        CGPoint(
            x: geometry.center.x + (cos(phase) * geometry.semiMajorAxis),
            y: geometry.center.y + (sin(phase) * geometry.semiMinorAxis)
        )
    }

    private func pointOnOrbit(in geometry: OrbitalGeometry, date: Date) -> CGPoint {
        pointOnOrbit(in: geometry, phase: orbitalPhase(for: date))
    }

    private func orbitalProgressPath(in geometry: OrbitalGeometry, endDate: Date) -> Path {
        var path = Path()
        let endAnomaly = orbitalEccentricAnomaly(for: endDate)
        let samples = 120

        for index in 0 ... samples {
            let progress = CGFloat(index) / CGFloat(samples)
            let anomaly = CGFloat(endAnomaly) * progress
            let point = pointOnOrbit(in: geometry, phase: .pi + anomaly)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    private func orbitalPhase(for date: Date) -> CGFloat {
        .pi + CGFloat(orbitalEccentricAnomaly(for: date))
    }

    private func orbitalEccentricAnomaly(for date: Date) -> Double {
        let meanAnomaly = orbitalProgress(for: date) * .pi * 2
        var eccentricAnomaly = meanAnomaly

        for _ in 0 ..< 6 {
            let numerator = eccentricAnomaly - (Self.earthOrbitEccentricity * sin(eccentricAnomaly)) - meanAnomaly
            let denominator = max(0.0001, 1 - (Self.earthOrbitEccentricity * cos(eccentricAnomaly)))
            eccentricAnomaly -= numerator / denominator
        }

        return eccentricAnomaly
    }

    private func orbitalProgress(for date: Date) -> Double {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let referencePerihelion = calendar.date(from: DateComponents(year: year, month: 1, day: 3, hour: 0)) ?? date
        let nextPerihelion = calendar.date(byAdding: .year, value: 1, to: referencePerihelion) ?? referencePerihelion.addingTimeInterval(365.2422 * 86_400)
        let cycleDuration = max(1, nextPerihelion.timeIntervalSince(referencePerihelion))
        let normalizedProgress = ((date.timeIntervalSince(referencePerihelion) / cycleDuration).truncatingRemainder(dividingBy: 1) + 1)
            .truncatingRemainder(dividingBy: 1)
        return normalizedProgress
    }

    private func orbitalMilestones(for date: Date) -> [OrbitalMilestone] {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)

        let definitions: [(AstronomyMoment, DateComponents, String, NSColor)] = [
            (.perihelion, DateComponents(year: year, month: 1, day: 3, hour: 0), "Peri", .systemYellow),
            (.marchEquinox, DateComponents(year: year, month: 3, day: 20, hour: 0), "Mar Eq.", .systemGreen),
            (.juneSolstice, DateComponents(year: year, month: 6, day: 21, hour: 0), "Jun Sol.", .systemTeal),
            (.aphelion, DateComponents(year: year, month: 7, day: 4, hour: 0), "Aphe", .systemBlue),
            (.septemberEquinox, DateComponents(year: year, month: 9, day: 22, hour: 0), "Sep Eq.", .systemOrange),
            (.decemberSolstice, DateComponents(year: year, month: 12, day: 21, hour: 0), "Dec Sol.", .systemPurple),
        ]

        return definitions.compactMap { moment, components, label, color in
            guard let eventDate = calendar.date(from: components) else { return nil }
            return OrbitalMilestone(
                moment: moment,
                date: eventDate,
                label: label,
                color: Color(nsColor: color)
            )
        }
    }

    private func formattedUpcomingHighlight(_ date: Date) -> String {
        Self.highlightFormatter.string(from: date)
    }

    private var orbitProgressSummary: String {
        "\(Int((orbitalProgress(for: date) * 100).rounded()))% of current solar year"
    }

    private static let starField: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (0.08, 0.14, 2.0, 0.70), (0.16, 0.70, 1.6, 0.52), (0.28, 0.12, 1.4, 0.56),
        (0.38, 0.82, 1.8, 0.44), (0.48, 0.18, 2.2, 0.68), (0.58, 0.66, 1.4, 0.55),
        (0.72, 0.24, 1.8, 0.48), (0.82, 0.74, 2.0, 0.60), (0.90, 0.18, 1.6, 0.52),
    ]
    private static let earthOrbitEccentricity: CGFloat = 0.0167
    private static let earthOrbitAxisRatio = sqrt(1 - (earthOrbitEccentricity * earthOrbitEccentricity))

    private static let highlightFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AlertCalendarLanguage.english
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
