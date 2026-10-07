import CryptoKit
import Foundation
import XCTest
@testable import ChironeGestionale

@MainActor
final class SecureDataIntegrityTests: XCTestCase {
    private final class KeyAvailability {
        var isAvailable = true
    }

    func testPrewarmAndDecryptNeverCreateMissingKey() throws {
        var writes = 0
        let cipher = SecureDataCipher(readKeyData: { nil }, storeKeyData: { _ in
            writes += 1
            return true
        })
        let ciphertext = try seal("Dato sintetico", with: Data(repeating: 7, count: 32))
        cipher.prewarmKey()
        XCTAssertNil(cipher.decrypt(ciphertext))
        XCTAssertEqual(writes, 0)
    }

    func testFirstEncryptionPersistsKeyBeforeReturningCiphertext() throws {
        var keyData: Data?
        var writes = 0
        let cipher = SecureDataCipher(readKeyData: { keyData }, storeKeyData: { data in
            keyData = data
            writes += 1
            return true
        })
        let ciphertext = try XCTUnwrap(cipher.encrypt("Dato sintetico"))
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(keyData?.count, 32)
        cipher.invalidateSessionCache()
        XCTAssertEqual(cipher.decrypt(ciphertext), "Dato sintetico")
    }

    func testUnavailableOrInvalidStoredKeyIsNotReplaced() {
        enum Failure: Error { case unavailable }
        let readers: [@MainActor () throws -> Data?] = [
            { throw Failure.unavailable },
            { Data(repeating: 1, count: 16) }
        ]
        for reader in readers {
            var writes = 0
            let cipher = SecureDataCipher(readKeyData: reader, storeKeyData: { _ in
                writes += 1
                return true
            })
            cipher.prewarmKey()
            XCTAssertNil(cipher.encrypt("Dato sintetico"))
            XCTAssertEqual(writes, 0)
        }
    }

    func testFailedKeyStorageDoesNotCacheEphemeralKey() {
        var writes = 0
        let cipher = SecureDataCipher(readKeyData: { nil }, storeKeyData: { _ in
            writes += 1
            return false
        })
        XCTAssertNil(cipher.encrypt("Prima prova"))
        XCTAssertNil(cipher.encrypt("Seconda prova"))
        XCTAssertEqual(writes, 2)
    }

    func testCompetingKeyCreationUsesPersistedWinningKey() throws {
        let winningKey = Data(repeating: 9, count: 32)
        var stored: Data?
        let cipher = SecureDataCipher(readKeyData: { stored }, storeKeyData: { _ in
            stored = winningKey
            return false
        })
        let ciphertext = try XCTUnwrap(cipher.encrypt("Dato sintetico"))
        let independentReader = SecureDataCipher(readKeyData: { winningKey }, storeKeyData: { _ in
            XCTFail("Reading must not store a key")
            return false
        })
        XCTAssertEqual(independentReader.decrypt(ciphertext), "Dato sintetico")
    }

    func testInvalidatingSessionRequiresKeyToBeAvailableAgain() throws {
        enum Failure: Error { case unavailable }
        let availability = KeyAvailability()
        let key = Data(repeating: 8, count: 32)
        let cipher = SecureDataCipher(readKeyData: {
            guard availability.isAvailable else { throw Failure.unavailable }
            return key
        }, storeKeyData: { _ in false })
        let ciphertext = try XCTUnwrap(cipher.encrypt("Dato sintetico"))
        availability.isAvailable = false
        XCTAssertEqual(cipher.decrypt(ciphertext), "Dato sintetico")
        cipher.invalidateSessionCache()
        XCTAssertNil(cipher.decrypt(ciphertext))
        XCTAssertNil(cipher.encrypt("Nuovo dato"))
    }

    func testUnreadablePatientCiphertextCannotBeReplacedOrCleared() {
        let patient = Patient(primaryDiagnosis: "Legacy", secondaryDiagnosis: "Legacy",
            medicalComorbidities: "Legacy", remotePsychiatricHistory: "Legacy", allergies: "Legacy")
        let invalid = "unreadable-ciphertext"
        patient.encryptedPrimaryDiagnosis = invalid
        patient.encryptedSecondaryDiagnosis = invalid
        patient.encryptedMedicalComorbidities = invalid
        patient.encryptedRemotePsychiatricHistory = invalid
        patient.encryptedAllergies = invalid
        for replacement in ["Nuovo dato", "", "   "] {
            XCTAssertFalse(patient.protectPrimaryDiagnosis(replacement))
            XCTAssertFalse(patient.protectSecondaryDiagnosis(replacement))
            XCTAssertFalse(patient.protectMedicalComorbidities(replacement))
            XCTAssertFalse(patient.protectRemotePsychiatricHistory(replacement))
            XCTAssertFalse(patient.protectAllergies(replacement))
        }
        XCTAssertEqual(patient.encryptedPrimaryDiagnosis, invalid)
        XCTAssertEqual(patient.encryptedSecondaryDiagnosis, invalid)
        XCTAssertEqual(patient.encryptedMedicalComorbidities, invalid)
        XCTAssertEqual(patient.encryptedRemotePsychiatricHistory, invalid)
        XCTAssertEqual(patient.encryptedAllergies, invalid)
        XCTAssertEqual(patient.primaryDiagnosis, "Legacy")
        XCTAssertEqual(patient.secondaryDiagnosis, "Legacy")
        XCTAssertEqual(patient.medicalComorbidities, "Legacy")
        XCTAssertEqual(patient.remotePsychiatricHistory, "Legacy")
        XCTAssertEqual(patient.allergies, "Legacy")
    }

    func testUnreadableNoteCannotBeReplacedClearedOrPersistedAsEmpty() {
        let note = ClinicalNote(content: "Legacy", encryptedContent: "unreadable-ciphertext")
        for replacement in ["Nuova nota", "", "   "] {
            XCTAssertFalse(note.protectContent(replacement))
        }
        var persistCalls = 0
        XCTAssertThrowsError(try ClinicalNoteEditing.save(note, content: "Nuova nota", wellbeing: 2, date: nil) {
            persistCalls += 1
        })
        XCTAssertEqual(persistCalls, 0)
        XCTAssertEqual(note.content, "Legacy")
        XCTAssertEqual(note.encryptedContent, "unreadable-ciphertext")
        XCTAssertEqual(note.wellbeingScore, 5)
    }

    func testReadableProtectedValuesCanStillBeEditedAndCleared() {
        let patient = Patient()
        let note = ClinicalNote()
        XCTAssertTrue(patient.protectPrimaryDiagnosis("Diagnosi sintetica"))
        XCTAssertTrue(patient.protectPrimaryDiagnosis("Diagnosi aggiornata"))
        XCTAssertEqual(patient.readablePrimaryDiagnosis, "Diagnosi aggiornata")
        XCTAssertTrue(patient.protectPrimaryDiagnosis(""))
        XCTAssertNil(patient.encryptedPrimaryDiagnosis)
        XCTAssertTrue(note.protectContent("Nota sintetica"))
        XCTAssertTrue(note.protectContent("Nota aggiornata"))
        XCTAssertEqual(note.readableContent, "Nota aggiornata")
        XCTAssertTrue(note.protectContent(""))
        XCTAssertNil(note.encryptedContent)
    }

    private func seal(_ plaintext: String, with key: Data) throws -> String {
        let box = try AES.GCM.seal(Data(plaintext.utf8), using: SymmetricKey(data: key))
        return try XCTUnwrap(box.combined).base64EncodedString()
    }
}
