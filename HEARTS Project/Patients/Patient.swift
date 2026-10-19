import Foundation

/// One person HEARTS is looking after. The 38 built-in people are the FAKE practice patients from
/// HEARTS_fake_patients_v2 (Patients/hearts_patients.json, written by model/train_risk_model.py).
/// Anyone can also enter their own info, which is saved only on the phone.
nonisolated struct Patient: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var age: Int
    var gender: String
    var zip: String
    var town: String
    var areaType: String
    var insurance: String
    var employment: String
    var diabetes: String
    var hypertension: String
    var copd: String
    var ckd: String
    var cad: String
    var sleepApnea: String
    var homeOxygenL: Double
    var bmi: Double
    var sodium: Double
    var ntProBNP: Double
    var nyhaClass: Int
    var ejectionFraction: Int
    var priorHFHospitalizations: Int
    var heartRate: Int
    var systolicBP: Int
    var diastolicBP: Int
    var o2Saturation: Int
    var medications: [String]
    var onDiuretics: String
    var onBetaBlockers: String
    var onSGLT2: String
    var lastHFHospitalization: String
    /// True for the "My info" profile the user typed in. Missing (nil) for the built-in patients.
    var isCustom: Bool?

    static let customID = "ME"

    var isCustomProfile: Bool { isCustom == true }

    var displayName: String { isCustomProfile ? "My info" : "Patient \(id)" }

    /// Short initials for the avatar bubble.
    var badge: String { isCustomProfile ? "ME" : id }

    var hasDiabetes: Bool { Self.yes(diabetes) }
    var hasHypertension: Bool { Self.yes(hypertension) }
    var hasCOPD: Bool { Self.yes(copd) }
    var hasCKD: Bool { Self.yes(ckd) }
    var hasCAD: Bool { Self.yes(cad) }
    var hasSleepApnea: Bool { Self.yes(sleepApnea) }
    var takesSGLT2: Bool { Self.yes(onSGLT2) }
    var takesDiuretic: Bool { Self.yes(onDiuretics) }
    var usesHomeOxygen: Bool { homeOxygenL > 0 }
    var livesInPollutedArea: Bool { areaType.lowercased().hasPrefix("polluted") }
    var hasReducedEF: Bool { ejectionFraction <= 40 }

    /// One line for list rows: "72 · Female · Cheshire".
    var summaryLine: String { "\(age) · \(gender) · \(town)" }

    var conditions: [String] {
        var list: [String] = []
        if hasHypertension { list.append("High blood pressure") }
        if hasDiabetes { list.append("Diabetes") }
        if hasCAD { list.append("Coronary artery disease") }
        if hasCKD { list.append("Kidney disease") }
        if hasCOPD { list.append("COPD") }
        if hasSleepApnea { list.append("Sleep apnea") }
        if usesHomeOxygen { list.append("Home oxygen \(Self.trim(homeOxygenL)) L") }
        return list
    }

    /// What the chat agent is told about this person. Plain text, no names.
    var promptDescription: String {
        var lines = [
            "\(age)-year-old \(gender.lowercased()) living in \(town) (\(livesInPollutedArea ? "a polluted / disadvantaged area" : "a cleaner area"))",
            "Heart failure: NYHA class \(nyhaClass), ejection fraction \(ejectionFraction)%, NT-proBNP \(Int(ntProBNP)) pg/mL",
            "Past heart failure hospital stays: \(priorHFHospitalizations)"
        ]
        lines.append("Other conditions: " + (conditions.isEmpty ? "none listed" : conditions.joined(separator: ", ")))
        if !medications.isEmpty { lines.append("Home medicines: " + medications.joined(separator: ", ")) }
        lines.append("Works: \(employment)")
        return lines.map { "- " + $0 }.joined(separator: "\n")
    }

    /// Starting point for the "Enter my own info" form.
    static var customTemplate: Patient {
        Patient(id: customID, age: 60, gender: "Female", zip: "06518", town: "Hamden",
                areaType: "Clean", insurance: "Private", employment: "Employed full-time",
                diabetes: "No", hypertension: "No", copd: "No", ckd: "No", cad: "No", sleepApnea: "No",
                homeOxygenL: 0, bmi: 28, sodium: 138, ntProBNP: 1500, nyhaClass: 2, ejectionFraction: 40,
                priorHFHospitalizations: 0, heartRate: 72, systolicBP: 125, diastolicBP: 78, o2Saturation: 96,
                medications: [], onDiuretics: "No", onBetaBlockers: "No", onSGLT2: "No",
                lastHFHospitalization: "", isCustom: true)
    }

    static func yes(_ value: String) -> Bool { value.trimmingCharacters(in: .whitespaces).lowercased() == "yes" }
    static func yesNo(_ flag: Bool) -> String { flag ? "Yes" : "No" }

    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

nonisolated enum PatientLoader {
    enum LoadError: LocalizedError {
        case missingFile
        var errorDescription: String? { "hearts_patients.json is missing from the app bundle." }
    }

    static func bundled(in bundle: Bundle = .main) throws -> [Patient] {
        guard let url = bundle.url(forResource: "hearts_patients", withExtension: "json") else {
            throw LoadError.missingFile
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> [Patient] {
        try JSONDecoder().decode([Patient].self, from: data)
    }
}
