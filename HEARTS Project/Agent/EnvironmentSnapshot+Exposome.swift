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
