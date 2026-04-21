import AppKit
import SwiftUI

struct DaylightPreviewArtwork: View {
    let latitude: Double
    let longitude: Double
    let date: Date
    let isEnabled: Bool

    private struct DaylightStrip {
        let rect: CGRect
    }

    private struct DaylightSweepGeometry {
        let strips: [DaylightStrip]
        let leadingBoundarySamples: [CGPoint?]
        let trailingBoundarySamples: [CGPoint?]
    }

    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(origin: .zero, size: geometry.size)
            let mapRect = worldMapRect(in: rect)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.08, blue: 0.16),
                        Color(red: 0.02, green: 0.06, blue: 0.13),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                worldMapBackdrop(mapRect: mapRect)

                Canvas { context, size in
                    let canvasRect = CGRect(origin: .zero, size: size)
                    let canvasMapRect = worldMapRect(in: canvasRect)
                    drawMapChrome(into: &context, mapRect: canvasMapRect)
                    drawDaylightSweep(into: &context, mapRect: canvasMapRect)
                    drawLocationMarker(into: &context, mapRect: canvasMapRect)
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(nsColor: .systemYellow),
                                        Color(nsColor: .systemOrange),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .padding(10)
                            .background(.regularMaterial, in: Circle())
                    }
                }
                .padding(12)

                if !isEnabled {
                    Color.black.opacity(0.18)
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
        ZStack {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.12, blue: 0.20),
                            Color(red: 0.09, green: 0.15, blue: 0.24),
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
                    .clipped()
                    .opacity(0.88)
                    .blendMode(.screen)
            }

            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(Color.black.opacity(0.10))
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

    private func drawMapChrome(into context: inout GraphicsContext, mapRect: CGRect) {
        let borderRect = mapRect.insetBy(dx: 0.5, dy: 0.5)
        context.stroke(
            Path(roundedRect: borderRect, cornerRadius: 18),
            with: .color(.white.opacity(0.14)),
            lineWidth: 1
        )

        let gridColor = Color.white.opacity(0.06)
        for lineIndex in 1..<4 {
            let ratio = CGFloat(lineIndex) / 4.0
            let y = mapRect.minY + (mapRect.height * ratio)
            var path = Path()
            path.move(to: CGPoint(x: mapRect.minX, y: y))
            path.addLine(to: CGPoint(x: mapRect.maxX, y: y))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
        }

        for lineIndex in 1..<6 {
            let ratio = CGFloat(lineIndex) / 6.0
            let x = mapRect.minX + (mapRect.width * ratio)
            var path = Path()
            path.move(to: CGPoint(x: x, y: mapRect.minY))
            path.addLine(to: CGPoint(x: x, y: mapRect.maxY))
            context.stroke(path, with: .color(gridColor), lineWidth: 0.5)
        }
    }

    private func drawDaylightSweep(into context: inout GraphicsContext, mapRect: CGRect) {
        let solarState = DaylightSolarState(date: date)
        let sweepGeometry = buildDaylightSweepGeometry(mapRect: mapRect, solarState: solarState)

        let daylightFill = Gradient(
            colors: [
                Color.white.opacity(0.10),
                Color.white.opacity(0.02),
            ]
        )

        let polygon = daylightPolygonPath(from: sweepGeometry.strips, offset: 0)
        context.fill(polygon, with: .linearGradient(daylightFill, startPoint: CGPoint(x: mapRect.minX, y: mapRect.midY), endPoint: CGPoint(x: mapRect.maxX, y: mapRect.midY)))

        drawBoundary(into: &context, points: sweepGeometry.leadingBoundarySamples, mapRect: mapRect)
        drawBoundary(into: &context, points: sweepGeometry.trailingBoundarySamples, mapRect: mapRect)
    }

    private func drawBoundary(into context: inout GraphicsContext, points: [CGPoint?], mapRect: CGRect) {
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
                context.stroke(path, with: .color(.white.opacity(0.16)), lineWidth: 1)
            }

            previousPoint = point
        }
    }

    private func drawLocationMarker(into context: inout GraphicsContext, mapRect: CGRect) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return }

        let point = CGPoint(
            x: mapRect.minX + CGFloat((longitude + 180.0) / 360.0) * mapRect.width,
            y: mapRect.minY + CGFloat((90.0 - latitude) / 180.0) * mapRect.height
        )

        let outerCircle = Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
        context.fill(outerCircle, with: .color(.white.opacity(0.18)))

        let innerCircle = Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
        context.fill(innerCircle, with: .color(.white.opacity(0.92)))
    }

    private func buildDaylightSweepGeometry(mapRect: CGRect, solarState: DaylightSolarState) -> DaylightSweepGeometry {
        let stripCount = max(Int(mapRect.width / 6.0), 48)
        let stripWidth = mapRect.width / CGFloat(stripCount)
        var strips: [DaylightStrip] = []
        var leadingBoundarySamples: [CGPoint?] = []
        var trailingBoundarySamples: [CGPoint?] = []

        for index in 0..<stripCount {
            let x = mapRect.minX + (CGFloat(index) * stripWidth)
            let longitude = (Double(index) / Double(max(stripCount - 1, 1))) * 360.0 - 180.0
            let solarAltitude = solarAltitudeDegrees(latitude: latitude, longitude: longitude, solarState: solarState)
            let clampedAltitude = max(-90.0, min(90.0, solarAltitude))
            let normalizedHeight = CGFloat((clampedAltitude + 90.0) / 180.0)
            let height = max(mapRect.height * normalizedHeight, 1)
            let rect = CGRect(
                x: x,
                y: mapRect.maxY - height,
                width: stripWidth + 0.5,
                height: height
            )
            strips.append(DaylightStrip(rect: rect))
            let leadingPoint = CGPoint(x: rect.minX, y: rect.minY)
            let trailingPoint = CGPoint(x: rect.maxX, y: rect.minY)
            leadingBoundarySamples.append(leadingPoint)
            trailingBoundarySamples.append(trailingPoint)
        }

        return DaylightSweepGeometry(
            strips: strips,
            leadingBoundarySamples: leadingBoundarySamples,
            trailingBoundarySamples: trailingBoundarySamples
        )
    }

    private func solarAltitudeDegrees(latitude: Double, longitude: Double, solarState: DaylightSolarState) -> Double {
        let latitudeRadians = latitude * .pi / 180.0
        let declinationRadians = solarState.declination * .pi / 180.0
        let hourAngle = (longitude - solarState.subsolarLongitude) * .pi / 180.0
        let sine = sin(latitudeRadians) * sin(declinationRadians)
            + cos(latitudeRadians) * cos(declinationRadians) * cos(hourAngle)
        return asin(max(-1.0, min(1.0, sine))) * 180.0 / .pi
    }

    private func daylightPolygonPath(from strips: [DaylightStrip], offset: CGFloat) -> Path {
        var path = Path()
        guard let firstStrip = strips.first else { return path }

        path.move(to: CGPoint(x: firstStrip.rect.minX + offset, y: firstStrip.rect.minY))
        for strip in strips {
            path.addLine(to: CGPoint(x: strip.rect.minX + offset, y: strip.rect.maxY))
        }
        for strip in strips.reversed() {
            path.addLine(to: CGPoint(x: strip.rect.maxX + offset, y: strip.rect.maxY))
            path.addLine(to: CGPoint(x: strip.rect.maxX + offset, y: strip.rect.minY))
        }
        path.closeSubpath()
        return path
    }

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
