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
                Self.clockMapBackground

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
                    Color.black.opacity(0.34)
                    Text("Enable sun moments to show this map in Feeds.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.62), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func worldMapBackdrop(mapRect: CGRect) -> some View {
        let mapShape = RoundedRectangle(cornerRadius: Self.mapCornerRadius, style: .continuous)

        ZStack {
            mapShape
                .fill(Self.clockMapOcean)

            if let landMaskImage = Self.clockMapLandMaskImage {
                Self.clockMapLand
                    .mask {
                        clockMapImage(landMaskImage, mapRect: mapRect)
                    }
                    .clipShape(mapShape)

                Self.clockMapLand
                    .opacity(0.34)
                    .mask {
                        clockMapImage(landMaskImage, mapRect: mapRect)
                            .blur(radius: 0.55)
                    }
                    .clipShape(mapShape)
            } else if let worldMapImage = Self.worldMapImage {
                Self.clockMapLand
                    .mask {
                        clockMapImage(worldMapImage, mapRect: mapRect)
                            .saturation(0)
                            .contrast(2.4)
                            .brightness(-0.34)
                            .luminanceToAlpha()
                    }
                    .clipShape(mapShape)
            }
        }
        .frame(width: mapRect.width, height: mapRect.height)
        .position(x: mapRect.midX, y: mapRect.midY)
    }

    private func clockMapImage(_ image: NSImage, mapRect: CGRect) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: mapRect.width, height: mapRect.height)
    }

    private func worldMapRect(in rect: CGRect) -> CGRect {
        let targetAspect: CGFloat = Self.worldMapAspectRatio
        let width = rect.width
        let height = width / targetAspect
        let y = rect.midY - (height / 2)
        return CGRect(x: rect.minX, y: y, width: width, height: height)
    }

    private func drawMapGrid(into context: inout GraphicsContext, mapRect: CGRect) {
        let verticalGridColor = Color.white.opacity(0.115)
        let horizontalGridColor = Color.white.opacity(0.022)

        for lineIndex in 1..<4 {
            let ratio = CGFloat(lineIndex) / 4.0
            let y = mapRect.minY + (mapRect.height * ratio)
            var path = Path()
            path.move(to: CGPoint(x: mapRect.minX, y: y))
            path.addLine(to: CGPoint(x: mapRect.maxX, y: y))
            context.stroke(path, with: .color(horizontalGridColor), lineWidth: 0.45)
        }

        for lineIndex in 1..<12 {
            let ratio = CGFloat(lineIndex) / 12.0
            let x = mapRect.minX + (mapRect.width * ratio)
            var path = Path()
            path.move(to: CGPoint(x: x, y: mapRect.minY))
            path.addLine(to: CGPoint(x: x, y: mapRect.maxY))
            context.stroke(path, with: .color(verticalGridColor), lineWidth: 0.55)
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
                case ..<(-6):
                    deepNightPath.addRect(rect)
                case ..<0:
                    twilightPath.addRect(rect)
                default:
                    continue
                }
            }
        }

        context.fill(deepNightPath, with: .color(Color.black.opacity(0.72)))
        context.fill(twilightPath, with: .color(Color.black.opacity(0.44)))
    }

    private func drawTerminatorCurves(
        into context: inout GraphicsContext,
        mapRect: CGRect,
        solarState: DaylightSolarState
    ) {
        let curves = buildTerminatorCurves(mapRect: mapRect, solarState: solarState)
        drawBoundary(into: &context, points: curves.westernPoints, color: .white.opacity(0.42))
        drawBoundary(into: &context, points: curves.easternPoints, color: .white.opacity(0.42))
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
                context.stroke(path, with: .color(color), lineWidth: 1.05)
            }

            previousPoint = point
        }
    }

    private func drawLocationMarker(into context: inout GraphicsContext, mapRect: CGRect) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return }

        let point = Self.point(latitude: latitude, longitude: longitude, in: mapRect)
        let shadowCircle = Path(ellipseIn: CGRect(x: point.x - 5.25, y: point.y - 4.75, width: 10.5, height: 10.5))
        context.fill(shadowCircle, with: .color(Color.black.opacity(0.50)))

        let markerCircle = Path(ellipseIn: CGRect(x: point.x - 3.35, y: point.y - 3.35, width: 6.7, height: 6.7))
        context.fill(markerCircle, with: .color(Self.clockMapOrange))
    }

    private func drawMapBorder(into context: inout GraphicsContext, mapRect: CGRect) {
        let borderRect = mapRect.insetBy(dx: 0.5, dy: 0.5)
        context.stroke(
            Path(roundedRect: borderRect, cornerRadius: Self.mapCornerRadius),
            with: .color(.white.opacity(0.08)),
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

    private static let mapCornerRadius: CGFloat = 0
    nonisolated static let preferredAspectRatio: CGFloat = 2104.0 / 964.0
    private static let worldMapAspectRatio: CGFloat = preferredAspectRatio
    private static let clockMapBackground = Color.black
    private static let clockMapOcean = Color.black
    private static let clockMapLand = Color(red: 0.31, green: 0.31, blue: 0.30)
    private static let clockMapOrange = Color(red: 1.0, green: 0.553, blue: 0.157)
    private static let clockMapLandMaskImage: NSImage? = {
        guard let worldMapImage else { return nil }
        return makeClockStyleLandMask(from: worldMapImage)
    }()
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

    private static func makeClockStyleLandMask(from image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        var sourcePixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        var maskPixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let sourceContext = CGContext(
            data: &sourcePixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        sourceContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        for index in stride(from: 0, to: sourcePixels.count, by: bytesPerPixel) {
            let red = Double(sourcePixels[index]) / 255.0
            let green = Double(sourcePixels[index + 1]) / 255.0
            let blue = Double(sourcePixels[index + 2]) / 255.0
            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let brightness = (red + green + blue) / 3.0
            let warmLand = (red * 0.54 + green * 0.46) - blue
            let greenLand = green - (blue * 0.76) - (red * 0.05)
            let ice = brightness > 0.76 && maximum - minimum < 0.18
                ? (brightness - 0.76) * 2.4
                : -1.0
            let alpha = smoothstep(-0.01, 0.13, max(warmLand, greenLand, ice))
            let alphaByte = UInt8((alpha * 255.0).rounded())

            maskPixels[index] = alphaByte
            maskPixels[index + 1] = alphaByte
            maskPixels[index + 2] = alphaByte
            maskPixels[index + 3] = alphaByte
        }

        guard let provider = CGDataProvider(data: Data(maskPixels) as CFData),
              let maskImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        return NSImage(cgImage: maskImage, size: NSSize(width: width, height: height))
    }

    private static func smoothstep(_ lowerBound: Double, _ upperBound: Double, _ value: Double) -> Double {
        guard upperBound > lowerBound else {
            return value >= upperBound ? 1.0 : 0.0
        }

        let progress = max(0.0, min(1.0, (value - lowerBound) / (upperBound - lowerBound)))
        return progress * progress * (3.0 - 2.0 * progress)
    }
}
