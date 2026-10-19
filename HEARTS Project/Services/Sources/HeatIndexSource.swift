import CoreLocation
import Foundation

/// Computes heat index from temperature + humidity using the NOAA Rothfusz regression.
/// Depends on NOAAWeatherSource having already fetched temp and humidity.
final class HeatIndexSource: ExposomeSource {
    var supportedFactors: [ExposomeFactor] { [.heatIndex] }

    private let weatherSource: NOAAWeatherSource

    init(weatherSource: NOAAWeatherSource) {
        self.weatherSource = weatherSource
    }

    func fetch(for factor: ExposomeFactor, at location: CLLocation) async throws -> ExposomeReading? {
        guard factor == .heatIndex else { return nil }

        async let tempResult    = weatherSource.fetch(for: .temperature, at: location)
        async let humidityResult = weatherSource.fetch(for: .humidity,    at: location)
        let (temp, humidity) = try await (tempResult, humidityResult)

        guard let t = temp, let h = humidity else { return nil }

        // Heat index is only meaningful when it's hot. Below 80°F return nil so
        // the dashboard shows "Not available" rather than a misleading number.
        guard t.numericValue >= 80 else { return nil }

        let hi = heatIndex(tempF: t.numericValue, rh: h.numericValue)
        return ExposomeReading(
            factor: .heatIndex,
            numericValue: hi,
            displayValue: String(format: "%.1f°F", hi),
            timestamp: t.timestamp
        )
    }

    /// NOAA Rothfusz regression. Valid for temperatures ≥ 80°F.
    private func heatIndex(tempF t: Double, rh: Double) -> Double {
        // Steadman simple formula for initial estimate
        let simple = 0.5 * (t + 61.0 + (t - 68.0) * 1.2 + rh * 0.094)
        guard simple >= 80 else { return (simple + t) / 2 }

        // Full Rothfusz regression
        var hi = -42.379
            + 2.04901523 * t
            + 10.14333127 * rh
            - 0.22475541 * t * rh
            - 0.00683783 * t * t
            - 0.05481717 * rh * rh
            + 0.00122874 * t * t * rh
            + 0.00085282 * t * rh * rh
            - 0.00000199 * t * t * rh * rh

        // Low-humidity adjustment
        if rh < 13, (80...112).contains(t) {
            hi -= (13 - rh) / 4 * sqrt((17 - abs(t - 95)) / 17)
        }
        // High-humidity adjustment
        if rh > 85, (80...87).contains(t) {
            hi += (rh - 85) / 10 * (87 - t) / 5
        }
        return hi
    }
}
