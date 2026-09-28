import CoreLocation
import Foundation

/// Fetches temperature and relative humidity from Open-Meteo (free, no API key required).
/// Replaced the original NOAA gridpoints path which was unreliable for many locations.
final class NOAAWeatherSource: ExposomeSource {
    var supportedFactors: [ExposomeFactor] { [.temperature, .humidity] }

    private var cache: [String: (temp: ExposomeReading, humidity: ExposomeReading, date: Date)] = [:]
    private let cacheTTL: TimeInterval = 1800

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private func cacheKey(for location: CLLocation) -> String {
        String(format: "%.2f,%.2f", location.coordinate.latitude, location.coordinate.longitude)
    }

    func fetch(for factor: ExposomeFactor, at location: CLLocation) async throws -> ExposomeReading? {
        guard factor == .temperature || factor == .humidity else { return nil }

        let key = cacheKey(for: location)
        if let cached = cache[key], Date().timeIntervalSince(cached.date) < cacheTTL {
            return factor == .temperature ? cached.temp : cached.humidity
        }

        let (temp, humidity) = try await fetchBoth(at: location)
        cache[key] = (temp, humidity, Date())
        return factor == .temperature ? temp : humidity
    }

    private func fetchBoth(at location: CLLocation) async throws -> (ExposomeReading, ExposomeReading) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude",         value: String(format: "%.4f", location.coordinate.latitude)),
            URLQueryItem(name: "longitude",        value: String(format: "%.4f", location.coordinate.longitude)),
            URLQueryItem(name: "current",          value: "temperature_2m,relative_humidity_2m"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "timezone",         value: "auto")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw WeatherError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let current = json?["current"] as? [String: Any],
            let tempF   = current["temperature_2m"] as? Double,
            let rh      = current["relative_humidity_2m"] as? Double
        else { throw WeatherError.missingData }

        let timestamp: Date = {
            if let timeStr = current["time"] as? String {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
                return fmt.date(from: timeStr) ?? Date()
            }
            return Date()
        }()

        return (
            ExposomeReading(factor: .temperature, numericValue: tempF,
                            displayValue: String(format: "%.1f°F", tempF), timestamp: timestamp),
            ExposomeReading(factor: .humidity, numericValue: rh,
                            displayValue: String(format: "%.0f%%", rh), timestamp: timestamp)
        )
    }

    enum WeatherError: LocalizedError {
        case missingData, httpError(Int)
        var errorDescription: String? {
            switch self {
            case .missingData:      return "Missing temperature or humidity data"
            case .httpError(let c): return "Weather service HTTP \(c)"
            }
        }
    }
}
