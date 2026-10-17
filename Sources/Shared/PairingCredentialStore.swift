import Foundation
import Security

enum PairingCredentialStore {
    private static let service = "com.indigital.samsungtvremote"

    static func token(for host: String) throws -> String? {
        try read(account: "token:\(host)")
    }

    static func certificatePin(for host: String) throws -> String? {
        try read(account: "certificate:\(host)")
    }

    static func save(token: String, certificatePin: String, for host: String) throws {
        try write(certificatePin, account: "certificate:\(host)")
        try write(token, account: "token:\(host)")
    }

    static func removeCredentials(for host: String) throws {
        try remove(account: "certificate:\(host)")
        try remove(account: "token:\(host)")
    }

    private static func read(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.keychain(status)
        }
        return value
    }

    private static func write(_ value: String, account: String) throws {
        let query = baseQuery(account: account)
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            #if os(iOS)
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            #endif
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw CredentialStoreError.keychain(insertStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw CredentialStoreError.keychain(updateStatus)
        }
    }

    private static func remove(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}

enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(errSecMissingEntitlement):
            "This build is missing Keychain access. Select your signing Team in Xcode and rebuild the app."
        case let .keychain(status):
            "Could not access the saved TV pairing. Keychain error \(status)."
        }
    }
}
