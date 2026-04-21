//
//  ClinicalNote.swift
//  ChironeGestionale
//
//  Created by Codex on 21/04/2026.
//

import Foundation
import SwiftData

@Model
final class ClinicalNote {
    var id: UUID
    var content: String
    var wellbeingScore: Int
    var createdAt: Date
    var updatedAt: Date

    var patient: Patient?

    init(
        id: UUID = UUID(),
        content: String = "",
        wellbeingScore: Int = 5,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        patient: Patient? = nil
    ) {
        self.id = id
        self.content = content
        self.wellbeingScore = min(max(wellbeingScore, 0), 10)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.patient = patient
    }
}
