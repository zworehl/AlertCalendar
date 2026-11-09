import AppKit
import Foundation
import XCTest
@testable import AlertCalendar

final class FootballEnrichmentBudgetTests: FootballDataAPIClientTestCase {
    func testConcurrentTeamRequestsShareOneFetchAndMissingTeamsRetryAfterTheirCacheExpires() async throws {
        let counter = EnrichmentRequestCounter()
        let session = makeMockSession { request in
            counter.increment()
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { session.invalidateAndCancel() }
        let client = FootballDataAPIClient(session: session)
        let now = Date()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { _ = await client.teamDetails(teamID: "missing", now: now) }
            }
            await group.waitForAll()
        }
        _ = await client.teamDetails(teamID: "missing", now: now.addingTimeInterval(30))
        XCTAssertEqual(counter.value, 1)
        _ = await client.teamDetails(teamID: "missing", now: now.addingTimeInterval(16 * 60))
        XCTAssertEqual(counter.value, 2)
    }

    func testConcurrentImagesShareOneDownloadAndInvalidImagesAreNotCachedAsFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try pngData(width: 20, height: 10)
        let counter = EnrichmentRequestCounter()
        let session = makeMockSession { request in
            counter.increment()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    request.url?.lastPathComponent == "valid.png" ? data : Data("<html>unavailable</html>".utf8))
        }
        defer { session.invalidateAndCancel() }
        let store = FootballImageStore(session: session, baseDirectoryURL: directory)
        let url = URL(string: "https://images.example/valid.png")!
        let urls = await withTaskGroup(of: URL?.self) { group in
            for _ in 0..<8 { group.addTask { await store.localFileURL(for: url) } }
            var values: [URL] = []
            for await value in group { if let value { values.append(value) } }
            return values
        }
        XCTAssertEqual(urls.count, 8)
        XCTAssertEqual(Set(urls).count, 1)
        XCTAssertEqual(counter.value, 1)
        let invalid = URL(string: "https://images.example/invalid.png")!
        let result = await store.localFileURL(for: invalid)
        XCTAssertNil(result)
        _ = await store.localFileURL(for: invalid)
        XCTAssertEqual(counter.value, 2)
    }

    @MainActor
    func testDecodedLogosHaveBoundedPixelMemoryAndPreserveAspectRatio() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try pngData(width: 1_200, height: 600).write(to: url)
        let image = await FootballLocalImageCache.decodedCGImage(for: url.path)
        let decoded = try XCTUnwrap(image)
        XCTAssertLessThanOrEqual(max(decoded.width, decoded.height), 192)
        XCTAssertEqual(Double(decoded.width) / Double(decoded.height), 2, accuracy: 0.03)
    }

    @MainActor
    func testRemoteLogoCannotOverwriteANewerLocalFlag() async throws {
        let started = expectation(description: "Remote image started")
        let stalePublication = expectation(description: "Stale image publication")
        stalePublication.isInverted = true
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try pngData(width: 20, height: 10)
        let session = makeMockSession { request in
            started.fulfill()
            Thread.sleep(forTimeInterval: 0.08)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        defer { session.invalidateAndCancel() }
        let coordinator = FootballLogoLoadingCoordinator(imageStore: FootballImageStore(session: session, baseDirectoryURL: directory)) { _, _ in
            stalePublication.fulfill()
        }
        defer { coordinator.cancel() }
        let key = FootballLogoLoadingCoordinator.Key(kind: .team, id: "national")
        coordinator.enqueue([.init(key: key, remoteURL: URL(string: "https://images.example/remote.png")!)])
        await fulfillment(of: [started], timeout: 2)
        coordinator.resolveLocally(key)
        await fulfillment(of: [stalePublication], timeout: 0.2)
    }

    @MainActor
    func testReturningToAnAlreadyLoadedLogoInvalidatesANewerPendingURL() async throws {
        let first = expectation(description: "First logo loaded")
        let secondStarted = expectation(description: "Replacement started")
        let stalePublication = expectation(description: "Obsolete replacement published")
        stalePublication.isInverted = true
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try pngData(width: 20, height: 10)
        let session = makeMockSession { request in
            if request.url?.lastPathComponent == "b.png" {
                secondStarted.fulfill()
                Thread.sleep(forTimeInterval: 0.08)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        defer { session.invalidateAndCancel() }
        var published = 0
        let coordinator = FootballLogoLoadingCoordinator(imageStore: FootballImageStore(session: session, baseDirectoryURL: directory)) { _, _ in
            published += 1
            if published == 1 { first.fulfill() } else { stalePublication.fulfill() }
        }
        defer { coordinator.cancel() }
        let key = FootballLogoLoadingCoordinator.Key(kind: .team, id: "team")
        let a = URL(string: "https://images.example/a.png")!
        coordinator.enqueue([.init(key: key, remoteURL: a)])
        await fulfillment(of: [first], timeout: 2)
        coordinator.enqueue([.init(key: key, remoteURL: URL(string: "https://images.example/b.png")!)])
        await fulfillment(of: [secondStarted], timeout: 2)
        coordinator.enqueue([.init(key: key, remoteURL: a)])
        await fulfillment(of: [stalePublication], timeout: 0.2)
        XCTAssertEqual(published, 1)
    }

    @MainActor
    func testExpiredCompletedLogoIsRevalidatedAfterItsFileDisappears() async throws {
        let first = expectation(description: "Initial logo")
        let refreshed = expectation(description: "Missing cached logo restored")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try pngData(width: 20, height: 10)
        let counter = EnrichmentRequestCounter()
        let session = makeMockSession { request in
            counter.increment()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        defer { session.invalidateAndCancel() }
        var now = Date()
        var paths: [String] = []
        let coordinator = FootballLogoLoadingCoordinator(imageStore: FootballImageStore(session: session, baseDirectoryURL: directory), now: { now }) { _, path in
            paths.append(path)
            if paths.count == 1 { first.fulfill() } else { refreshed.fulfill() }
        }
        defer { coordinator.cancel() }
        let request = FootballLogoLoadingCoordinator.Request(key: .init(kind: .team, id: "team"), remoteURL: URL(string: "https://images.example/expiring.png")!)
        coordinator.enqueue([request])
        await fulfillment(of: [first], timeout: 2)
        try FileManager.default.removeItem(atPath: XCTUnwrap(paths.first))
        now = now.addingTimeInterval(16 * 60)
        coordinator.enqueue([request])
        await fulfillment(of: [refreshed], timeout: 2)
        XCTAssertEqual(counter.value, 2)
    }

    private func pngData(width: Int, height: Int) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}

private final class EnrichmentRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
