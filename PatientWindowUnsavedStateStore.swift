import Foundation

final class PatientWindowUnsavedStateStore {
    static let shared = PatientWindowUnsavedStateStore()

    private var states: [UUID: Bool] = [:]

    private init() {}

    func set(_ hasUnsavedChanges: Bool, for patientID: UUID) {
        states[patientID] = hasUnsavedChanges
    }

    func hasUnsavedChanges(for patientID: UUID) -> Bool {
        states[patientID] ?? false
    }

    func clear(for patientID: UUID) {
        states.removeValue(forKey: patientID)
    }
}
