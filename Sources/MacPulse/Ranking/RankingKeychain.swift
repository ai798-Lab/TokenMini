import Foundation
import Security

/// 排行榜会话只保存在本机钥匙串，不写 UserDefaults、文件或日志。
enum RankingKeychain {
    enum Token: String {
        case access = "access-token"
        case refresh = "refresh-token"
    }

    private static let service = "com.liangheping.macpulse.ranking"

    static func load(_ token: Token) -> String? {
        var query = baseQuery(token)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func store(_ value: String, as token: Token) throws {
        guard let data = value.data(using: .utf8) else { throw Error.encoding }
        let query = baseQuery(token)
        let updates: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw Error.status(updated) }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw Error.status(added) }
    }

    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
    }

    private static func baseQuery(_ token: Token) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: token.rawValue,
            kSecAttrSynchronizable as String: false,
        ]
    }

    enum Error: Swift.Error {
        case encoding
        case status(OSStatus)
    }
}
