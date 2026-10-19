import CoreLocation
import Foundation

/// Fetches PM2.5 and US AQI from Open-Meteo Air Quality API (free, no key required).
final class AirNowSource: ExposomeSource {
    var supportedFactors: [ExposomeFactor] { [.pm25, .aqi] }

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
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude",  value: String(format: "%.4f", location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", location.coordinate.longitude)),
            URLQueryItem(name: "current",   value: "pm2_5,us_aqi"),
            URLQueryItem(name: "timezone",  value: "auto")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AirQualityError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let current = json?["current"] as? [String: Any] else {
            throw AirQualityError.unexpectedResponse
        }

        let timestamp: Date = {
            if let timeStr = current["time"] as? String {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
                return fmt.date(from: timeStr) ?? Date()
            }
            return Date()
        }()

        let pm25Reading: ExposomeReading? = {
            let raw = current["pm2_5"]
            guard let value = (raw as? Double) ?? (raw as? Int).map(Double.init),
                  !(raw is NSNull) else { return nil }
            return ExposomeReading(
                factor: .pm25,
                numericValue: value,
                displayValue: String(format: "%.1f µg/m³", value),
                timestamp: timestamp
            )
        }()

        let aqiReading: ExposomeReading? = {
            let raw = current["us_aqi"]
            guard let value = (raw as? Double) ?? (raw as? Int).map(Double.init),
                  !(raw is NSNull) else { return nil }
            return ExposomeReading(
                factor: .aqi,
                numericValue: value,
                displayValue: aqiCategory(Int(value)),
                timestamp: timestamp
            )
        }()

        return (pm25Reading, aqiReading)
    }

    private func aqiCategory(_ aqi: Int) -> String {
        switch aqi {
        case 0...50:    return "\(aqi) — Good"
        case 51...100:  return "\(aqi) — Moderate"
        case 101...150: return "\(aqi) — Unhealthy for Sensitive Groups"
        case 151...200: return "\(aqi) — Unhealthy"
        case 201...300: return "\(aqi) — Very Unhealthy"
        default:        return "\(aqi) — Hazardous"
        }
    }

    enum AirQualityError: LocalizedError {
        case unexpectedResponse, httpError(Int)
        var errorDescription: String? {
            switch self {
            case .unexpectedResponse: return "Unexpected air quality response format"
            case .httpError(let c):   return "Air quality service HTTP \(c)"
            }
        }
    }
}
