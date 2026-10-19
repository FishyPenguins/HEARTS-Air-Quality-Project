import Foundation

/// The HEARTS risk model, running on the phone.
///
/// It is a logistic regression trained by model/train_risk_model.py on the FAKE practice patients
/// (Risk/hearts_risk_model.json holds its numbers). Chart features set each person's baseline risk.
/// Air and heat are added on top using effect sizes from published studies, since 38 fake patients
/// are far too few to learn them. The output is the chance of a heart failure hospitalization in
/// the next 7 days if today's conditions continue. It is a prototype, not a real prediction.
nonisolated struct RiskModel: Codable, Sendable {
    struct Feature: Codable, Sendable {
        let key: String
        let label: String
        let coef: Double
        let mean: Double
        let scale: Double
    }

    struct Environment: Codable, Sendable {
        let pm25PerUgm3: Double
        let heatIndexThresholdF: Double
        let heatPerDegreeF: Double
        let coldThresholdF: Double
        let coldPerDegreeF: Double
        let referencePM25: Double
    }

    struct Level: Codable, Sendable {
        let name: String
        let below: Double?
    }

    struct Metrics: Codable, Sendable {
        let patientDays: Int
        let events: Int
        let crossValidatedAUC: Double
    }

    let name: String
    let version: String
    let horizonDays: Int
    let trainedOn: String
    let disclaimer: String
    let intercept: Double
    let features: [Feature]
    let environment: Environment
    let levels: [Level]
    let metrics: Metrics

    // MARK: - Loading

    enum LoadError: LocalizedError {
        case missingFile
        var errorDescription: String? { "hearts_risk_model.json is missing from the app bundle." }
    }

    static func bundled(in bundle: Bundle = .main) throws -> RiskModel {
        guard let url = bundle.url(forResource: "hearts_risk_model", withExtension: "json") else {
            throw LoadError.missingFile
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> RiskModel {
        try JSONDecoder().decode(RiskModel.self, from: data)
    }

    // MARK: - Scoring

    /// Turns one chart feature into the same number the Python trainer used. Keys must match.
    func featureValue(_ key: String, for p: Patient) -> Double {
        switch key {
        case "age10":        return Double(p.age) / 10
        case "nyha":         return Double(p.nyhaClass)
        case "logNTproBNP":  return log(max(p.ntProBNP, 1))
        case "priorHFStays": return Double(min(p.priorHFHospitalizations, 5))
        case "reducedEF":    return p.hasReducedEF ? 1 : 0
        case "ckd":          return p.hasCKD ? 1 : 0
        case "diabetes":     return p.hasDiabetes ? 1 : 0
        case "copd":         return p.hasCOPD ? 1 : 0
        case "lowSodium":    return p.sodium < 135 ? 1 : 0
        case "homeOxygen":   return p.usesHomeOxygen ? 1 : 0
        case "sglt2":        return p.takesSGLT2 ? 1 : 0
        case "pollutedArea": return p.livesInPollutedArea ? 1 : 0
        default:             return 0
        }
    }

    func assess(_ patient: Patient, conditions: RiskConditions) -> RiskAssessment {
        var contributions: [(feature: Feature, value: Double)] = []
        var linear = intercept
        for feature in features {
            let z = (featureValue(feature.key, for: patient) - feature.mean) / feature.scale
            let contribution = feature.coef * z
            contributions.append((feature, contribution))
            linear += contribution
        }

        let env = environment
        let pm25 = conditions.pm25 ?? env.referencePM25
        let pmTerm = env.pm25PerUgm3 * (pm25 - env.referencePM25)
        let heatTerm = conditions.heatIndexF.map { env.heatPerDegreeF * max(0, $0 - env.heatIndexThresholdF) } ?? 0
        let coldTerm = conditions.temperatureF.map { env.coldPerDegreeF * max(0, env.coldThresholdF - $0) } ?? 0

        let baseline = weekRisk(linear)
        let current = weekRisk(linear + pmTerm + heatTerm + coldTerm)

        var drivers: [RiskAssessment.Driver] = contributions
            .filter { abs($0.value) >= 0.05 }
            .map { .init(label: describe($0.feature, for: patient), impact: $0.value, kind: .chart) }
        if pmTerm > 0.001 {
            drivers.append(.init(label: "Air pollution today (PM2.5 \(Int(pm25.rounded())) µg/m³)", impact: pmTerm, kind: .air))
        }
        if heatTerm > 0.001, let hi = conditions.heatIndexF {
            drivers.append(.init(label: "Heat (feels like \(Int(hi.rounded()))°F)", impact: heatTerm, kind: .heat))
        }
        if coldTerm > 0.001, let t = conditions.temperatureF {
            drivers.append(.init(label: "Cold (\(Int(t.rounded()))°F), watch the next 3 to 5 days", impact: coldTerm, kind: .cold))
        }

        return RiskAssessment(
            patientID: patient.id,
            horizonDays: horizonDays,
            baselineRisk: baseline,
            currentRisk: current,
            levelIndex: levelIndex(for: current),
            levelName: levelName(for: current),
            raising: drivers.filter { $0.impact > 0 }.sorted { $0.impact > $1.impact },
            lowering: drivers.filter { $0.impact < 0 }.sorted { $0.impact < $1.impact },
            conditions: conditions
        )
    }

    private func weekRisk(_ logit: Double) -> Double {
        let daily = 1 / (1 + exp(-logit))
        return 1 - pow(1 - daily, Double(horizonDays))
    }

    private func levelIndex(for risk: Double) -> Int {
        levels.firstIndex { level in level.below.map { risk < $0 } ?? true } ?? max(levels.count - 1, 0)
    }

    private func levelName(for risk: Double) -> String {
        levels.isEmpty ? "Unknown" : levels[levelIndex(for: risk)].name
    }

    private func describe(_ feature: Feature, for p: Patient) -> String {
        switch feature.key {
        case "age10":        return "Age \(p.age)"
        case "nyha":         return "NYHA class \(p.nyhaClass)"
        case "logNTproBNP":  return "NT-proBNP \(Int(p.ntProBNP)) pg/mL"
        case "priorHFStays": return "\(p.priorHFHospitalizations) past heart failure hospital stay\(p.priorHFHospitalizations == 1 ? "" : "s")"
        case "reducedEF":    return "Ejection fraction \(p.ejectionFraction)%"
        case "lowSodium":    return "Sodium \(Int(p.sodium))"
        case "sglt2":        return p.takesSGLT2 ? "Takes an SGLT2 inhibitor" : "Not on an SGLT2 inhibitor"
        case "pollutedArea": return p.livesInPollutedArea ? "Lives in a polluted area" : "Lives in a cleaner area"
        default:
            let value = featureValue(feature.key, for: p)
            return value > 0 ? feature.label : "No \(feature.label.lowercased())"
        }
    }
}

/// The conditions the risk model scores. Usually today's live readings, or what-if values in the demo.
nonisolated struct RiskConditions: Equatable, Sendable {
    var aqi: Int?
    var pm25: Double?
    var heatIndexF: Double?
    var temperatureF: Double?

    static let clean = RiskConditions(aqi: 20, pm25: 5, heatIndexF: 70, temperatureF: 70)

    init(aqi: Int? = nil, pm25: Double? = nil, heatIndexF: Double? = nil, temperatureF: Double? = nil) {
        self.aqi = aqi
        self.pm25 = pm25 ?? aqi.map { AQI.pm25(fromAQI: $0) }
        self.heatIndexF = heatIndexF ?? temperatureF
        self.temperatureF = temperatureF
    }

    init(snapshot: EnvironmentSnapshot) {
        self.init(aqi: snapshot.aqi, pm25: snapshot.pm25,
                  heatIndexF: snapshot.heatIndexF, temperatureF: snapshot.temperatureF)
    }
}

nonisolated struct RiskAssessment: Equatable, Sendable {
    enum DriverKind: Sendable { case chart, air, heat, cold }

    struct Driver: Equatable, Sendable, Identifiable {
        let label: String
        let impact: Double
        let kind: DriverKind
        var id: String { label }
    }

    let patientID: String
    let horizonDays: Int
    /// Risk on a clean-air, mild day.
    let baselineRisk: Double
    /// Risk with today's air and heat.
    let currentRisk: Double
    /// 0 = Low, 1 = Moderate, 2 = Elevated, 3 = High.
    let levelIndex: Int
    let levelName: String
    let raising: [Driver]
    let lowering: [Driver]
    let conditions: RiskConditions

    /// How much today's air and heat change the risk, as a percent of the clean-day risk.
    var environmentChangePercent: Double {
        baselineRisk > 0 ? (currentRisk / baselineRisk - 1) * 100 : 0
    }

    var environmentDrivers: [Driver] { raising.filter { $0.kind != .chart } }

    var percentText: String { Self.percent(currentRisk) }

    static func percent(_ value: Double) -> String {
        let pct = value * 100
        return pct < 10 ? String(format: "%.1f%%", pct) : "\(Int(pct.rounded()))%"
    }

    /// What the chat agent is told.
    var promptDescription: String {
        var lines = [
            "HEARTS risk model (student prototype trained on fake patients, not a real prediction): \(levelName) risk.",
            "Chance of a heart failure hospital stay in the next \(horizonDays) days if today's conditions continue: \(Self.percent(currentRisk)) (on a clean, mild day: \(Self.percent(baselineRisk)))."
        ]
        if environmentChangePercent >= 0.5 {
            lines.append("Today's air and heat raise that by about \(Int(environmentChangePercent.rounded()))%.")
        }
        if !raising.isEmpty {
            lines.append("Biggest things raising risk: " + raising.prefix(4).map(\.label).joined(separator: "; "))
        }
        if !lowering.isEmpty {
            lines.append("Things lowering risk: " + lowering.prefix(3).map(\.label).joined(separator: "; "))
        }
        return lines.map { "- " + $0 }.joined(separator: "\n")
    }
}

/// US EPA AQI breakpoints for PM2.5 (2024 update), used to turn an AQI into PM2.5 and back.
nonisolated enum AQI {
    private static let breakpoints: [(cLow: Double, cHigh: Double, iLow: Double, iHigh: Double)] = [
        (0.0, 9.0, 0, 50),
        (9.1, 35.4, 51, 100),
        (35.5, 55.4, 101, 150),
        (55.5, 125.4, 151, 200),
        (125.5, 225.4, 201, 300),
        (225.5, 325.4, 301, 500)
    ]

    static func pm25(fromAQI aqi: Int) -> Double {
        let i = Double(max(0, min(aqi, 500)))
        let bp = breakpoints.first { i <= $0.iHigh } ?? breakpoints[breakpoints.count - 1]
        return bp.cLow + (i - bp.iLow) * (bp.cHigh - bp.cLow) / (bp.iHigh - bp.iLow)
    }

    static func category(_ aqi: Int) -> String {
        switch aqi {
        case ..<51: return "Good"
        case 51...100: return "Moderate"
        case 101...150: return "Unhealthy for Sensitive Groups"
        case 151...200: return "Unhealthy"
        case 201...300: return "Very Unhealthy"
        default: return "Hazardous"
        }
    }
}
