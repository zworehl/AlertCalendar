import Foundation

enum AlertCalendarHTTPClient {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await shared.data(for: request)
    }
}
