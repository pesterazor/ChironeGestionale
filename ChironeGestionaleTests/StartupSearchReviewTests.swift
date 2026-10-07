import Foundation
import LocalAuthentication
import SwiftData
import XCTest
@testable import ChironeGestionale

@MainActor
final class StartupSearchReviewTests: XCTestCase {
    func testStoreFailureRemainsUnavailableUntilAnExplicitSuccessfulRetry() throws {
        enum FixtureError: Error { case unavailable }
        let schema = Schema([Patient.self, ClinicalNote.self, TherapyMedication.self,
                             PHQ9Assessment.self, GAD7Assessment.self, MDQAssessment.self,
                             BeckAssessment.self, MADRSAssessment.self])
        let memoryContainer = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
        var attempts = 0
        let state = ModelStoreState {
            attempts += 1
            if attempts == 1 { throw FixtureError.unavailable }
            return memoryContainer
        }
        XCTAssertEqual(attempts, 1, "A failed persistent opening must never start a fallback store.")
        XCTAssertNil(state.container)
        XCTAssertNotNil(state.errorDescription)
        state.retry()
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(state.container === memoryContainer)
        XCTAssertNil(state.errorDescription)
    }

    func testPatientSearchIgnoresWordOrderAccentsCaseAndExtraWhitespace() {
        let first = Patient(firstName: "José Maria", lastName: "D’Ángelo", taxCode: "SYNTHETIC123", phoneNumber: "011 123 456")
        let second = Patient(firstName: "Maria", lastName: "Rossi", taxCode: "SYNTHETIC456")
        let patients = [first, second]
        for query in ["  ANGELO   jose\n", "jose 123", "synthetic123", "011 456"] {
            XCTAssertEqual(PatientSidebarQuery.results(from: patients, query: query, sortByLastVisit: false).map(\.id), [first.id], query)
        }
        XCTAssertEqual(PatientSidebarQuery.results(from: patients, query: "maria", sortByLastVisit: false).count, 2)
        XCTAssertTrue(PatientSidebarQuery.results(from: patients, query: "missing", sortByLastVisit: false).isEmpty)
        XCTAssertEqual(PatientSidebarQuery.results(from: patients, query: " \n", sortByLastVisit: false).count, 2)
    }

    func testLastVisitOrderingIsDeterministicAndUpdatesAfterANoteChanges() {
        let older = Patient(firstName: "Older", lastName: "B")
        let newer = Patient(firstName: "Newer", lastName: "A")
        let noVisit = Patient(firstName: "None", lastName: "A")
        let oldNote = ClinicalNote(createdAt: Date(timeIntervalSince1970: 10))
        older.clinicalNotes = [oldNote]
        newer.clinicalNotes = [ClinicalNote(createdAt: Date(timeIntervalSince1970: 20))]
        let patients = [noVisit, older, newer]
        XCTAssertEqual(PatientSidebarQuery.results(from: patients, query: "", sortByLastVisit: true).map(\.id), [newer.id, older.id, noVisit.id])
        oldNote.createdAt = Date(timeIntervalSince1970: 30)
        XCTAssertEqual(PatientSidebarQuery.results(from: patients, query: "", sortByLastVisit: true).map(\.id), [older.id, newer.id, noVisit.id])
        let sameName = Patient(firstName: "None", lastName: "A")
        let expected = [sameName, noVisit].sorted { $0.id.uuidString < $1.id.uuidString }.map(\.id)
        XCTAssertEqual(PatientSidebarQuery.results(from: [sameName, noVisit], query: "", sortByLastVisit: false).map(\.id), expected)
    }

    func testAutocompleteNormalizesQueriesAndHandlesNonpositiveLimits() {
        let autocomplete = ActiveIngredientAutocomplete(ingredients: ["ACIDO", "ACICLOVIR", "CAFÉINA"], forms: ["ACIDO": ["10 MG", "2,5 MG", "20 MG"]])
        XCTAssertEqual(autocomplete.suggestions(for: " acì ", limit: 1), ["ACIDO"])
        XCTAssertEqual(autocomplete.suggestions(for: "cafe"), ["CAFÉINA"])
        XCTAssertEqual(autocomplete.formulationSuggestions(for: "acido", formulationQuery: ""), ["2,5 MG", "10 MG", "20 MG"])
        for limit in [0, -1] {
            XCTAssertTrue(autocomplete.suggestions(for: "ac", limit: limit).isEmpty)
            XCTAssertTrue(autocomplete.formulationSuggestions(for: "acido", formulationQuery: "", limit: limit).isEmpty)
        }
        XCTAssertTrue(autocomplete.suggestions(for: "zz").isEmpty)
    }

    func testAutocompleteRecognizesCompoundDosageUnits() {
        let autocomplete = ActiveIngredientAutocomplete(ingredients: ["TEST"], forms: ["TEST": ["5 MG/ML A", "5 MG Z", "2 MG/ML"]])
        XCTAssertEqual(autocomplete.formulationSuggestions(for: "TEST", formulationQuery: ""), ["2 MG/ML", "5 MG Z", "5 MG/ML A"])
    }

    func testAuthenticationDeduplicatesRequestsAndRejectsStaleCallbacks() async {
        let context = StubAuthenticationContext()
        let model = AppLockViewModel(makeContext: { context })
        model.unlock()
        model.unlock()
        XCTAssertEqual(context.evaluations, 1)
        XCTAssertTrue(model.isAuthenticating)
        let staleCompletion = context.completion
        model.lock()
        XCTAssertTrue(context.invalidated)
        XCTAssertFalse(model.isAuthenticating)
        staleCompletion?(true, nil)
        await Task.yield()
        XCTAssertFalse(model.isUnlocked)
    }

    func testReauthenticationTimeoutBoundaryAndClockRollback() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(AppLockViewModel.requiresReauthentication(backgroundedAt: base, now: base.addingTimeInterval(299), timeoutMinutes: 5))
        XCTAssertTrue(AppLockViewModel.requiresReauthentication(backgroundedAt: base, now: base.addingTimeInterval(300), timeoutMinutes: 5))
        XCTAssertTrue(AppLockViewModel.requiresReauthentication(backgroundedAt: base, now: base.addingTimeInterval(-1), timeoutMinutes: 5))
        XCTAssertTrue(AppLockViewModel.requiresReauthentication(backgroundedAt: base, now: base.addingTimeInterval(60), timeoutMinutes: 0))
    }
}

private final class StubAuthenticationContext: LAContext, @unchecked Sendable {
    var evaluations = 0
    var invalidated = false
    var completion: (@Sendable (Bool, Error?) -> Void)?

    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool { true }

    override func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, Error?) -> Void) {
        evaluations += 1
        completion = reply
    }

    override func invalidate() { invalidated = true }
}
