import Foundation
import CryptoKit
import Security

enum SecureDataCipherError: Error {
    case invalidCiphertext
    case keyCreationFailed
}

final class SecureDataCipher {
    static let shared = SecureDataCipher()

    private let service = "it.chirone.gestionale"
    private let account = "patient-data-symmetric-key"

    private init() {}

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

            let key = try symmetricKey()
            let sealed = try AES.GCM.SealedBox(combined: combined)
            let decryptedData = try AES.GCM.open(sealed, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func symmetricKey() throws -> SymmetricKey {
        if let existing = try readKeyData() {
            return SymmetricKey(data: existing)
        }

        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        try storeKeyData(raw)
        return key
    }

    private func readKeyData() throws -> Data? {
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
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw SecureDataCipherError.keyCreationFailed
        }
    }

    private func storeKeyData(_ data: Data) throws {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureDataCipherError.keyCreationFailed
        }
    }
}
