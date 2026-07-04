import AppKit
import CoreLocation
import MapKit
import SwiftUI

private enum MiniLocationMapPreviewTiming {
    static let loadingTimeoutNanoseconds: UInt64 = 8_000_000_000
    static let snapshotTimeoutSeconds: TimeInterval = 6
}

private enum MiniLocationMapPreviewSnapshot {
    static let minimumWidth: CGFloat = 120
}

private struct MiniLocationMapSnapshotRequest: Hashable, Sendable {
    let locationText: String
    let width: Int
    let height: Int

    var size: CGSize {
        CGSize(width: width, height: height)
    }
}

struct MiniLocationMapView: View {
    let locationText: String
    let preferredHeight: CGFloat

    @State private var snapshotData: Data?
    @State private var isLoading = false
    @State private var requestedSnapshotRequest: MiniLocationMapSnapshotRequest?
    @State private var resolveTask: Task<Void, Never>?
    @State private var loadingTimeoutTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Location Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let request = snapshotRequest(for: proxy.size)

                ZStack {
                    if let snapshotData,
                       let snapshotImage = NSImage(data: snapshotData) {
                        Image(nsImage: snapshotImage)
                            .resizable()
                            .interpolation(.medium)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                        Text(isLoading ? "Loading map..." : "Map unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .task(id: request) {
                    await resolveLocation(request: request)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: preferredHeight)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onDisappear {
            resolveTask?.cancel()
            resolveTask = nil
            loadingTimeoutTask?.cancel()
            loadingTimeoutTask = nil
        }
    }

    private func snapshotRequest(for size: CGSize) -> MiniLocationMapSnapshotRequest {
        MiniLocationMapSnapshotRequest(
            locationText: locationText,
            width: max(Int(MiniLocationMapPreviewSnapshot.minimumWidth), Int(size.width.rounded(.toNearestOrAwayFromZero))),
            height: max(80, Int(size.height.rounded(.toNearestOrAwayFromZero)))
        )
    }

    @MainActor
    private func resolveLocation(request: MiniLocationMapSnapshotRequest) async {
        let trimmed = request.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || request.width <= 0 || request.height <= 0 {
            resolveTask?.cancel()
            resolveTask = nil
            loadingTimeoutTask?.cancel()
            loadingTimeoutTask = nil
            requestedSnapshotRequest = nil
            isLoading = false
            snapshotData = nil
            return
        }
        if requestedSnapshotRequest == request,
           (isLoading || snapshotData != nil) {
            return
        }

        requestedSnapshotRequest = request
        isLoading = true
        snapshotData = nil
        resolveTask?.cancel()
        loadingTimeoutTask?.cancel()
        loadingTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: MiniLocationMapPreviewTiming.loadingTimeoutNanoseconds)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard requestedSnapshotRequest == request,
                      isLoading else { return }
                isLoading = false
                snapshotData = nil
                resolveTask?.cancel()
                resolveTask = nil
                loadingTimeoutTask = nil
            }
        }
        resolveTask = Task {
            let coordinate = await LocationCoordinateResolver.shared.coordinate(for: request.locationText)
            guard !Task.isCancelled else { return }
            let imageData = await MiniLocationMapSnapshotRenderer.snapshotData(
                for: coordinate?.clCoordinate,
                size: request.size
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard request.locationText == locationText,
                      requestedSnapshotRequest == request else { return }
                loadingTimeoutTask?.cancel()
                loadingTimeoutTask = nil
                isLoading = false
                resolveTask = nil
                snapshotData = imageData
            }
        }
    }
}

private enum MiniLocationMapSnapshotRenderer {
    static func snapshotData(for coordinate: CLLocationCoordinate2D?, size: CGSize) async -> Data? {
        guard let coordinate else { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let box = MapSnapshotContinuationBox(continuation)
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
            options.size = CGSize(
                width: max(MiniLocationMapPreviewSnapshot.minimumWidth, size.width),
                height: max(80, size.height)
            )
            options.mapType = .mutedStandard

            let snapshotter = MKMapSnapshotter(options: options)
            let timeout = MapSnapshotTimeoutWorkItem {
                snapshotter.cancel()
                box.resume(returning: nil)
            }

            DispatchQueue.main.asyncAfter(
                deadline: .now() + MiniLocationMapPreviewTiming.snapshotTimeoutSeconds,
                execute: timeout.workItem
            )

            snapshotter.start(with: .main) { snapshot, _ in
                timeout.cancel()
                guard let snapshot else {
                    box.resume(returning: nil)
                    return
                }
                box.resume(returning: annotatedImageData(from: snapshot))
            }
        }
    }

    private static func annotatedImageData(from snapshot: MKMapSnapshotter.Snapshot) -> Data? {
        let image = NSImage(size: snapshot.image.size)
        image.lockFocus()
        defer { image.unlockFocus() }

        snapshot.image.draw(
            in: NSRect(origin: .zero, size: snapshot.image.size),
            from: NSRect(origin: .zero, size: snapshot.image.size),
            operation: .copy,
            fraction: 1
        )

        let markerDiameter: CGFloat = 12
        let markerRect = NSRect(
            x: (snapshot.image.size.width - markerDiameter) / 2,
            y: (snapshot.image.size.height - markerDiameter) / 2,
            width: markerDiameter,
            height: markerDiameter
        )
        let marker = NSBezierPath(ovalIn: markerRect)
        NSColor.systemRed.setFill()
        marker.fill()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        marker.lineWidth = 2
        marker.stroke()

        return image.tiffRepresentation
    }
}

private final class MapSnapshotTimeoutWorkItem: @unchecked Sendable {
    let workItem: DispatchWorkItem

    init(_ handler: @escaping () -> Void) {
        workItem = DispatchWorkItem(block: handler)
    }

    func cancel() {
        workItem.cancel()
    }
}

private final class MapSnapshotContinuationBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(returning value: sending Value) {
        let continuationToResume: CheckedContinuation<Value, Never>?
        lock.lock()
        continuationToResume = continuation
        continuation = nil
        lock.unlock()
        continuationToResume?.resume(returning: value)
    }
}
