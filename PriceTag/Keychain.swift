//
//  Keychain.swift
//  PriceTag
//
//  Keeps the sign-in token somewhere safer than the app's files.
//

import Foundation
import Security

enum Keychain {
    private static let service = "com.atiqueaqtab.pricetag2026.session"

    private static func base(_ key: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    static func read(_ key: String) -> String? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ key: String, _ value: String) {
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(base(key) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = base(key)
            add[kSecValueData as String] = data
            // Readable after the first unlock so a background refresh still works.
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func remove(_ key: String) {
        SecItemDelete(base(key) as CFDictionary)
    }
}
