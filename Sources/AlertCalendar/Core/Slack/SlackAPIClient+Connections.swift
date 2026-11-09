import Foundation

extension SlackAPIClient {
    func connectUserToken(_ rawToken: String) async throws -> SlackConnection {
        let token = try normalizedUserToken(rawToken)
        return try await connection(
            for: .legacyUserToken(token),
            connectedAt: Date()
        )
    }

    func validateConnection(_ connection: SlackConnection) async throws -> SlackConnection {
        let token = try await authorizedToken(for: connection)
        let authResponse = try await authTest(token: token)
        let profileResponse = try await profileGet(token: token)
        let teamInfoResponse = try await bestEffortTeamInfo(token: token)
        let now = Date()

        let validatedConnection = try buildConnection(
            authResponse: authResponse,
            profileResponse: profileResponse,
            teamInfoResponse: teamInfoResponse,
            connectedAt: connection.connectedAt,
            lastValidatedAt: now,
            existingConnection: connection
        )
        authorizedTokensByConnectionID[validatedConnection.id] = token
        if validatedConnection.id != connection.id {
            authorizedTokensByConnectionID[connection.id] = nil
        }
        return validatedConnection
    }

    func currentProfileStatus(for connection: SlackConnection) async throws -> SlackProfileStatusSnapshot {
        let token = try await authorizedToken(for: connection)
        let response = try await profileGet(token: token)
        guard let profile = response.profile else {
            throw SlackAPIError.invalidResponse
        }
        return profileSnapshot(from: profile)
    }

    func setStatus(_ snapshot: SlackProfileStatusSnapshot, for connection: SlackConnection) async throws -> SlackProfileStatusSnapshot {
        let token = try await authorizedToken(for: connection)
        return try await profileSet(snapshot: snapshot, token: token)
    }

    func removeStoredToken(for connectionID: String) throws {
        authorizedTokensByConnectionID[connectionID] = nil
        try tokenStore.removeToken(for: connectionID)
    }

    func connection(
        for credential: SlackCredential,
        connectedAt: Date
    ) async throws -> SlackConnection {
        let token = try normalizedUserToken(credential.accessToken)
        let authResponse = try await authTest(token: token)
        let profileResponse = try await profileGet(token: token)
        let teamInfoResponse = try await bestEffortTeamInfo(token: token)

        let now = Date()
        let connection = try buildConnection(
            authResponse: authResponse,
            profileResponse: profileResponse,
            teamInfoResponse: teamInfoResponse,
            connectedAt: connectedAt,
            lastValidatedAt: now
        )
        try tokenStore.saveCredential(credential, for: connection.id)
        authorizedTokensByConnectionID[connection.id] = token
        return connection
    }

    func buildConnection(
        authResponse: SlackAuthTestResponse,
        profileResponse: SlackProfileEnvelope,
        teamInfoResponse: SlackTeamInfoResponse?,
        connectedAt: Date,
        lastValidatedAt: Date,
        existingConnection: SlackConnection? = nil
    ) throws -> SlackConnection {
        guard let profile = profileResponse.profile else {
            throw SlackAPIError.invalidResponse
        }

        return SlackConnection(
            id: SlackConnection.makeID(teamID: authResponse.teamID, userID: authResponse.userID),
            teamID: authResponse.teamID,
            teamName: authResponse.teamName,
            workspaceURLString: authResponse.workspaceURLString,
            workspaceImageURLString: teamIconURLString(from: teamInfoResponse)
                ?? existingConnection?.workspaceImageURLString,
            userID: authResponse.userID,
            userName: authResponse.userName,
            userDisplayName: SlackConnection.normalizedValue(profile.displayName)
                ?? SlackConnection.normalizedValue(profile.realName)
                ?? existingConnection?.userDisplayName,
            emailAddress: SlackConnection.normalizedValue(profile.email)
                ?? existingConnection?.emailAddress,
            profileImageURLString: profileImageURLString(from: profile)
                ?? existingConnection?.profileImageURLString,
            connectedAt: connectedAt,
            lastValidatedAt: lastValidatedAt
        )
    }

    func authorizedToken(for connection: SlackConnection) async throws -> String {
        if let cachedToken = authorizedTokensByConnectionID[connection.id] {
            return cachedToken
        }

        guard let storedCredential = try tokenStore.storedCredential(for: connection.id) else {
            throw SlackAPIError.missingStoredToken
        }

        let token: String
        switch storedCredential {
        case let .legacyToken(storedToken):
            token = try normalizedUserToken(storedToken)
        case let .credential(credential):
            token = try normalizedUserToken(credential.accessToken)
        }
        authorizedTokensByConnectionID[connection.id] = token
        return token
    }
}
