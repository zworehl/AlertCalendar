import Combine
import Foundation
import Sparkle

@MainActor
final class SoftwareUpdateController: ObservableObject {
    static let shared = SoftwareUpdateController()

    @Published private(set) var revision = 0
    @Published private(set) var configurationError: String?

    private let standardUpdaterController: SPUStandardUpdaterController
    private var didStart = false
    private var refreshTask: Task<Void, Never>?

    private init() {
        standardUpdaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    deinit {
        refreshTask?.cancel()
    }

    var automaticallyChecksForUpdates: Bool {
        standardUpdaterController.updater.automaticallyChecksForUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        standardUpdaterController.updater.automaticallyDownloadsUpdates
    }

    var allowsAutomaticUpdates: Bool {
        standardUpdaterController.updater.allowsAutomaticUpdates
    }

    var canCheckForUpdates: Bool {
        didStart && standardUpdaterController.updater.canCheckForUpdates
    }

    var lastUpdateCheckDate: Date? {
        standardUpdaterController.updater.lastUpdateCheckDate
    }

    var displayVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    func start() {
        guard !didStart else { return }
        guard Self.hasValidConfiguration(in: .main) else {
            configurationError = "Automatic updates are unavailable in this development build."
            revision += 1
            return
        }

        standardUpdaterController.startUpdater()
        didStart = true
        configurationError = nil
        revision += 1
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        standardUpdaterController.updater.automaticallyChecksForUpdates = isEnabled
        if !isEnabled {
            standardUpdaterController.updater.automaticallyDownloadsUpdates = false
        }
        revision += 1
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        guard standardUpdaterController.updater.allowsAutomaticUpdates else { return }
        standardUpdaterController.updater.automaticallyDownloadsUpdates = isEnabled
        revision += 1
    }

    @objc
    func checkForUpdates(_ sender: Any? = nil) {
        guard canCheckForUpdates else { return }
        standardUpdaterController.checkForUpdates(sender)
        monitorActiveUpdateSession()
    }

    nonisolated static func hasValidConfiguration(in bundle: Bundle) -> Bool {
        guard let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        return URL(string: feedURL)?.scheme == "https" && !publicKey.isEmpty
    }

    private func monitorActiveUpdateSession() {
        refreshTask?.cancel()
        revision += 1
        refreshTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                revision += 1
            } while standardUpdaterController.updater.sessionInProgress
        }
    }
}
