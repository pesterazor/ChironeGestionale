//
//  TherapyMedication.swift
//  ChironeGestionale
//
//  Created by Codex on 21/04/2026.
//

import Foundation
import SwiftData

@Model
final class TherapyMedication {
    var id: UUID
    var medicationName: String
    var dosage: String
    var posology: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    var patient: Patient?

    init(
        id: UUID = UUID(),
        medicationName: String = "",
        dosage: String = "",
        posology: String = "",
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        patient: Patient? = nil
    ) {
        self.id = id
        self.medicationName = medicationName
        self.dosage = dosage
        self.posology = posology
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.patient = patient
    }
}
