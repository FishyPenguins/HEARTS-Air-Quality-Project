import CoreLocation
import Foundation

/// Fetches PM2.5 and AQI from the EPA AirNow API.
/// Get a free key at https://docs.airnowapi.org/
/// Replace the placeholder below with your key, or set AIRNOW_API_KEY in the scheme env vars.
final class AirNowSource: ExposomeSource {
    var supportedFactors: [ExposomeFactor] { [.pm25, .aqi] }

    // Read from environment first, then fall back to the compile-time placeholder.
    private var apiKey: String {
        ProcessInfo.processInfo.environment["AIRNOW_API_KEY"] ?? "0DD7E724-0180-4F2F-A15E-75F3DF511C30"
    }

    private var cache: [String: (pm25: ExposomeReading?, aqi: ExposomeReading?, date: Date)] = [:]
    private let cacheTTL: TimeInterval = 3600

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private func cacheKey(for location: CLLocation) -> String {
        String(format: "%.2f,%.2f", location.coordinate.latitude, location.coordinate.longitude)
    }

    func fetch(for factor: ExposomeFactor, at location: CLLocation) async throws -> ExposomeReading? {
        guard factor == .pm25 || factor == .aqi else { return nil }

        let key = cacheKey(for: location)
        if let cached = cache[key], Date().timeIntervalSince(cached.date) < cacheTTL {
            return factor == .pm25 ? cached.pm25 : cached.aqi
        }

        let (pm25, aqi) = try await fetchBoth(at: location)
        cache[key] = (pm25, aqi, Date())
        return factor == .pm25 ? pm25 : aqi
    }

    private func fetchBoth(at location: CLLocation) async throws -> (ExposomeReading?, ExposomeReading?) {
        guard apiKey != "YOUR_AIRNOW_API_KEY" else {
            throw AirNowError.noApiKey
        }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        var components = URLComponents(string: "https://www.airnowapi.org/aq/observation/latLong/current/")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "application/json"),
            URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", lon)),
            URLQueryItem(name: "distance", value: "25"),
            URLQueryItem(name: "API_KEY", value: apiKey)
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AirNowError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        guard let observations = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw AirNowError.unexpectedResponse
        }

        let now = Date()
        var pm25Reading: ExposomeReading?
        var aqiReading: ExposomeReading?

        for obs in observations {
            guard let paramName = obs["ParameterName"] as? String,
                  let aqiValue = obs["AQI"] as? Int else { continue }

            if paramName == "PM2.5" {
                pm25Reading = ExposomeReading(
                    factor: .pm25,
                    numericValue: Double(aqiValue),
                    displayValue: "\(aqiValue) µg/m³",
                    timestamp: now
                )
                aqiReading = ExposomeReading(
                    factor: .aqi,
                    numericValue: Double(aqiValue),
                    displayValue: aqiCategory(aqiValue),
                    timestamp: now
                )
            }
        }

        return (pm25Reading, aqiReading)
    }

    private func aqiCategory(_ aqi: Int) -> String {
        switch aqi {
        case 0...50:   return "\(aqi) — Good"
        case 51...100: return "\(aqi) — Moderate"
        case 101...150: return "\(aqi) — Unhealthy for Sensitive Groups"
        case 151...200: return "\(aqi) — Unhealthy"
        case 201...300: return "\(aqi) — Very Unhealthy"
        default:        return "\(aqi) — Hazardous"
        }
    }

    enum AirNowError: LocalizedError {
        case noApiKey, unexpectedResponse, httpError(Int)
        var errorDescription: String? {
            switch self {
            case .noApiKey:           return "AirNow API key not configured"
            case .unexpectedResponse: return "Unexpected AirNow response format"
            case .httpError(let c):   return "AirNow HTTP \(c)"
            }
        }
    }
}
