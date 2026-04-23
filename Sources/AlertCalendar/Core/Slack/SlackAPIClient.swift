import Foundation
import Security

enum SlackAPIError: LocalizedError, Equatable {
    case invalidTokenFormat
    case missingStoredToken
    case invalidResponse
    case transport(statusCode: Int)
    case api(message: String)
    case missingScope(needed: String, provided: String?)
    case keychainFailure(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidTokenFormat:
            return "Provide a valid Slack user token."
        case .missingStoredToken:
            return "The saved Slack credential could not be found in Keychain."
        case .invalidResponse:
            return "Slack returned an unexpected response."
        case let .transport(statusCode):
            return "Slack returned HTTP \(statusCode)."
        case let .missingScope(needed, provided):
            let providedScopes = SlackConnection.normalizedValue(provided) ?? "none"
            if needed.hasPrefix("users.profile:") {
                return "The Slack token is valid, but it is missing \(needed). Current scopes: \(providedScopes). AlertCalendar needs users.profile:read and users.profile:write."
            }
            return "The Slack token is missing \(needed). Current scopes: \(providedScopes)."
        case let .api(message):
            switch message {
            case "invalid_auth", "token_revoked":
                return "Slack rejected the saved credential. Connect the account again."
            case "missing_scope":
                return "The Slack app must grant users.profile:read and users.profile:write."
            case "account_inactive":
                return "The Slack user behind this credential is inactive."
            default:
                return "Slack error: \(message)."
            }
        case let .keychainFailure(status):
            let fallback = "Keychain returned status \(status)."
            let message = SecCopyErrorMessageString(status, nil) as String?
            return message ?? fallback
        }
    }
}

actor SlackAPIClient {
    let session: URLSession
    let tokenStore: SlackTokenKeychainStore

    init(
        session: URLSession? = nil,
        tokenStore: SlackTokenKeychainStore = SlackTokenKeychainStore()
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 20
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
        self.tokenStore = tokenStore
    }

    func normalizedUserToken(_ rawToken: String) throws -> String {
        let trimmed = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("xoxp-") || trimmed.hasPrefix("xoxe.xoxp-") else {
            throw SlackAPIError.invalidTokenFormat
        }
        return trimmed
    }
}
