import Foundation

extension SlackAPIClient {
    func authTest(token: String) async throws -> SlackAuthTestResponse {
        var request = URLRequest(url: URL(string: "https://slack.com/api/auth.test")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: SlackAuthTestEnvelope = try await send(request)
        guard response.ok else {
            throw slackAPIError(
                message: response.error,
                needed: response.needed,
                provided: response.provided
            )
        }

        guard
            let teamID = SlackConnection.normalizedValue(response.teamId),
            let teamName = SlackConnection.normalizedValue(response.team),
            let userID = SlackConnection.normalizedValue(response.userId),
            let userName = SlackConnection.normalizedValue(response.user)
        else {
            throw SlackAPIError.invalidResponse
        }

        return SlackAuthTestResponse(
            workspaceURLString: SlackConnection.normalizedValue(response.url),
            teamID: teamID,
            teamName: teamName,
            userID: userID,
            userName: userName
        )
    }

    func profileGet(token: String) async throws -> SlackProfileEnvelope {
        var request = URLRequest(url: URL(string: "https://slack.com/api/users.profile.get")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: SlackProfileEnvelope = try await send(request)
        guard response.ok, response.profile != nil else {
            throw slackAPIError(
                message: response.error,
                needed: response.needed,
                provided: response.provided
            )
        }
        return response
    }

    func profileSet(snapshot: SlackProfileStatusSnapshot, token: String) async throws -> SlackProfileStatusSnapshot {
        var request = URLRequest(url: URL(string: "https://slack.com/api/users.profile.set")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            SlackProfileSetRequest(profile: SlackProfileRequestProfile(snapshot: snapshot))
        )

        let response: SlackProfileEnvelope = try await send(request)
        guard response.ok else {
            throw slackAPIError(
                message: response.error,
                needed: response.needed,
                provided: response.provided
            )
        }

        guard let profile = response.profile else {
            throw SlackAPIError.invalidResponse
        }

        return profileSnapshot(from: profile)
    }

    func bestEffortTeamInfo(token: String) async throws -> SlackTeamInfoResponse? {
        do {
            return try await teamInfo(token: token)
        } catch let error as SlackAPIError {
            switch error {
            case let .missingScope(needed, _):
                if needed == "team:read" {
                    return nil
                }
            case let .api(message):
                if message == "missing_scope" || message == "not_allowed_token_type" {
                    return nil
                }
            default:
                break
            }
            throw error
        }
    }

    func teamInfo(token: String) async throws -> SlackTeamInfoResponse? {
        var request = URLRequest(url: URL(string: "https://slack.com/api/team.info")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: SlackTeamInfoEnvelope = try await send(request)
        guard response.ok else {
            throw slackAPIError(
                message: response.error,
                needed: response.needed,
                provided: response.provided
            )
        }
        return response.team
    }

    func profileImageURLString(from profile: SlackProfileResponse) -> String? {
        SlackConnection.normalizedValue(profile.image192)
            ?? SlackConnection.normalizedValue(profile.image72)
            ?? SlackConnection.normalizedValue(profile.imageOriginal)
    }

    func teamIconURLString(from team: SlackTeamInfoResponse?) -> String? {
        guard let icon = team?.icon else { return nil }
        return SlackConnection.normalizedValue(icon.image88)
            ?? SlackConnection.normalizedValue(icon.image68)
            ?? SlackConnection.normalizedValue(icon.image44)
            ?? SlackConnection.normalizedValue(icon.image34)
    }

    func profileSnapshot(from profile: SlackProfileResponse) -> SlackProfileStatusSnapshot {
        SlackProfileStatusSnapshot(
            statusText: profile.statusText ?? "",
            statusEmoji: profile.statusEmoji ?? "",
            statusExpiration: profile.statusExpiration ?? 0
        )
    }

    func formRequest(url: URL, parameters: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = parameters
            .sorted(by: { $0.key < $1.key })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return request
    }

    func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SlackAPIError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw SlackAPIError.transport(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data)
    }

    func slackAPIError(
        message: String?,
        needed: String?,
        provided: String?
    ) -> SlackAPIError {
        let resolvedMessage = message ?? "unknown_error"
        if resolvedMessage == "missing_scope",
           let neededScope = SlackConnection.normalizedValue(needed) {
            return .missingScope(
                needed: neededScope,
                provided: SlackConnection.normalizedValue(provided)
            )
        }
        return .api(message: resolvedMessage)
    }
}

struct SlackAuthTestEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let needed: String?
    let provided: String?
    let url: String?
    let team: String?
    let teamId: String?
    let user: String?
    let userId: String?
}

struct SlackAuthTestResponse {
    let workspaceURLString: String?
    let teamID: String
    let teamName: String
    let userID: String
    let userName: String
}

struct SlackProfileEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let needed: String?
    let provided: String?
    let profile: SlackProfileResponse?
}

struct SlackTeamInfoEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let needed: String?
    let provided: String?
    let team: SlackTeamInfoResponse?
}

struct SlackTeamInfoResponse: Decodable {
    let id: String?
    let name: String?
    let icon: SlackTeamIconResponse?
}

struct SlackTeamIconResponse: Decodable {
    let image34: String?
    let image44: String?
    let image68: String?
    let image88: String?
    let image102: String?
    let image132: String?
    let image230: String?
    let imageDefault: Bool?
}

struct SlackProfileResponse: Codable {
    let displayName: String?
    let realName: String?
    let email: String?
    let image72: String?
    let image192: String?
    let imageOriginal: String?
    let statusText: String?
    let statusEmoji: String?
    let statusExpiration: Int?
}

struct SlackProfileSetRequest: Encodable {
    let profile: SlackProfileRequestProfile
}

struct SlackProfileRequestProfile: Encodable {
    enum CodingKeys: String, CodingKey {
        case statusText = "status_text"
        case statusEmoji = "status_emoji"
        case statusExpiration = "status_expiration"
    }

    let statusText: String
    let statusEmoji: String
    let statusExpiration: Int

    init(snapshot: SlackProfileStatusSnapshot) {
        statusText = snapshot.statusText
        statusEmoji = snapshot.statusEmoji
        statusExpiration = snapshot.statusExpiration
    }
}
