import ApplicationServices
import XCTest
@testable import AlertCalendar

@MainActor
final class AppleMailAutomationPermissionTests: XCTestCase {
    func testCachedAccessorDoesNotWaitAndCoalescesConcurrentRefreshes() async {
        let probe = PermissionProbe(results: [.authorized])
        let service = AppleMailAutomationPermissionService(refreshInterval: 30) { asks in
            await probe.perform(asks)
        }
        let start = Date()
        for _ in 0 ..< 100 { XCTAssertEqual(service.currentStatus(), .notDetermined) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.1)
        async let first = service.refresh(forceRefresh: true)
        async let second = service.refresh(forceRefresh: true)
        let results = await [first, second]
        XCTAssertEqual(results, [.authorized, .authorized])
        XCTAssertEqual(service.currentStatus(), .authorized)
        let calls = await probe.calls
        XCTAssertEqual(calls, [false])
    }

    func testFailureDoesNotPoisonFutureChecks() async {
        let probe = PermissionProbe(results: [nil, .authorized])
        let service = AppleMailAutomationPermissionService(refreshInterval: 30) { asks in
            try await probe.performThrowing(asks)
        }
        let failed = await service.refresh()
        let recovered = await service.refresh(forceRefresh: true)
        XCTAssertEqual(failed, .mailUnavailable)
        XCTAssertEqual(recovered, .authorized)
    }

    func testExplicitRequestWaitsForProbeThenCoalescesPermissionPrompt() async {
        let probe = PermissionProbe(results: [.notDetermined, .authorized])
        let service = AppleMailAutomationPermissionService(refreshInterval: 30) { asks in
            await probe.perform(asks)
        }
        _ = service.currentStatus()
        async let first = service.requestAccess()
        async let second = service.requestAccess()
        let results = await [first, second]
        XCTAssertEqual(results, [.authorized, .authorized])
        let calls = await probe.calls
        XCTAssertEqual(calls, [false, true])
    }

    func testForcedRefreshDetectsRevokedPermission() async {
        let probe = PermissionProbe(results: [.authorized, .denied])
        let service = AppleMailAutomationPermissionService(refreshInterval: 30) { asks in
            await probe.perform(asks)
        }
        _ = await service.refresh()
        let revoked = await service.refresh(forceRefresh: true)
        XCTAssertEqual(revoked, .denied)
        XCTAssertEqual(service.currentStatus(), .denied)
    }

    func testMapsConsentAndUnavailableStatusesWithoutAssumingAuthorization() {
        XCTAssertEqual(AppleMailAutomationPermission.authorizationStatus(for: noErr), .authorized)
        XCTAssertEqual(AppleMailAutomationPermission.authorizationStatus(for: OSStatus(errAEEventWouldRequireUserConsent)), .notDetermined)
        XCTAssertEqual(AppleMailAutomationPermission.authorizationStatus(for: OSStatus(errAEEventNotPermitted)), .denied)
        XCTAssertEqual(AppleMailAutomationPermission.authorizationStatus(for: nil), .mailUnavailable)
        XCTAssertEqual(AppleMailAutomationPermission.authorizationStatus(for: -600), .mailUnavailable)
    }
}

private actor PermissionProbe {
    var calls: [Bool] = []
    private var results: [AppleMailAutomationAuthorizationStatus?]
    init(results: [AppleMailAutomationAuthorizationStatus?]) { self.results = results }

    func performThrowing(_ asks: Bool) async throws -> AppleMailAutomationAuthorizationStatus {
        calls.append(asks)
        let result = results.isEmpty ? .denied : results.removeFirst()
        try await Task.sleep(for: .milliseconds(40))
        guard let result else { throw AlertCalendarProcessError.timedOut }
        return result
    }

    func perform(_ asks: Bool) async -> AppleMailAutomationAuthorizationStatus {
        (try? await performThrowing(asks)) ?? .mailUnavailable
    }
}
