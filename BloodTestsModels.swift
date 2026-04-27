import Foundation

struct BloodTestColumnRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var dateText: String
}

struct BloodTestRowRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var testName: String
    var values: [String: String]
}

struct BloodTestsTablePayload: Codable, Equatable {
    var columns: [BloodTestColumnRecord]
    var rows: [BloodTestRowRecord]

    static let empty = BloodTestsTablePayload(columns: [], rows: [])
}

enum BloodTestsDefaults {
    static let defaultTests: [String] = [
        "Leucociti (WBC)",
        "Piastrine (PLT)",
        "Emoglobina (Hb)",
        "Ematocrito (Hct)",
        "Neutrofili assoluti (ANC)",
        "Glucosio",
        "Creatinina (Crea)",
        "eGFR",
        "TSH",
        "FT4 (Tiroxina libera)",
        "Sodio (Na)",
        "Potassio (K)",
        "Magnesio (Mg)",
        "Calcio (Ca)",
        "AST (GOT)",
        "ALT (GPT)",
        "Gamma GT (GGT)",
        "CK (CPK)",
        "Prolattina (Prl)",
        "Bilirubina totale",
        "Colesterolo totale",
        "HDL",
        "LDL",
        "Ammonio",
        "Valproatemia (Ac. valproico)",
        "Litiemia (Li)",
        "Clozapinemia (Clo)",
        "Carbamazepinemia (Car)",
        "Vitamina B12",
        "Folati",
        "Vitamina D (25-OH)"
    ]

    static let defaultTestSet: Set<String> = Set(defaultTests.map { normalizedName(canonicalName($0)) })
    static let defaultTestOrder: [String: Int] = {
        Dictionary(uniqueKeysWithValues: defaultTests.enumerated().map { (index, value) in
            (normalizedName(canonicalName(value)), index)
        })
    }()

    static let canonicalByAlias: [String: String] = {
        let pairs: [(String, String)] = [
            ("WBC", "Leucociti (WBC)"),
            ("PTL", "Piastrine (PLT)"),
            ("PLT", "Piastrine (PLT)"),
            ("HB", "Emoglobina (Hb)"),
            ("HCT", "Ematocrito (Hct)"),
            ("ANC", "Neutrofili assoluti (ANC)"),
            ("FT4", "FT4 (Tiroxina libera)"),
            ("NA", "Sodio (Na)"),
            ("K", "Potassio (K)"),
            ("MG", "Magnesio (Mg)"),
            ("CA", "Calcio (Ca)"),
            ("AST", "AST (GOT)"),
            ("ALT", "ALT (GPT)"),
            ("GGT", "Gamma GT (GGT)"),
            ("CPK", "CK (CPK)"),
            ("CK", "CK (CPK)"),
            ("PROLATTINA (PRL)", "Prolattina (Prl)"),
            ("BILIRUBINA", "Bilirubina totale"),
            ("COLESTEROLO TOT", "Colesterolo totale"),
            ("VIT. D", "Vitamina D (25-OH)"),
            ("VIT D", "Vitamina D (25-OH)"),
            ("B12", "Vitamina B12"),
            ("AC. VALPROICO (VAL)", "Valproatemia (Ac. valproico)"),
            ("LITIO (LI)", "Litiemia (Li)"),
            ("CLOZAPINA (CLO)", "Clozapinemia (Clo)"),
            ("CARBAMAZEPINA (CAR)", "Carbamazepinemia (Car)")
        ]

        return Dictionary(uniqueKeysWithValues: pairs.map {
            (normalizedName($0.0), $0.1)
        })
    }()

    static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
    }

    static func canonicalName(_ value: String) -> String {
        let normalized = normalizedName(value)
        return canonicalByAlias[normalized] ?? value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
