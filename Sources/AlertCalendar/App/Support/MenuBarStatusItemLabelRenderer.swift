import AppKit
import Combine

/// Publishes the existing badge artwork through the native status button.
/// Presentation has its own owner; changing the label never activates a window.
@MainActor
final class MenuBarStatusItemLabelRenderer {
    typealias RenderImage = @MainActor (MenuBarPresentationState, CGFloat, Int) -> NSImage
    typealias LoadLogo = @MainActor (String) async -> NSImage?
    typealias LabelSink = @MainActor (NSImage, String) -> Void

    private struct ImageKey: Equatable {
        let state: MenuBarPresentationState
        let fontSize: CGFloat
        let logoRevision: Int
    }

    private let defaults: UserDefaults
    private let renderImage: RenderImage
    private let loadLogo: LoadLogo
    private let sink: LabelSink
    private let loadingIntervalNanoseconds: UInt64
    private var subscriptions = Set<AnyCancellable>()
    private var loadingTask: Task<Void, Never>?
    private var logoTask: Task<Void, Never>?
    private var state = MenuBarPresentationState.loading
    private var isLoading = true
    private var isStopped = false
    private var loadingFrame = 0
    private var logoPaths: [String] = []
    private var logoRevision = 0
    private var imageKey: ImageKey?
    private var image: NSImage?
    private var lastPublishedImage: NSImage?
    private var lastPublishedTitle: String?

    convenience init(
        presentation: MenuBarPresentationModel,
        button: NSStatusBarButton,
        defaults: UserDefaults = .standard
    ) {
        var accessibleTitle: String?
        self.init(
            presentation: presentation, defaults: defaults
        ) { [weak button] image, title in
            guard let button else { return }
            if !button.title.isEmpty { button.title = "" }
            if button.image !== image { button.image = image }
            if button.imagePosition != .imageOnly { button.imagePosition = .imageOnly }
            if button.toolTip != title { button.toolTip = title }
            if accessibleTitle != title {
                button.setAccessibilityLabel(title)
                accessibleTitle = title
            }
        }
    }

    init(
        presentation: MenuBarPresentationModel,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        loadingIntervalNanoseconds: UInt64 = MenuBarLoadingIndicator.frameIntervalNanoseconds,
        renderImage: @escaping RenderImage = MenuBarStatusLabel.makeImage,
        loadLogo: @escaping LoadLogo = FootballLocalImageCache.loadImage,
        sink: @escaping LabelSink
    ) {
        self.defaults = defaults
        self.loadingIntervalNanoseconds = loadingIntervalNanoseconds
        self.renderImage = renderImage
        self.loadLogo = loadLogo
        self.sink = sink

        presentation.$state.combineLatest(presentation.$isInitialLoading)
            .sink { [weak self] state, isLoading in
                self?.apply(state: state, isLoading: isLoading)
            }
            .store(in: &subscriptions)
        for name in [UserDefaults.didChangeNotification, .alertCalendarLanguageDidChange] {
            notificationCenter.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.publishLabel()
                }
                .store(in: &subscriptions)
        }
    }

    deinit {
        loadingTask?.cancel()
        logoTask?.cancel()
    }

    func stop() {
        isStopped = true
        subscriptions.removeAll()
        loadingTask?.cancel()
        loadingTask = nil
        logoTask?.cancel()
        logoTask = nil
    }

    private func apply(state: MenuBarPresentationState, isLoading: Bool) {
        guard !isStopped else { return }
        self.state = state
        self.isLoading = isLoading
        updateLogoLoading()
        if isLoading {
            startLoadingAnimationIfNeeded()
        } else {
            loadingTask?.cancel()
            loadingTask = nil
            loadingFrame = 0
        }
        publishLabel()
    }

    private func publishLabel() {
        guard !isStopped else { return }
        if isLoading {
            publishIfChanged(MenuBarLoadingIndicator.frames[loadingFrame], title: L10n.text("Alert Calendar is loading"))
            return
        }
        let storedFontSize = (defaults.object(forKey: DefaultsKeys.menuBarFontSize) as? NSNumber)?.doubleValue ?? 13
        let fontSize = storedFontSize.isFinite ? min(max(CGFloat(storedFontSize), 10), 18) : 13
        var artworkState = state
        artworkState.fullTitleText = nil
        let key = ImageKey(state: artworkState, fontSize: fontSize, logoRevision: logoRevision)
        if imageKey != key {
            image = renderImage(state, fontSize, logoRevision)
            imageKey = key
        }
        if let image { publishIfChanged(image, title: state.fullTitleText ?? state.label) }
    }

    private func publishIfChanged(_ image: NSImage, title: String) {
        guard image !== lastPublishedImage || title != lastPublishedTitle else { return }
        lastPublishedImage = image
        lastPublishedTitle = title
        sink(image, title)
    }

    private func startLoadingAnimationIfNeeded() {
        guard loadingTask == nil else { return }
        let interval = loadingIntervalNanoseconds
        loadingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: interval) }
                catch { return }
                guard let self, !self.isStopped, self.isLoading, !Task.isCancelled else { return }
                self.loadingFrame = (self.loadingFrame + 1) % MenuBarLoadingIndicator.frameCount
                self.publishLabel()
            }
        }
    }

    private func updateLogoLoading() {
        let paths = Self.footballLogoPaths(for: state)
        guard paths != logoPaths else { return }
        logoPaths = paths
        logoTask?.cancel()
        logoTask = nil
        let pendingPaths = paths.filter { FootballLocalImageCache.cachedImage(for: $0) == nil }
        guard !pendingPaths.isEmpty else { return }
        let loadLogo = self.loadLogo
        logoTask = Task { [weak self] in
            var didLoad = false
            for path in pendingPaths {
                guard !Task.isCancelled else { return }
                if await loadLogo(path) != nil { didLoad = true }
            }
            guard let self, !self.isStopped, !Task.isCancelled, self.logoPaths == paths else { return }
            self.logoTask = nil
            if didLoad {
                self.logoRevision += 1
                self.publishLabel()
            }
        }
    }

    static func footballLogoPaths(for state: MenuBarPresentationState) -> [String] {
        var seen = Set<String>()
        return ([state.footballDisplay] + state.pinnedFootballScores.map { Optional($0.display) })
            .flatMap { [$0?.homeLocalLogoPath, $0?.awayLocalLogoPath] }
            .compactMap { $0 }
            .filter { seen.insert($0).inserted }
    }
}
