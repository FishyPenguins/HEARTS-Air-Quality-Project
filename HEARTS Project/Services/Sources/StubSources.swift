import CoreLocation
import Foundation

// Ambient Noise and Light Pollution have no confirmed free real-time public feed.
// They return nil so the dashboard shows "Not available".
// Green Space similarly has no simple free feed; swap in a real source when identified.

struct AmbientNoiseSource: ExposomeSource {
    var supportedFactors: [ExposomeFactor] { [.ambientNoise] }
    func fetch(for _: ExposomeFactor, at _: CLLocation) async throws -> ExposomeReading? { nil }
}

struct LightPollutionSource: ExposomeSource {
    var supportedFactors: [ExposomeFactor] { [.lightPollution] }
    func fetch(for _: ExposomeFactor, at _: CLLocation) async throws -> ExposomeReading? { nil }
}

struct GreenSpaceSource: ExposomeSource {
    var supportedFactors: [ExposomeFactor] { [.greenSpace] }
    func fetch(for _: ExposomeFactor, at _: CLLocation) async throws -> ExposomeReading? { nil }
}

/// Fetches grass pollen concentration from Open-Meteo Air Quality API (free, no key required).
/// Uses the CAMS global model — coverage is best in Europe but available worldwide.
struct PollenSource: ExposomeSource {
    var supportedFactors: [ExposomeFactor] { [.pollen] }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    func fetch(for factor: ExposomeFactor, at location: CLLocation) async throws -> ExposomeReading? {
        guard factor == .pollen else { return nil }

        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude",  value: String(format: "%.4f", location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", location.coordinate.longitude)),
            URLQueryItem(name: "current",   value: "grass_pollen"),
            URLQueryItem(name: "timezone",  value: "auto")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw PollenError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let current = json?["current"] as? [String: Any] else {
            throw PollenError.unexpectedResponse
        }

        // grass_pollen is null from the API when out of season or model has no data
        let rawValue = current["grass_pollen"]
        guard let grains = (rawValue as? Double) ?? (rawValue as? Int).map(Double.init),
              !(rawValue is NSNull) else {
            return nil
        }

        let timestamp: Date = {
            if let timeStr = current["time"] as? String {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
                return fmt.date(from: timeStr) ?? Date()
            }
            return Date()
        }()

        return ExposomeReading(
            factor: .pollen,
            numericValue: grains,
            displayValue: String(format: "%.1f grains/m³", grains),
            timestamp: timestamp
        )
    }

    enum PollenError: LocalizedError {
        case unexpectedResponse, httpError(Int)
        var errorDescription: String? {
            switch self {
            case .unexpectedResponse: return "Unexpected pollen response format"
            case .httpError(let c):   return "Pollen service HTTP \(c)"
            }
        }
    }
}
