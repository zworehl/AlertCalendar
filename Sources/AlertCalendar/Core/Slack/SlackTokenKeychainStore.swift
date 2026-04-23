import Foundation
import Security

struct SlackTokenKeychainStore {
    let service: String

    init(service: String = "com.zworehl.alertcalendar.slack") {
        self.service = service
    }

    func saveToken(_ token: String, for connectionID: String) throws {
        try saveCredential(.legacyUserToken(token), for: connectionID)
    }

    func saveCredential(_ credential: SlackCredential, for connectionID: String) throws {
        let tokenData = try JSONEncoder().encode(credential)
        let baseQuery = itemQuery(for: connectionID)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: tokenData] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = tokenData
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SlackAPIError.keychainFailure(status: addStatus)
            }
            return
        }

        throw SlackAPIError.keychainFailure(status: updateStatus)
    }

    func storedCredential(for connectionID: String) throws -> SlackStoredKeychainCredential? {
        var query = itemQuery(for: connectionID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SlackAPIError.keychainFailure(status: status)
        }
        guard let data = result as? Data else {
            throw SlackAPIError.invalidTokenFormat
        }

        if let credential = try? JSONDecoder().decode(SlackCredential.self, from: data) {
            return .credential(credential)
        }

        guard let token = String(data: data, encoding: .utf8) else {
            throw SlackAPIError.invalidTokenFormat
        }
        return .legacyToken(token)
    }

    func removeToken(for connectionID: String) throws {
        let status = SecItemDelete(itemQuery(for: connectionID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SlackAPIError.keychainFailure(status: status)
        }
    }

    private func itemQuery(for connectionID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectionID,
        ]
    }
}
