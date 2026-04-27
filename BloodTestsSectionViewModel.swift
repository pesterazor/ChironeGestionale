import Foundation

enum BloodTestsSectionViewModel {
    private static let writeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    private static let parseDateFormatters: [DateFormatter] = {
        let formats = [
            "dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy", "d-M-yyyy", "yyyy-MM-dd", "dd/MM/yy", "d/M/yy"
        ]

        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "it_IT")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()

    static func isDefaultRow(_ row: BloodTestRowRecord) -> Bool {
        let key = BloodTestsDefaults.normalizedName(BloodTestsDefaults.canonicalName(row.testName))
        return BloodTestsDefaults.defaultTestSet.contains(key)
    }

    static func normalizePayload(_ payload: BloodTestsTablePayload) -> BloodTestsTablePayload {
        var rowsByNormalizedName: [String: BloodTestRowRecord] = [:]

        for row in payload.rows {
            let trimmedName = row.testName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }
            let canonicalName = BloodTestsDefaults.canonicalName(trimmedName)

            let cleanedValues = row.values.reduce(into: [String: String]()) { partial, entry in
                let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    partial[entry.key] = value
                }
            }

            let normalizedName = BloodTestsDefaults.normalizedName(canonicalName)
            if rowsByNormalizedName[normalizedName] == nil {
                rowsByNormalizedName[normalizedName] = BloodTestRowRecord(
                    id: row.id,
                    testName: canonicalName,
                    values: cleanedValues
                )
            }
        }

        for defaultTest in BloodTestsDefaults.defaultTests {
            let key = BloodTestsDefaults.normalizedName(defaultTest)
            if rowsByNormalizedName[key] == nil {
                rowsByNormalizedName[key] = BloodTestRowRecord(
                    id: UUID(),
                    testName: defaultTest,
                    values: [:]
                )
            }
        }

        var uniqueColumns: [UUID: BloodTestColumnRecord] = [:]
        for column in payload.columns {
            let text = column.dateText.trimmingCharacters(in: .whitespacesAndNewlines)
            uniqueColumns[column.id] = BloodTestColumnRecord(id: column.id, dateText: text)
        }

        let columns = Array(uniqueColumns.values)
        let allowedColumnIDs = Set(columns.map(\.id.uuidString))

        let rows = rowsByNormalizedName.values.map { row in
            let filteredValues = row.values.reduce(into: [String: String]()) { partial, entry in
                if allowedColumnIDs.contains(entry.key) {
                    partial[entry.key] = entry.value
                }
            }
            return BloodTestRowRecord(id: row.id, testName: row.testName, values: filteredValues)
        }

        return BloodTestsTablePayload(columns: columns, rows: rows)
    }

    static func decodePayload(from raw: String?) -> BloodTestsTablePayload {
        guard
            let raw,
            let data = raw.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(BloodTestsTablePayload.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    static func encodePayload(_ payload: BloodTestsTablePayload) -> String {
        guard let data = try? JSONEncoder().encode(payload), let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func dateText(from date: Date) -> String {
        writeDateFormatter.string(from: date)
    }

    static func parsedDate(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for formatter in parseDateFormatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }
}
