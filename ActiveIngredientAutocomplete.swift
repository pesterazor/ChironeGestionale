import Foundation

struct ActiveIngredientAutocomplete {
    static let shared = ActiveIngredientAutocomplete()

    private let ingredients: [String]
    private let normalizedByIngredient: [String: String]
    private let ingredientByNormalized: [String: String]
    private let prefixIndex: [String: [String]]
    private let normalizedFormsByIngredient: [String: [(raw: String, normalized: String)]]

    private init() {
        guard
            let url = Bundle.main.url(forResource: "active_ingredients_it", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            ingredients = []
            normalizedByIngredient = [:]
            ingredientByNormalized = [:]
            prefixIndex = [:]
            normalizedFormsByIngredient = [:]
            return
        }

        ingredients = decoded

        var normalized: [String: String] = [:]
        normalized.reserveCapacity(decoded.count)
        var reverseNormalized: [String: String] = [:]
        reverseNormalized.reserveCapacity(decoded.count)

        var index: [String: [String]] = [:]
        index.reserveCapacity(decoded.count * 2)

        for ingredient in decoded {
            let key = Self.normalized(ingredient)
            normalized[ingredient] = key
            reverseNormalized[key] = ingredient

            for prefixLength in 2...3 {
                guard key.count >= prefixLength else { continue }
                let prefix = String(key.prefix(prefixLength))
                index[prefix, default: []].append(ingredient)
            }
        }

        let forms = Self.loadForms()
        var normalizedForms: [String: [(raw: String, normalized: String)]] = [:]
        normalizedForms.reserveCapacity(forms.count)
        for (ingredient, values) in forms {
            normalizedForms[ingredient] = values.map { ($0, Self.normalized($0)) }
        }

        normalizedByIngredient = normalized
        ingredientByNormalized = reverseNormalized
        prefixIndex = index
        normalizedFormsByIngredient = normalizedForms
    }

    func suggestions(for query: String, limit: Int = 12) -> [String] {
        let normalizedQuery = Self.normalized(query)
        guard normalizedQuery.count >= 2 else { return [] }

        let prefixLength = min(3, normalizedQuery.count)
        let prefix = String(normalizedQuery.prefix(prefixLength))
        let candidates = prefixIndex[prefix] ?? ingredients

        var results: [String] = []
        results.reserveCapacity(min(limit, candidates.count))

        for ingredient in candidates {
            guard let normalizedIngredient = normalizedByIngredient[ingredient] else { continue }
            guard normalizedIngredient.hasPrefix(normalizedQuery) else { continue }
            results.append(ingredient)
            if results.count == limit {
                break
            }
        }

        return results
    }

    func formulationSuggestions(
        for ingredientQuery: String,
        formulationQuery: String,
        limit: Int = 12
    ) -> [String] {
        let normalizedIngredient = Self.normalized(ingredientQuery)
        let normalizedFormulation = Self.normalized(formulationQuery)

        let ingredient: String
        if let resolved = ingredientByNormalized[normalizedIngredient] {
            ingredient = resolved
        } else {
            guard let best = suggestions(for: ingredientQuery, limit: 1).first else { return [] }
            ingredient = best
        }

        guard let source = normalizedFormsByIngredient[ingredient], !source.isEmpty else { return [] }

        // If user has selected ingredient but hasn't typed dosage yet,
        // surface the most common formulations immediately.
        if normalizedFormulation.isEmpty {
            return Array(source.prefix(limit).map(\.raw))
        }

        if normalizedFormulation.count < 2 {
            return Array(source.prefix(limit).map(\.raw))
        }

        var results: [String] = []
        results.reserveCapacity(min(limit, source.count))
        for entry in source {
            guard entry.normalized.hasPrefix(normalizedFormulation) else { continue }
            results.append(entry.raw)
            if results.count == limit {
                break
            }
        }
        return results
    }

    private static func loadForms() -> [String: [String]] {
        guard
            let url = Bundle.main.url(forResource: "active_ingredient_forms_it", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else {
            return [:]
        }

        var sortedForms: [String: [String]] = [:]
        sortedForms.reserveCapacity(decoded.count)

        for (ingredient, values) in decoded {
            sortedForms[ingredient] = values.sorted { lhs, rhs in
                dosageSortKey(lhs) < dosageSortKey(rhs)
            }
        }

        return sortedForms
    }

    private static func dosageSortKey(_ formulation: String) -> (hasDose: Int, dose: Double, unit: Int, fallback: String) {
        let pattern = #"(\d+(?:[.,]\d+)?)\s*(MCG|MICROG|MG|G|UI|MUI|MEQ|MMOL|MG/ML|MCG/ML|G/ML|MG/G|%)"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(
                in: formulation,
                options: [],
                range: NSRange(formulation.startIndex..<formulation.endIndex, in: formulation)
            ),
            let doseRange = Range(match.range(at: 1), in: formulation),
            let unitRange = Range(match.range(at: 2), in: formulation)
        else {
            return (1, .infinity, 99, formulation.localizedLowercase)
        }

        let doseString = formulation[doseRange].replacingOccurrences(of: ",", with: ".")
        let dose = Double(doseString) ?? .infinity
        let unitRaw = formulation[unitRange].uppercased().replacingOccurrences(of: "MICROG", with: "MCG")

        let unitOrder: [String: Int] = [
            "MCG": 0, "MG": 1, "G": 2,
            "MG/ML": 3, "MCG/ML": 4, "G/ML": 5, "MG/G": 6,
            "UI": 7, "MUI": 8, "MEQ": 9, "MMOL": 10, "%": 11
        ]

        return (0, dose, unitOrder[unitRaw] ?? 99, formulation.localizedLowercase)
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
            .uppercased()
    }
}
