import Foundation

enum BloodTestCalculators {
    struct EGFRGenderFactors {
        let kappa: Double
        let alpha: Double
        let isFemale: Bool
    }

    // CKD-EPI 2021 creatinine equation (creatinina in mg/dL).
    static func eGFRCKDEPI2021(
        creatinineMgDl: Double,
        ageYears: Int,
        patientGender: String?
    ) -> Double? {
        guard creatinineMgDl > 0, ageYears > 0, let factors = genderFactors(from: patientGender) else {
            return nil
        }

        let ratio = creatinineMgDl / factors.kappa
        let minPart = pow(min(ratio, 1), factors.alpha)
        let maxPart = pow(max(ratio, 1), -1.2)
        let agePart = pow(0.9938, Double(ageYears))
        let femalePart = factors.isFemale ? 1.012 : 1.0

        return 142.0 * minPart * maxPart * agePart * femalePart
    }

    // Friedewald formula in mg/dL (valid when TG < 400 mg/dL).
    static func ldlFriedewald(
        totalCholesterolMgDl: Double,
        hdlMgDl: Double,
        triglyceridesMgDl: Double
    ) -> Double? {
        guard triglyceridesMgDl < 400 else { return nil }
        let ldl = totalCholesterolMgDl - hdlMgDl - (triglyceridesMgDl / 5.0)
        return max(ldl, 0)
    }

    private static func genderFactors(from rawGender: String?) -> EGFRGenderFactors? {
        let normalized = BloodTestsDefaults.normalizedName(rawGender ?? "")
        if normalized.contains("femmina") {
            return EGFRGenderFactors(kappa: 0.7, alpha: -0.241, isFemale: true)
        }
        if normalized.contains("maschio") {
            return EGFRGenderFactors(kappa: 0.9, alpha: -0.302, isFemale: false)
        }
        return nil
    }
}
