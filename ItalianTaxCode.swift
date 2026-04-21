//
//  ItalianTaxCode.swift
//  ChironeGestionale
//
//  Created by Codex on 21/04/2026.
//

import Foundation

enum ItalianTaxCode {
    struct PlaceSuggestion: Identifiable, Hashable {
        let name: String
        let province: String
        let cadastralCode: String

        var id: String { "\(name)|\(province)|\(cadastralCode)" }
        var displayText: String { "\(name) (\(province)) - \(cadastralCode)" }
    }

    static func generate(
        firstName: String,
        lastName: String,
        birthDate: Date?,
        gender: String?,
        placeOfBirth: String,
        birthProvince: String? = nil
    ) -> String? {
        guard let birthDate else { return nil }
        guard let genderCode = genderCode(from: gender) else { return nil }
        guard let placeCode = resolvePlaceCode(from: placeOfBirth, province: birthProvince) else { return nil }

        let surnamePart = surnameCode(lastName)
        let namePart = nameCode(firstName)
        let datePart = birthDateCode(date: birthDate, genderCode: genderCode)

        let partial = surnamePart + namePart + datePart + placeCode
        guard partial.count == 15 else { return nil }

        return partial + String(controlCharacter(for: partial))
    }

    static func suggestions(for query: String, province: String? = nil, limit: Int = 8) -> [PlaceSuggestion] {
        let normalizedQuery = normalizePlaceString(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let provinceFilter = province?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        return allSuggestions
            .filter { suggestion in
                let nameMatches = normalizePlaceString(suggestion.name).hasPrefix(normalizedQuery)
                guard nameMatches else { return false }
                guard let provinceFilter, !provinceFilter.isEmpty else { return true }
                return suggestion.province == provinceFilter
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func surnameCode(_ value: String) -> String {
        personCode(value, treatNameRule: false)
    }

    private static func nameCode(_ value: String) -> String {
        personCode(value, treatNameRule: true)
    }

    private static func personCode(_ value: String, treatNameRule: Bool) -> String {
        let normalized = normalizedLetters(value)
        let consonants = normalized.filter { !"AEIOU".contains($0) }
        let vowels = normalized.filter { "AEIOU".contains($0) }

        var chars: [Character] = []

        if treatNameRule && consonants.count >= 4 {
            chars.append(consonants[0])
            chars.append(consonants[2])
            chars.append(consonants[3])
        } else {
            chars.append(contentsOf: consonants.prefix(3))
            if chars.count < 3 {
                chars.append(contentsOf: vowels.prefix(3 - chars.count))
            }
        }

        while chars.count < 3 {
            chars.append("X")
        }

        return String(chars.prefix(3))
    }

    private static func birthDateCode(date: Date, genderCode: GenderCode) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        let year = (components.year ?? 0) % 100
        let month = monthLetter(components.month ?? 1)
        let dayRaw = components.day ?? 1
        let day = genderCode == .female ? dayRaw + 40 : dayRaw

        return String(format: "%02d%@%02d", year, String(month), day)
    }

    private static func monthLetter(_ month: Int) -> Character {
        let map: [Int: Character] = [
            1: "A", 2: "B", 3: "C", 4: "D", 5: "E", 6: "H",
            7: "L", 8: "M", 9: "P", 10: "R", 11: "S", 12: "T"
        ]
        return map[month] ?? "A"
    }

    private static func controlCharacter(for partial: String) -> Character {
        let oddMap: [Character: Int] = [
            "0": 1, "1": 0, "2": 5, "3": 7, "4": 9, "5": 13, "6": 15, "7": 17, "8": 19, "9": 21,
            "A": 1, "B": 0, "C": 5, "D": 7, "E": 9, "F": 13, "G": 15, "H": 17, "I": 19, "J": 21,
            "K": 2, "L": 4, "M": 18, "N": 20, "O": 11, "P": 3, "Q": 6, "R": 8, "S": 12, "T": 14,
            "U": 16, "V": 10, "W": 22, "X": 25, "Y": 24, "Z": 23
        ]

        let evenMap: [Character: Int] = [
            "0": 0, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9,
            "A": 0, "B": 1, "C": 2, "D": 3, "E": 4, "F": 5, "G": 6, "H": 7, "I": 8, "J": 9,
            "K": 10, "L": 11, "M": 12, "N": 13, "O": 14, "P": 15, "Q": 16, "R": 17, "S": 18, "T": 19,
            "U": 20, "V": 21, "W": 22, "X": 23, "Y": 24, "Z": 25
        ]

        let chars = Array(partial)
        var sum = 0

        for (index, char) in chars.enumerated() {
            let upper = Character(String(char).uppercased())
            let position = index + 1
            if position % 2 == 0 {
                sum += evenMap[upper] ?? 0
            } else {
                sum += oddMap[upper] ?? 0
            }
        }

        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return alphabet[sum % 26]
    }

    private static func normalizedLetters(_ value: String) -> [Character] {
        let upper = value
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "it_IT"))
            .uppercased()

        return upper.filter { $0 >= "A" && $0 <= "Z" }
    }

    private enum GenderCode {
        case male
        case female
    }

    private static func genderCode(from value: String?) -> GenderCode? {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "maschio":
            return .male
        case "femmina":
            return .female
        default:
            return nil
        }
    }

    private static func resolvePlaceCode(from rawValue: String, province: String?) -> String? {
        let upper = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if let match = upper.range(of: #"[A-Z][0-9]{3}"#, options: .regularExpression) {
            return String(upper[match])
        }

        var normalized = normalizePlaceString(rawValue)
        if normalized.isEmpty { return nil }

        normalized = normalized
            .replacingOccurrences(of: "COMUNE DI ", with: "")
            .replacingOccurrences(of: "CITTA DI ", with: "")

        let provinceFilter = province?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if let records = comuniIndex[normalized] {
            if let provinceFilter, !provinceFilter.isEmpty,
               let selected = records.first(where: { $0.province == provinceFilter }) {
                return selected.cadastralCode
            }
            if let first = records.first {
                return first.cadastralCode
            }
        }

        // Gestione input "COMUNE PR" se la sigla è scritta nel campo luogo.
        let tokens = normalized.split(separator: " ").map(String.init)
        if tokens.count >= 2,
           let last = tokens.last,
           last.count == 2,
           provinceSiglas.contains(last) {
            let cityOnly = tokens.dropLast().joined(separator: " ")
            if let records = comuniIndex[cityOnly],
               let selected = records.first(where: { $0.province == last }) {
                return selected.cadastralCode
            }
        }

        return nil
    }

    private static func normalizePlaceString(_ value: String) -> String {
        let noDiacritics = value
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "it_IT"))
            .uppercased()

        return noDiacritics
            .replacingOccurrences(of: #"[^A-Z0-9]"#, with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
            .joined(separator: " ")
    }

    private struct ComuneRecord: Decodable {
        let name: String
        let province: String
        let cadastralCode: String

        enum CodingKeys: String, CodingKey {
            case nome
            case sigla
            case codiceCatastale
            case codiceCatastaleSnake = "codice_catastale"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .nome)
            province = (try? container.decode(String.self, forKey: .sigla)) ?? ""
            cadastralCode = (try? container.decode(String.self, forKey: .codiceCatastale))
                ?? (try? container.decode(String.self, forKey: .codiceCatastaleSnake))
                ?? ""
        }
    }

    private static let comuniIndex: [String: [ComuneRecord]] = loadComuniIndex()
    private static let allSuggestions: [PlaceSuggestion] = loadSuggestions()

    private static func loadComuniIndex() -> [String: [ComuneRecord]] {
        guard let url = Bundle.main.url(forResource: "comuni", withExtension: "json") else {
            return [:]
        }

        guard let data = try? Data(contentsOf: url) else {
            return [:]
        }

        guard let records = try? JSONDecoder().decode([ComuneRecord].self, from: data) else {
            return [:]
        }

        var index: [String: [ComuneRecord]] = [:]
        index.reserveCapacity(records.count)

        for record in records {
            let key = normalizePlaceString(record.name)
            guard !key.isEmpty, !record.cadastralCode.isEmpty else { continue }
            index[key, default: []].append(record)
        }

        return index
    }

    private static func loadSuggestions() -> [PlaceSuggestion] {
        comuniIndex
            .values
            .flatMap { $0 }
            .map { record in
                PlaceSuggestion(
                    name: record.name,
                    province: record.province,
                    cadastralCode: record.cadastralCode
                )
            }
            .sorted { lhs, rhs in
                let first = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if first == .orderedSame {
                    return lhs.province.localizedCaseInsensitiveCompare(rhs.province) == .orderedAscending
                }
                return first == .orderedAscending
            }
    }

    private static let provinceSiglas: Set<String> = [
        "AG", "AL", "AN", "AO", "AP", "AQ", "AR", "AT", "AV", "BA", "BT", "BL", "BN", "BG", "BI",
        "BO", "BZ", "BS", "BR", "CA", "CL", "CB", "CE", "CT", "CZ", "CH", "CO", "CS", "CR", "KR",
        "CN", "EN", "FM", "FE", "FI", "FG", "FC", "FR", "GE", "GO", "GR", "IM", "IS", "SP", "LT",
        "LE", "LC", "LI", "LO", "LU", "MC", "MN", "MS", "MT", "ME", "MI", "MO", "MB", "NA", "NO",
        "NU", "OR", "PD", "PA", "PR", "PV", "PG", "PU", "PE", "PC", "PI", "PT", "PN", "PZ", "PO",
        "RG", "RA", "RC", "RE", "RI", "RN", "RM", "RO", "SA", "SS", "SV", "SI", "SR", "SO", "TA",
        "TE", "TR", "TO", "TP", "TN", "TV", "TS", "UD", "VA", "VE", "VB", "VC", "VR", "VV", "VI",
        "VT"
    ]
}
