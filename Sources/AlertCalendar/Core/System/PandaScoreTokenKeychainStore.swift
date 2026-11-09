import Foundation
import Security

protocol EsportsTokenStoring: Sendable {
    func loadToken() throws -> String?
    func saveToken(_ token: String) throws
    func removeToken() throws
}

enum PandaScoreTokenStoreError: Error, Equatable {
    case invalidToken
    case keychain(OSStatus)
}

/// Construction performs no Keychain access. Tokens stay local to this Mac.
struct PandaScoreTokenKeychainStore: EsportsTokenStoring {
    let service: String
    let account: String

    init(service: String = "com.zworehl.alertcalendar.pandascore", account: String = "personal") {
        self.service = service
        self.account = account
    }

    func loadToken() throws -> String? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw PandaScoreTokenStoreError.keychain(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8), Self.isValid(token) else {
            throw PandaScoreTokenStoreError.invalidToken
        }
        return token
    }

    func saveToken(_ token: String) throws {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValid(value) else { throw PandaScoreTokenStoreError.invalidToken }
        let data = Data(value.utf8)
        let status = SecItemUpdate(itemQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw PandaScoreTokenStoreError.keychain(status) }
        var query = itemQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw PandaScoreTokenStoreError.keychain(addStatus) }
    }

    func removeToken() throws {
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PandaScoreTokenStoreError.keychain(status) }
    }

    static func isValid(_ token: String) -> Bool {
        !token.isEmpty && token.utf8.count <= 4_096 && token.unicodeScalars.allSatisfy {
            $0.value >= 33 && $0.value <= 126
        }
    }

    private var itemQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }
}
