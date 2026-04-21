import AppKit
import SwiftUI

struct DaylightPreviewArtwork: View {
    let latitude: Double
    let longitude: Double
    let date: Date
    let isEnabled: Bool

    private struct TerminatorCurves {
        let westernPoints: [CGPoint?]
        let easternPoints: [CGPoint?]
    }

    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            let mapRect = worldMapRect(in: rect)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.07, blue: 0.13),
                        Color(red: 0.02, green: 0.05, blue: 0.10),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                worldMapBackdrop(mapRect: mapRect)

                Canvas { context, size in
                    let canvasRect = CGRect(origin: .zero, size: size)
                    let canvasMapRect = worldMapRect(in: canvasRect)
                    let mapPath = Path(roundedRect: canvasMapRect, cornerRadius: Self.mapCornerRadius)
                    let solarState = DaylightSolarState(date: date)

                    var clippedContext = context
                    clippedContext.clip(to: mapPath)
                    drawMapGrid(into: &clippedContext, mapRect: canvasMapRect)
                    drawNightOverlay(into: &clippedContext, mapRect: canvasMapRect, solarState: solarState)
                    drawTerminatorCurves(into: &clippedContext, mapRect: canvasMapRect, solarState: solarState)
                    drawLocationMarker(into: &clippedContext, mapRect: canvasMapRect)

                    drawMapBorder(into: &context, mapRect: canvasMapRect)
                }

                if !isEnabled {
                    Color.black.opacity(0.20)
                    Text("Enable sun moments to show this map in Feeds.")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func worldMapBackdrop(mapRect: CGRect) -> some View {
        let mapShape = RoundedRectangle(cornerRadius: Self.mapCornerRadius, style: .continuous)

        ZStack {
            mapShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.12, blue: 0.21),
                            Color(red: 0.04, green: 0.09, blue: 0.17),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let worldMapImage = Self.worldMapImage {
                Image(nsImage: worldMapImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: mapRect.width, height: mapRect.height)
                    .saturation(0.84)
                    .contrast(1.02)
                    .brightness(-0.04)
                    .opacity(0.76)
                    .clipShape(mapShape)
            }

            mapShape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color.clear,
                            Color.black.opacity(0.08),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .frame(width: mapRect.width, height: mapRect.height)
        .position(x: mapRect.midX, y: mapRect.midY)
    }

    private func worldMapRect(in rect: CGRect) -> CGRect {
        let targetAspect: CGFloat = Self.worldMapAspectRatio
        let width = rect.width
        let height = width / targetAspect
        let y = rect.midY - (height / 2)
        return CGRect(x: rect.minX, y: y, width: width, height: height)
    }

    private func drawMapGrid(into context: inout GraphicsContext, mapRect: CGRect) {
        let gridColor = Color.white.opacity(0.08)

        for lineIndex in 1..<4 {
            let ratio = CGFloat(lineIndex) / 4.0
            let y = mapRect.minY + (mapRect.height * ratio)
            var path = Path()
            path.move(to: CGPoint(x: mapRect.minX, y: y))
            path.addLine(to: CGPoint(x: mapRect.maxX, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.6)
        }

        for lineIndex in 1..<6 {
            let ratio = CGFloat(lineIndex) / 6.0
            let x = mapRect.minX + (mapRect.width * ratio)
            var path = Path()
            path.move(to: CGPoint(x: x, y: mapRect.minY))
            path.addLine(to: CGPoint(x: x, y: mapRect.maxY))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.6)
        }
    }

    private func drawNightOverlay(
        into context: inout GraphicsContext,
        mapRect: CGRect,
        solarState: DaylightSolarState
    ) {
        let columnCount = max(Int(mapRect.width / 5.0), 96)
        let rowCount = max(Int(mapRect.height / 5.0), 48)
        let cellWidth = mapRect.width / CGFloat(columnCount)
        let cellHeight = mapRect.height / CGFloat(rowCount)

        var deepNightPath = Path()
        var twilightPath = Path()
        var daylightGlowPath = Path()

        for row in 0..<rowCount {
            let cellY = mapRect.minY + CGFloat(row) * cellHeight
            let sampleY = cellY + (cellHeight / 2.0)
            let sampleLatitude = Self.latitude(forY: sampleY, in: mapRect)

            for column in 0..<columnCount {
                let cellX = mapRect.minX + CGFloat(column) * cellWidth
                let sampleX = cellX + (cellWidth / 2.0)
                let sampleLongitude = Self.longitude(forX: sampleX, in: mapRect)
                let altitude = Self.solarAltitudeDegrees(
                    latitude: sampleLatitude,
                    longitude: sampleLongitude,
                    solarState: solarState
                )

                let rect = CGRect(
                    x: cellX,
                    y: cellY,
                    width: cellWidth + 0.75,
                    height: cellHeight + 0.75
                )

                switch altitude {
                case ..<(-12):
                    deepNightPath.addRect(rect)
                case ..<0:
                    twilightPath.addRect(rect)
                case ..<6:
                    daylightGlowPath.addRect(rect)
                default:
                    continue
                }
            }
        }

        context.fill(deepNightPath, with: .color(Color.black.opacity(0.38)))
        context.fill(twilightPath, with: .color(Color(red: 0.05, green: 0.08, blue: 0.14).opacity(0.24)))
        context.fill(daylightGlowPath, with: .color(Color(red: 1.0, green: 0.90, blue: 0.68).opacity(0.08)))
    }

    private func drawTerminatorCurves(
        into context: inout GraphicsContext,
        mapRect: CGRect,
        solarState: DaylightSolarState
    ) {
        let curves = buildTerminatorCurves(mapRect: mapRect, solarState: solarState)
        drawBoundary(into: &context, points: curves.westernPoints, color: .white.opacity(0.34))
        drawBoundary(into: &context, points: curves.easternPoints, color: Color(red: 1.0, green: 0.90, blue: 0.68).opacity(0.28))
    }

    private func buildTerminatorCurves(mapRect: CGRect, solarState: DaylightSolarState) -> TerminatorCurves {
        let sampleCount = max(Int(mapRect.height / 4.0), 48)
        var westernPoints: [CGPoint?] = []
        var easternPoints: [CGPoint?] = []
        var previousWesternPoint: CGPoint?
        var previousEasternPoint: CGPoint?

        for index in 0...sampleCount {
            let ratio = CGFloat(index) / CGFloat(sampleCount)
            let latitude = 90.0 - (Double(ratio) * 180.0)
            let y = mapRect.minY + (mapRect.height * ratio)

            guard let boundary = Self.terminatorLongitudes(for: latitude, solarState: solarState) else {
                westernPoints.append(nil)
                easternPoints.append(nil)
                previousWesternPoint = nil
                previousEasternPoint = nil
                continue
            }

            let westernPoint = CGPoint(
                x: Self.xPosition(for: boundary.west, in: mapRect),
                y: y
            )
            let easternPoint = CGPoint(
                x: Self.xPosition(for: boundary.east, in: mapRect),
                y: y
            )

            appendBoundaryPoint(
                westernPoint,
                to: &westernPoints,
                previousPoint: &previousWesternPoint,
                mapRect: mapRect
            )
            appendBoundaryPoint(
                easternPoint,
                to: &easternPoints,
                previousPoint: &previousEasternPoint,
                mapRect: mapRect
            )
        }

        return TerminatorCurves(
            westernPoints: westernPoints,
            easternPoints: easternPoints
        )
    }

    private func appendBoundaryPoint(
        _ point: CGPoint,
        to points: inout [CGPoint?],
        previousPoint: inout CGPoint?,
        mapRect: CGRect
    ) {
        if let previousPoint, abs(point.x - previousPoint.x) > mapRect.width * 0.45 {
            points.append(nil)
        }

        points.append(point)
        previousPoint = point
    }

    private func drawBoundary(into context: inout GraphicsContext, points: [CGPoint?], color: Color) {
        var previousPoint: CGPoint?

        for point in points {
            guard let point else {
                previousPoint = nil
                continue
            }

            if let previousPoint {
                var path = Path()
                path.move(to: previousPoint)
                path.addLine(to: point)
                context.stroke(path, with: .color(color), lineWidth: 1.15)
            }

            previousPoint = point
        }
    }

    private func drawLocationMarker(into context: inout GraphicsContext, mapRect: CGRect) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return }

        let point = Self.point(latitude: latitude, longitude: longitude, in: mapRect)
        let haloCircle = Path(ellipseIn: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20))
        context.fill(haloCircle, with: .color(Color.white.opacity(0.12)))

        let outerCircle = Path(ellipseIn: CGRect(x: point.x - 5.5, y: point.y - 5.5, width: 11, height: 11))
        context.fill(outerCircle, with: .color(Color(red: 0.98, green: 0.95, blue: 0.84).opacity(0.95)))

        let innerCircle = Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
        context.fill(innerCircle, with: .color(Color(red: 0.09, green: 0.18, blue: 0.33)))
    }

    private func drawMapBorder(into context: inout GraphicsContext, mapRect: CGRect) {
        let borderRect = mapRect.insetBy(dx: 0.5, dy: 0.5)
        context.stroke(
            Path(roundedRect: borderRect, cornerRadius: Self.mapCornerRadius),
            with: .color(.white.opacity(0.18)),
            lineWidth: 1
        )
    }

    nonisolated static func terminatorLongitudes(
        for latitude: Double,
        solarState: DaylightSolarState
    ) -> (west: Double, east: Double)? {
        let latitudeRadians = latitude * .pi / 180.0
        let declinationRadians = solarState.declination * .pi / 180.0
        let cosineHourAngle = -tan(latitudeRadians) * tan(declinationRadians)

        guard cosineHourAngle.isFinite, (-1.0...1.0).contains(cosineHourAngle) else {
            return nil
        }

        let hourAngleDegrees = acos(cosineHourAngle) * 180.0 / .pi
        return (
            west: normalizedLongitude(solarState.subsolarLongitude - hourAngleDegrees),
            east: normalizedLongitude(solarState.subsolarLongitude + hourAngleDegrees)
        )
    }

    nonisolated static func solarAltitudeDegrees(
        latitude: Double,
        longitude: Double,
        solarState: DaylightSolarState
    ) -> Double {
        let latitudeRadians = latitude * .pi / 180.0
        let declinationRadians = solarState.declination * .pi / 180.0
        let hourAngle = (longitude - solarState.subsolarLongitude) * .pi / 180.0
        let sine = sin(latitudeRadians) * sin(declinationRadians)
            + cos(latitudeRadians) * cos(declinationRadians) * cos(hourAngle)
        return asin(max(-1.0, min(1.0, sine))) * 180.0 / .pi
    }

    nonisolated static func point(latitude: Double, longitude: Double, in mapRect: CGRect) -> CGPoint {
        CGPoint(
            x: xPosition(for: longitude, in: mapRect),
            y: mapRect.minY + CGFloat((90.0 - latitude) / 180.0) * mapRect.height
        )
    }

    nonisolated static func latitude(forY y: CGFloat, in mapRect: CGRect) -> Double {
        90.0 - Double((y - mapRect.minY) / mapRect.height) * 180.0
    }

    nonisolated static func longitude(forX x: CGFloat, in mapRect: CGRect) -> Double {
        Double((x - mapRect.minX) / mapRect.width) * 360.0 - 180.0
    }

    nonisolated static func xPosition(for longitude: Double, in mapRect: CGRect) -> CGFloat {
        mapRect.minX + CGFloat((normalizedLongitude(longitude) + 180.0) / 360.0) * mapRect.width
    }

    nonisolated static func normalizedLongitude(_ longitude: Double) -> Double {
        var value = longitude.truncatingRemainder(dividingBy: 360.0)
        if value > 180.0 {
            value -= 360.0
        } else if value < -180.0 {
            value += 360.0
        }
        return value
    }

    private static let mapCornerRadius: CGFloat = 16
    private static let worldMapAspectRatio: CGFloat = 2.0
    private static let worldMapImage: NSImage? = {
        let bundle = Bundle.module
        let candidateURLs = [
            bundle.url(forResource: "earth-blue-marble", withExtension: "png"),
            bundle.url(forResource: "earth-blue-marble", withExtension: "png", subdirectory: "Resources/Images"),
        ]

        for url in candidateURLs.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }()
}
