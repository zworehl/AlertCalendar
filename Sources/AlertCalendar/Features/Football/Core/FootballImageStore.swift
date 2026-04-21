import CryptoKit
import Foundation

actor FootballImageStore {
    private let fileManager: FileManager
    private let session: URLSession
    private let baseDirectoryURL: URL
    private static let requestTimeout: TimeInterval = 6
    private static let resourceTimeout: TimeInterval = 12

    init(fileManager: FileManager = .default, session: URLSession? = nil) {
        self.fileManager = fileManager

        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = Self.requestTimeout
            configuration.timeoutIntervalForResource = Self.resourceTimeout
            configuration.waitsForConnectivity = false
            configuration.httpMaximumConnectionsPerHost = 8
            self.session = URLSession(configuration: configuration)
        }

        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.baseDirectoryURL = applicationSupportURL
            .appendingPathComponent("AlertCalendar", isDirectory: true)
            .appendingPathComponent("football-images", isDirectory: true)
    }

    func localFileURL(for remoteURL: URL?) async -> URL? {
        guard let remoteURL else { return nil }
        ensureDirectoryExists(at: baseDirectoryURL)

        let fileExtension = normalizedFileExtension(from: remoteURL)
        let fileName = "\(hashed(remoteURL.absoluteString)).\(fileExtension)"
        let destinationURL = baseDirectoryURL.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        do {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = Self.requestTimeout
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else {
                return nil
            }

            try data.write(to: destinationURL, options: [.atomic])
            return destinationURL
        } catch {
            return nil
        }
    }

    private func ensureDirectoryExists(at url: URL) {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func normalizedFileExtension(from remoteURL: URL) -> String {
        let ext = remoteURL.pathExtension.lowercased()
        return ext.isEmpty ? "png" : ext
    }

    private func hashed(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
