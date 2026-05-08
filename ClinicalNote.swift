//
//  ClinicalNote.swift
//  ChironeGestionale
//
//  Created by Peste on 21/04/2026.
//

import Foundation
import SwiftData

@Model
final class ClinicalNote {
    var id: UUID
    var content: String
    var encryptedContent: String?
    var wellbeingScore: Int
    var createdAt: Date
    var updatedAt: Date

    var patient: Patient?

    init(
        id: UUID = UUID(),
        content: String = "",
        encryptedContent: String? = nil,
        wellbeingScore: Int = 5,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        patient: Patient? = nil
    ) {
        self.id = id
        self.content = content
        self.encryptedContent = encryptedContent
        self.wellbeingScore = min(max(wellbeingScore, 0), 10)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.patient = patient
    }
}

extension ClinicalNote {
    static func timelineSorted(_ notes: [ClinicalNote]) -> [ClinicalNote] {
        notes.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    var readableContent: String {
        if let decrypted = SecureDataCipher.shared.decrypt(encryptedContent) {
            return decrypted
        }
        return content
    }

    func protectContent(_ plaintext: String) {
        let trimmed = plaintext.trimmingCharacters(in: .whitespacesAndNewlines)
        if let encrypted = SecureDataCipher.shared.encrypt(trimmed) {
            encryptedContent = encrypted
            content = ""
        } else {
            encryptedContent = nil
            content = trimmed
        }
    }
}
