import Foundation
import CryptoKit
import Security

enum SecureDataCipherError: Error {
    case invalidCiphertext
    case keyCreationFailed
}

final class SecureDataCipher {
    static let shared = SecureDataCipher()

    private static let service = "it.chirone.gestionale"
    private static let account = "patient-data-symmetric-key"
    private let keyLock = NSLock()
    private var cachedKey: SymmetricKey?
    private let loadKeyData: @MainActor () throws -> Data?
    private let saveKeyData: @MainActor (Data) throws -> Bool

    private convenience init() {
        #if DEBUG
        // Unit tests encrypt only synthetic records and must never read the user's Keychain key.
        if NSClassFromString("XCTestCase") != nil {
            let data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            self.init(readKeyData: { data }, storeKeyData: { _ in false })
            return
        }
        #endif
        self.init(readKeyData: { try Self.readKeyData() }, storeKeyData: { try Self.storeKeyData($0) })
    }

    // Injectable storage keeps failure-path tests independent from the user's Keychain.
    init(readKeyData: @escaping @MainActor () throws -> Data?, storeKeyData: @escaping @MainActor (Data) throws -> Bool) {
        loadKeyData = readKeyData
        saveKeyData = storeKeyData
    }

    // Warms the in-memory key cache immediately after biometric unlock,
    // so the first clinical field access doesn't pay the Keychain round-trip.
    func prewarmKey() {
        _ = try? symmetricKey(createIfMissing: false)
    }

    // Clears the cached key on app lock. The next operation will re-read
    // from the Keychain, which is unavailable while the device is locked.
    func invalidateSessionCache() {
        keyLock.lock()
        defer { keyLock.unlock() }
        cachedKey = nil
    }

    func encrypt(_ plaintext: String) -> String? {
        guard !plaintext.isEmpty else { return nil }

        do {
            let key = try symmetricKey()
            let data = Data(plaintext.utf8)
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else {
                throw SecureDataCipherError.invalidCiphertext
            }
            return combined.base64EncodedString()
        } catch {
            return nil
        }
    }

    func decrypt(_ ciphertextBase64: String?) -> String? {
        guard let ciphertextBase64, !ciphertextBase64.isEmpty else { return nil }

        do {
            guard let combined = Data(base64Encoded: ciphertextBase64) else {
                throw SecureDataCipherError.invalidCiphertext
            }

            // Reading encrypted data must never create a replacement for a missing key.
            let key = try symmetricKey(createIfMissing: false)
            let sealed = try AES.GCM.SealedBox(combined: combined)
            let decryptedData = try AES.GCM.open(sealed, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func symmetricKey(createIfMissing: Bool = true) throws -> SymmetricKey {
        keyLock.lock()
        defer { keyLock.unlock() }

        if let key = cachedKey { return key }

        let key: SymmetricKey
        if let existing = try loadKeyData() {
            guard existing.count == 32 else { throw SecureDataCipherError.keyCreationFailed }
            key = SymmetricKey(data: existing)
        } else {
            guard createIfMissing else { throw SecureDataCipherError.keyCreationFailed }
            let newKey = SymmetricKey(size: .bits256)
            let raw = newKey.withUnsafeBytes { Data($0) }
            if try saveKeyData(raw) {
                key = newKey
            } else if let existing = try loadKeyData() {
                // Another process may have created the shared Keychain item first.
                guard existing.count == 32 else { throw SecureDataCipherError.keyCreationFailed }
                key = SymmetricKey(data: existing)
            } else {
                throw SecureDataCipherError.keyCreationFailed
            }
        }
        cachedKey = key
        return key
    }

    private static func readKeyData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == 32 else {
                throw SecureDataCipherError.keyCreationFailed
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw SecureDataCipherError.keyCreationFailed
        }
    }

    private static func storeKeyData(_ data: Data) throws -> Bool {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem { return false }
        guard status == errSecSuccess else {
            throw SecureDataCipherError.keyCreationFailed
        }
        return true
    }
}
