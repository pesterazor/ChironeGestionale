import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import ChironeGestionale

@MainActor
final class PsychometricTrendTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func trend(_ scores: [Int?], maximum: Int = 27) -> PsychometricTrendData {
        let records = scores.enumerated().map { index, score in
            PsychometricTrendRecord(date: date.addingTimeInterval(Double(index) * 86400), score: score)
        }
        return PsychometricTrendData(newestFirst: records.reversed(), maximum: maximum)
    }

    func testEmptySingleConstantAndSignedChanges() {
        XCTAssertTrue(trend([]).points.isEmpty)
        XCTAssertNil(trend([]).previousDelta)
        XCTAssertFalse(trend([]).latestIsInvalid)
        XCTAssertNil(trend([4]).baselineDelta)
        XCTAssertEqual(trend([4, 4, 4]).previousDelta, 0)
        XCTAssertEqual(trend([4, 4, 4]).baselineDelta, 0)
        XCTAssertEqual(trend([2, 9, 5]).previousDelta, -4)
        XCTAssertEqual(trend([2, 9, 5]).baselineDelta, 3)
        XCTAssertEqual(trend([2, 9]).previousDelta, 7)
        XCTAssertEqual(PsychometricTrendConfiguration.phq9.deltaText(-4), "−4 punti")
        XCTAssertEqual(PsychometricTrendConfiguration.phq9.deltaText(1), "+1 punto")
        XCTAssertEqual(PsychometricTrendConfiguration.phq9.deltaText(0), "0 punti")
        XCTAssertEqual(PsychometricTrendConfiguration.mdq.deltaText(-1), "−1 sintomo")
        XCTAssertEqual(PsychometricTrendConfiguration.mdq.deltaText(2), "+2 sintomi")
    }

    func testLastTwelveValidPointsRetainFullHistoryBaseline() {
        let data = trend([0, nil] + Array(1...15).map(Optional.some))
        XCTAssertEqual(data.points.count, 16)
        XCTAssertEqual(data.recentPoints.map(\.value), Array(4...15))
        XCTAssertEqual(data.baselineDelta, 15)
        XCTAssertEqual(data.previousDelta, 1)
        XCTAssertEqual(data.excludedCount, 1)
    }

    func testInvalidDataBreaksLineAndInvalidLatestSuppressesComparisons() {
        let data = trend([2, nil, 9, 28, 5, -1, 4])
        XCTAssertEqual(data.points.map(\.segment), [0, 1, 2, 3])
        XCTAssertEqual(data.excludedCount, 3)
        XCTAssertEqual(data.previousDelta, -1)
        XCTAssertTrue(data.previousWasInvalid)
        let invalidLast = trend([3, 5, nil])
        XCTAssertTrue(invalidLast.latestIsInvalid)
        XCTAssertNil(invalidLast.previousDelta)
        XCTAssertNil(invalidLast.baselineDelta)
        XCTAssertEqual(invalidLast.recentPoints.count, 2)
        XCTAssertTrue(trend([nil, nil]).points.isEmpty)
    }

    func testCoincidentDatesPreserveRecordsOrderingAndSelection() {
        let a = PHQ9Assessment(date: date, scores: Array(repeating: 1, count: 9))
        let b = PHQ9Assessment(date: date, scores: Array(repeating: 2, count: 9))
        let c = PHQ9Assessment(date: date, scores: Array(repeating: 2, count: 9))
        a.createdAt = date; b.createdAt = date; c.createdAt = date.addingTimeInterval(1)
        a.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        b.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let records = AssessmentDateEditing.sorted([c, a, b]).map { PsychometricTrendRecord($0) }
        let data = PsychometricTrendData(newestFirst: records, maximum: 27)
        XCTAssertEqual(data.points.map(\.id), [a.id, b.id, c.id])
        XCTAssertEqual(data.points.map(\.date), [date, date, date])
        XCTAssertEqual(PsychometricTrendData.selection(at: date, in: data.points).count, 3)
        XCTAssertEqual(data.previousDelta, 0)
        XCTAssertEqual(data.baselineDelta, 9)
        let domain = PsychometricTrendData.domain(for: data.points)
        XCTAssertLessThan(domain.lowerBound, date)
        XCTAssertGreaterThan(domain.upperBound, date)
    }

    func testAllAdaptersRejectIncompleteAndOutOfRangeResponses() {
        XCTAssertNil(PsychometricTrendRecord(PHQ9Assessment(scores: [])).score)
        XCTAssertNil(PsychometricTrendRecord(PHQ9Assessment(scores: [4] + Array(repeating: 0, count: 8))).score)
        XCTAssertNil(PsychometricTrendRecord(GAD7Assessment(scores: Array(repeating: -1, count: 7))).score)
        XCTAssertNil(PsychometricTrendRecord(MDQAssessment(part1Answers: [])).score)
        XCTAssertNil(PsychometricTrendRecord(MDQAssessment(part3RawValue: 4)).score)
        XCTAssertNil(PsychometricTrendRecord(MDQAssessment(part1Answers: [2] + Array(repeating: 0, count: 12))).score)
        XCTAssertNil(PsychometricTrendRecord(BeckAssessment(scale: .bai, answerIndices: [])).score)
        XCTAssertNil(PsychometricTrendRecord(BeckAssessment(scale: .bdiII, answerIndices: Array(repeating: 9, count: 21))).score)
        XCTAssertNil(PsychometricTrendRecord(MADRSAssessment(scores: Array(repeating: 7, count: 10))).score)
        XCTAssertEqual(PsychometricTrendRecord(PHQ9Assessment()).score, 0)
        XCTAssertEqual(PsychometricTrendRecord(GAD7Assessment()).score, 0)
        XCTAssertEqual(PsychometricTrendRecord(MDQAssessment()).score, 0)
        let invalidDate = PsychometricTrendRecord(date: Date(timeIntervalSince1970: .nan), score: 1)
        XCTAssertTrue(PsychometricTrendData(newestFirst: [invalidDate], maximum: 27).latestIsInvalid)
    }

    func testBeckScalesStaySeparateAndUseTheirOwnThresholds() {
        let records = [BeckAssessment(scale: .bai, answerIndices: Array(repeating: 1, count: 21)),
                       BeckAssessment(scale: .bdiII, answerIndices: Array(repeating: 2, count: 21))]
        let bai = PsychometricTrendData(newestFirst: BeckAssessment.sorted(records, for: .bai).map { PsychometricTrendRecord($0) }, maximum: 63)
        let bdi = PsychometricTrendData(newestFirst: BeckAssessment.sorted(records, for: .bdiII).map { PsychometricTrendRecord($0) }, maximum: 63)
        XCTAssertEqual(bai.points.map(\.value), [21])
        // Gli indici 2 degli item sonno e appetito corrispondono a 1 punto.
        XCTAssertEqual(bdi.points.map(\.value), [40])
        XCTAssertEqual(PsychometricTrendConfiguration.beck(.bai).thresholds, [8, 16, 26])
        XCTAssertEqual(PsychometricTrendConfiguration.beck(.bdiII).thresholds, [14, 20, 29])
        XCTAssertEqual([PsychometricTrendConfiguration.phq9, .gad7, .beck(.bai), .beck(.bdiII), .madrs, .mdq].map(\.maximum), [27, 21, 63, 63, 60, 13])
    }

    func testDateEditAdditionAndDeletionRefreshBaselineAndComparisons() throws {
        let schema = Schema([Patient.self, ClinicalNote.self, TherapyMedication.self, PHQ9Assessment.self, GAD7Assessment.self, MDQAssessment.self, BeckAssessment.self, MADRSAssessment.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let patient = Patient(firstName: "Test", lastName: "Sintetico")
        context.insert(patient)
        let a = PHQ9Assessment(date: date, scores: Array(repeating: 1, count: 9), patient: patient)
        let b = PHQ9Assessment(date: date.addingTimeInterval(86400), scores: Array(repeating: 2, count: 9), patient: patient)
        patient.phq9Assessments = [a, b]
        try context.save()
        func current() -> PsychometricTrendData {
            PsychometricTrendData(newestFirst: AssessmentDateEditing.sorted(patient.phq9Assessments).map { PsychometricTrendRecord($0) }, maximum: 27)
        }
        XCTAssertEqual(current().previousDelta, 9)
        try AssessmentDateEditing.update(a, to: date.addingTimeInterval(86400 * 2)) { try context.save() }
        XCTAssertEqual(current().previousDelta, -9)
        XCTAssertEqual(current().points.first?.id, b.id)
        let c = PHQ9Assessment(date: date.addingTimeInterval(86400 * 3), scores: Array(repeating: 0, count: 9), patient: patient)
        context.insert(c)
        patient.phq9Assessments.append(c)
        try context.save()
        XCTAssertEqual(current().baselineDelta, -18)
        try AssessmentDeletion.delete(b, in: context)
        XCTAssertEqual(current().baselineDelta, -9)
        try AssessmentDeletion.delete(c, in: context)
        XCTAssertNil(current().previousDelta)
        XCTAssertEqual(current().points.count, 1)
    }

    func testSixScalesRenderAtRequestedWidthsAndAppearances() throws {
        let patient = Patient(firstName: "Paziente", lastName: "Sintetico")
        for index in 0..<14 {
            let day = date.addingTimeInterval(Double(index * index) * 86400)
            patient.phq9Assessments.append(PHQ9Assessment(date: day, scores: Array(repeating: index % 4, count: 9)))
            patient.gad7Assessments.append(GAD7Assessment(date: day, scores: Array(repeating: index % 4, count: 7)))
            patient.mdqAssessments.append(MDQAssessment(date: day, part1Answers: Array(repeating: 1, count: index % 14) + Array(repeating: 0, count: 13 - index % 14), part2Answer: true, part3RawValue: 2))
            for scale in BeckScale.allCases {
                patient.beckAssessments.append(BeckAssessment(scale: scale, date: day, answerIndices: Array(repeating: index % 4, count: 21)))
            }
            patient.madrsAssessments.append(MADRSAssessment(date: day, scores: Array(repeating: index % 7, count: 10), raterName: "Dottoressa Alessandra Maria Rossi · Servizio di psichiatria e psicologia clinica"))
        }
        let views: [(String, AnyView)] = [
            ("PHQ9", AnyView(PHQ9ScaleContent(patient: patient))),
            ("GAD7", AnyView(GAD7ScaleContent(patient: patient))),
            ("BAI", AnyView(BeckScaleContent(patient: patient, scale: .bai))),
            ("BDI-II", AnyView(BeckScaleContent(patient: patient, scale: .bdiII))),
            ("MADRS", AnyView(MADRSScaleContent(patient: patient))),
            ("MDQ", AnyView(MDQScaleContent(patient: patient)))
        ]
        for width in [820.0, 980.0] {
            for dark in [false, true] {
                for (name, view) in views {
                    try render(ScrollView { view.padding(24) }, name: "Trend-\(name)-\(Int(width))-\(dark ? "dark" : "light")", width: width, dark: dark)
                }
            }
        }
        let cases: [(String, [Int?])] = [("single", [5]), ("constant", [6, 6, 6]), ("invalid-last", [4, nil, 7, nil]), ("all-invalid", [nil, nil])]
        for (name, values) in cases {
            let data = trend(values)
            try render(PsychometricTrendView(data: data, configuration: .phq9) {
                Text("Valutazione di prova con descrizione lunga per verificare la disposizione verticale").fixedSize(horizontal: false, vertical: true)
            }.padding(24), name: "Trend-\(name)-narrow", width: 420, dark: false)
        }
        try render(PsychometricTrendChart(points: trend([2, 8, nil, 19, 12]).points, configuration: .phq9, expanded: true).padding(24), name: "Trend-expanded-gap", width: 820, dark: false)
    }

    func testKeyboardAndAccessibilityNavigationVisitsDatesAndClampsAtBounds() {
        let data = trend([4, 8, 2])
        let first = data.points[0].date
        let middle = data.points[1].date
        let last = data.points[2].date
        func next(_ current: Date?, _ step: Int) -> Date? {
            PsychometricTrendData.nextSelection(after: current, step: step, in: data.points)
        }
        XCTAssertEqual(next(nil, 1), first)
        XCTAssertEqual(next(nil, -1), last)
        XCTAssertEqual(next(first, 1), middle)
        XCTAssertEqual(next(middle, -1), first)
        XCTAssertEqual(next(first, -1), first)
        XCTAssertEqual(next(last, 1), last)
        XCTAssertNil(PsychometricTrendData.nextSelection(after: nil, step: 1, in: []))
        let duplicates = PsychometricTrendData(newestFirst: [
            PsychometricTrendRecord(date: last, score: 2),
            PsychometricTrendRecord(date: first, score: 8),
            PsychometricTrendRecord(date: first, score: 4)
        ], maximum: 27)
        XCTAssertEqual(PsychometricTrendData.nextSelection(after: first, step: 1, in: duplicates.points), last)
        XCTAssertEqual(PsychometricTrendData.selection(at: first.addingTimeInterval(1), in: duplicates.points).map(\.value), [4, 8])
    }

    private func render<V: View>(_ view: V, name: String, width: CGFloat, dark: Bool) throws {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light).background(dark ? Color.black : Color.white))
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 760)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        window.contentView = nil
    }
}
