import Foundation

enum PsychometricResponseValidation {
    nonisolated static func isComplete(_ scores: [Int], itemCount: Int, range: ClosedRange<Int>) -> Bool {
        scores.count == itemCount && scores.allSatisfy(range.contains)
    }

    nonisolated static func isCompleteMDQ(part1: [Int], part2: Int, part3: Int) -> Bool {
        isComplete(part1, itemCount: 13, range: 0...1) && (0...1).contains(part2) && (0...3).contains(part3)
    }
}
