import AppKit
import XCTest
@testable import AlertCalendar

@MainActor
final class MenuBarStatusItemLabelRendererTests: XCTestCase {
    func testNativeLabelTracksPublishedStateAndFullAccessibleTitle() {
        let model = MenuBarPresentationModel()
        model.setInitialLoading(false)
        var images: [NSImage] = []
        var titles: [String] = []
        let renderer = MenuBarStatusItemLabelRenderer(presentation: model) { image, title in
            images.append(image)
            titles.append(title)
        }
        defer { renderer.stop() }

        var state = MenuBarPresentationState.empty(text: "Meeting")
        state.fullTitleText = "Meeting with the product team"
        model.apply(state)

        XCTAssertEqual(titles.last, state.fullTitleText)
        XCTAssertGreaterThan(images.last?.size.width ?? 0, 0)
        XCTAssertFalse(images.last?.isTemplate ?? true)
        let count = images.count
        model.apply(state)
        XCTAssertEqual(images.count, count, "An unchanged model must not repaint the status item")
        model.apply(.empty(text: "Available"))
        XCTAssertEqual(titles.last, "Available")
    }

    func testDefaultsNotificationUpdatesFontAndRetainsCachedArtworkForUnrelatedSettings() async throws {
        let suite = "MenuBarStatusItemLabelRendererTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        let model = MenuBarPresentationModel()
        model.apply(.empty(text: "A long meeting title"))
        model.setInitialLoading(false)
        var renderedSizes: [CGFloat] = []
        var images: [NSImage] = []
        let renderer = MenuBarStatusItemLabelRenderer(
            presentation: model, defaults: defaults, notificationCenter: center,
            renderImage: { state, fontSize, revision in
                renderedSizes.append(fontSize)
                return MenuBarStatusLabel.makeImage(for: state, fontSize: fontSize, footballLogoRevision: revision)
            }
        ) { image, _ in images.append(image) }
        defer { renderer.stop() }
        XCTAssertEqual(renderedSizes, [13])
        let originalWidth = try XCTUnwrap(images.last).size.width

        defaults.set(18.0, forKey: DefaultsKeys.menuBarFontSize)
        center.post(name: UserDefaults.didChangeNotification, object: defaults)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(renderedSizes, [13, 18])
        XCTAssertGreaterThan(try XCTUnwrap(images.last).size.width, originalWidth)

        let publicationCount = images.count
        defaults.set(true, forKey: "unrelatedSetting")
        center.post(name: UserDefaults.didChangeNotification, object: defaults)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(renderedSizes, [13, 18])
        XCTAssertEqual(images.count, publicationCount, "Unrelated settings must not reassign identical status artwork")
    }

    func testLoadingAnimatesOnlyDuringInitialLoadAndStopCancelsObservers() async throws {
        let model = MenuBarPresentationModel()
        let center = NotificationCenter()
        var images: [NSImage] = []
        var titles: [String] = []
        let renderer = MenuBarStatusItemLabelRenderer(
            presentation: model, notificationCenter: center, loadingIntervalNanoseconds: 1_000_000
        ) { image, title in
            images.append(image)
            titles.append(title)
        }
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertGreaterThan(images.count, 1)
        XCTAssertTrue(images.first === MenuBarLoadingIndicator.frames[0])
        XCTAssertTrue(images.dropFirst().contains { $0 !== images.first })
        XCTAssertEqual(titles.last, L10n.text("Alert Calendar is loading"))

        model.apply(.empty(text: "Ready"))
        model.setInitialLoading(false)
        XCTAssertEqual(titles.last, "Ready", "Use the emitted @Published value before its storage is updated")
        let afterInitialLoad = images.count
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertEqual(images.count, afterInitialLoad)

        renderer.stop()
        model.setInitialLoading(true)
        model.apply(.empty(text: "Changed after stop"))
        center.post(name: .alertCalendarLanguageDidChange, object: nil)
        try await Task.sleep(nanoseconds: 15_000_000)
        XCTAssertEqual(images.count, afterInitialLoad)
    }

    func testLanguageNotificationRefreshesLoadingMetadata() async throws {
        let model = MenuBarPresentationModel()
        let center = NotificationCenter()
        var titles: [String] = []
        let renderer = MenuBarStatusItemLabelRenderer(
            presentation: model, notificationCenter: center, loadingIntervalNanoseconds: 10_000_000_000
        ) { _, title in titles.append(title) }
        defer { renderer.stop() }
        let previousLanguage = AlertCalendarLanguage.current
        defer { AlertCalendarLanguage.current = previousLanguage }
        AlertCalendarLanguage.current = previousLanguage == .english ? .spanishLatinAmerica : .english
        let previousCount = titles.count
        center.post(name: .alertCalendarLanguageDidChange, object: nil)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(titles.count, previousCount + 1)
        XCTAssertEqual(titles.last, L10n.text("Alert Calendar is loading"))
    }

    func testTooltipOnlyChangesKeepArtworkWhileAlertAndGoalBlinkFramesStillPublish() {
        let model = MenuBarPresentationModel()
        model.setInitialLoading(false)
        var rendered = 0
        var images: [NSImage] = []
        var titles: [String] = []
        let renderer = MenuBarStatusItemLabelRenderer(
            presentation: model,
            renderImage: { _, _, _ in rendered += 1; return NSImage(size: .init(width: 40, height: 22)) },
            loadLogo: { _ in nil }
        ) { image, title in images.append(image); titles.append(title) }
        defer { renderer.stop() }
        var state = MenuBarPresentationState.empty(text: "Meeting")
        state.fullTitleText = "Meeting with the team"
        model.apply(state)
        let originalImage = images.last
        let renderCount = rendered

        state.fullTitleText = "Meeting with the updated team"
        model.apply(state)
        XCTAssertEqual(rendered, renderCount)
        XCTAssertTrue(images.last === originalImage)
        XCTAssertEqual(titles.last, state.fullTitleText)

        state.alertedSegmentIndex = 0
        state.alertTextOpacity = 1
        model.apply(state)
        let beforeAlert = images.count
        model.setAlertTextOpacity(0.25)
        XCTAssertEqual(images.count, beforeAlert + 1, "An intentional urgent blink is a real artwork update")

        state.alertTextOpacity = 0.25
        state.footballDisplay = footballDisplay(home: "/not-loaded-home.png", away: "/not-loaded-away.png")
        state.footballGoalHighlightSide = .home
        state.footballGoalHighlightTextOpacity = 1
        model.apply(state)
        let beforeGoal = images.count
        state.footballGoalHighlightTextOpacity = 0.25
        model.apply(state)
        XCTAssertEqual(images.count, beforeGoal + 1, "Goal highlight frames must remain visible")
    }

    func testLogoLoadingRefreshesArtworkAndIncludesPinnedScoresWithoutDuplicatePaths() async throws {
        let model = MenuBarPresentationModel()
        var state = MenuBarPresentationState.empty(text: "Football")
        let home = "/temporary-\(UUID().uuidString)-home.png"
        let away = "/temporary-\(UUID().uuidString)-away.png"
        let pinned = "/temporary-\(UUID().uuidString)-pinned.png"
        state.footballDisplay = footballDisplay(home: home, away: away)
        state.pinnedFootballScores = [
            PinnedFootballMenuBarScore(
                id: "pinned", calendarColor: .systemBlue, backgroundProgress: 1,
                display: footballDisplay(home: home, away: pinned),
                statusText: "Live", highlightSide: nil, highlightOpacity: 0
            )
        ]
        model.apply(state)
        model.setInitialLoading(false)
        var loadedPaths: [String] = []
        var revisions: [Int] = []
        let renderer = MenuBarStatusItemLabelRenderer(
            presentation: model,
            renderImage: { _, _, revision in
                revisions.append(revision)
                return NSImage(size: NSSize(width: 40, height: 22))
            },
            loadLogo: { path in
                loadedPaths.append(path)
                return NSImage(size: NSSize(width: 8, height: 8))
            }
        ) { _, _ in }
        defer { renderer.stop() }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(loadedPaths, [home, away, pinned])
        XCTAssertEqual(revisions, [0, 1])
    }

    func testRendererDeallocatesWhileLoadingAnimationIsRunning() async throws {
        let model = MenuBarPresentationModel()
        var renderer: MenuBarStatusItemLabelRenderer? = MenuBarStatusItemLabelRenderer(
            presentation: model, loadingIntervalNanoseconds: 1_000_000
        ) { _, _ in }
        weak var releasedRenderer = renderer
        try await Task.sleep(nanoseconds: 5_000_000)
        renderer = nil
        XCTAssertNil(releasedRenderer)
    }

    private func footballDisplay(home: String, away: String) -> FootballMenuBarDisplay {
        FootballMenuBarDisplay(
            accessibilityText: "HOME 1 - 0 AWAY", competitionName: "League", competitionStage: nil,
            homeAbbreviation: "HOME", awayAbbreviation: "AWAY", showsScore: true,
            homeScore: "1", awayScore: "0", competitionLocalLogoPath: nil,
            homeLocalLogoPath: home, awayLocalLogoPath: away,
            homeLogoUsesCircularOutline: true, awayLogoUsesCircularOutline: true
        )
    }
}
