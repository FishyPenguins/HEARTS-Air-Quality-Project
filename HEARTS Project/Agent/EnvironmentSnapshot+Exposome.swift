import Foundation

extension EnvironmentSnapshot {
    /// Pulls whatever readings ExposomeService has loaded so far into a snapshot for the agent.
    @MainActor
    init(statuses: [ExposomeFactor: ExposomeStatus], locationName: String?) {
        func value(_ factor: ExposomeFactor) -> Double? {
            switch statuses[factor] {
            case .available(let reading): return reading.numericValue
            case .failed(_, let lastKnown?): return lastKnown.numericValue
            default: return nil
            }
        }
        self.init(
            locationName: locationName,
            aqi: value(.aqi).map { Int($0) },
            pm25: value(.pm25),
            temperatureF: value(.temperature),
            humidityPercent: value(.humidity),
            heatIndexF: value(.heatIndex),
            pollen: value(.pollen)
        )
    }
}

extension EnvironmentSnapshot {
    /// Same snapshot, plus the selected person and their risk, so the chat answers for that person.
    nonisolated func personalized(for patient: Patient?, risk: RiskAssessment?) -> EnvironmentSnapshot {
        var copy = self
        copy.patientDescription = patient?.promptDescription
        copy.riskDescription = risk?.promptDescription
        var hints: [String] = []
        if let patient {
            if patient.hasCOPD { hints.append("copd lungs breathing") }
            if patient.hasCKD || patient.takesDiuretic { hints.append("heat medications water pills") }
        }
        if let risk, risk.levelIndex >= 2 { hints.append("warning signs weight swelling") }
        copy.patientHints = hints
        return copy
    }
}
