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

    static func applyDerivedCalculations(
        to payload: inout BloodTestsTablePayload,
        forColumnID columnID: UUID,
        patientDateOfBirth: Date?,
        patientGender: String?
    ) {
        let key = columnID.uuidString

        let creatinineIndex = rowIndex(in: payload.rows, matchingAny: ["creatinina", "crea"])
        let eGFRIndex = rowIndex(in: payload.rows, matchingAny: ["egfr"])
        if let eGFRIndex {
            if
                let creatinineIndex,
                let creatinine = numericValue(from: payload.rows[creatinineIndex].values[key]),
                creatinine > 0,
                let dateOfBirth = patientDateOfBirth,
                let age = yearsSince(dateOfBirth),
                age > 0
            {
                if let egfr = BloodTestCalculators.eGFRCKDEPI2021(
                    creatinineMgDl: creatinine,
                    ageYears: age,
                    patientGender: patientGender
                ) {
                    payload.rows[eGFRIndex].values[key] = formatLabValue(egfr, maxFractionDigits: 0)
                } else {
                    payload.rows[eGFRIndex].values.removeValue(forKey: key)
                }
            } else {
                payload.rows[eGFRIndex].values.removeValue(forKey: key)
            }
        }

        let ldlIndex = rowIndex(in: payload.rows, matchingAny: ["ldl"])
        let hdlIndex = rowIndex(in: payload.rows, matchingAny: ["hdl"])
        let totalCholIndex = rowIndex(in: payload.rows, matchingAny: ["colesterolo totale", "colesterolo tot"])
        let triglyceridesIndex = rowIndex(in: payload.rows, matchingAny: ["trigliceridi", "triglycerides", "tg"])

        if let ldlIndex {
            if
                let hdlIndex,
                let totalCholIndex,
                let triglyceridesIndex,
                let total = numericValue(from: payload.rows[totalCholIndex].values[key]),
                let hdl = numericValue(from: payload.rows[hdlIndex].values[key]),
                let triglycerides = numericValue(from: payload.rows[triglyceridesIndex].values[key]),
                triglycerides < 400
            {
                if let ldl = BloodTestCalculators.ldlFriedewald(
                    totalCholesterolMgDl: total,
                    hdlMgDl: hdl,
                    triglyceridesMgDl: triglycerides
                ) {
                    payload.rows[ldlIndex].values[key] = formatLabValue(ldl, maxFractionDigits: 0)
                } else {
                    payload.rows[ldlIndex].values.removeValue(forKey: key)
                }
            } else {
                payload.rows[ldlIndex].values.removeValue(forKey: key)
            }
        }
    }

    static func bloodTestsRequestNoteText(
        from previous: BloodTestsTablePayload,
        to current: BloodTestsTablePayload
    ) -> String? {
        guard previous != current else { return nil }

        let previousByName = rowsDictionary(from: previous.rows)
        let currentByName = rowsDictionary(from: current.rows)

        let allKeys = Set(previousByName.keys).union(currentByName.keys)
        var touchedExamNames: [String] = []

        for key in allKeys {
            let oldValues = previousByName[key]?.values ?? [:]
            let newValues = currentByName[key]?.values ?? [:]

            guard hasInsertedOrUpdatedValue(from: oldValues, to: newValues) else { continue }

            if let name = currentByName[key]?.displayName ?? previousByName[key]?.displayName {
                touchedExamNames.append(name)
            }
        }

        let sortedNames = touchedExamNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        guard !sortedNames.isEmpty else { return nil }
        return "Presa visione esami ematochimici: \(sortedNames.joined(separator: ", "))."
    }

    private static func hasInsertedOrUpdatedValue(from oldValues: [String: String], to newValues: [String: String]) -> Bool {
        for (columnKey, newValue) in newValues {
            if oldValues[columnKey] != newValue {
                return true
            }
        }
        return false
    }

    private static func rowIndex(in rows: [BloodTestRowRecord], matchingAny tokens: [String]) -> Int? {
        rows.firstIndex { row in
            let normalized = BloodTestsDefaults.normalizedName(row.testName)
            return tokens.contains { token in
                let normalizedToken = BloodTestsDefaults.normalizedName(token)
                return normalized == normalizedToken || normalized.contains(normalizedToken)
            }
        }
    }

    private static func numericValue(from raw: String?) -> Double? {
        guard let raw else { return nil }
        let normalized = raw.replacingOccurrences(of: ",", with: ".")

        let pattern = "[-+]?[0-9]*\\.?[0-9]+"
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: normalized, range: NSRange(location: 0, length: normalized.utf16.count)),
            let range = Range(match.range, in: normalized)
        else {
            return nil
        }

        return Double(String(normalized[range]))
    }

    private static func yearsSince(_ dateOfBirth: Date) -> Int? {
        let ageComponents = Calendar.current.dateComponents([.year], from: dateOfBirth, to: .now)
        guard let years = ageComponents.year, years >= 0 else { return nil }
        return years
    }

    private static func formatLabValue(_ value: Double, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "it_IT")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func rowsDictionary(from rows: [BloodTestRowRecord]) -> [String: (displayName: String, values: [String: String])] {
        var result: [String: (displayName: String, values: [String: String])] = [:]

        for row in rows {
            let canonical = BloodTestsDefaults.canonicalName(row.testName)
            let key = BloodTestsDefaults.normalizedName(canonical)
            let cleanedValues = row.values.reduce(into: [String: String]()) { partial, pair in
                let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    partial[pair.key] = value
                }
            }
            result[key] = (displayName: canonical, values: cleanedValues)
        }

        return result
    }
}
