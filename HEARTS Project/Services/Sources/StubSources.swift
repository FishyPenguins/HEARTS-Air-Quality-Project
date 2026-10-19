import CoreLocation
import Foundation

// Light Pollution has no confirmed free real-time public feed.
// It returns nil so the dashboard shows "Not available".

/// Estimates ambient noise from nearby road density via OpenStreetMap Overpass API.
/// Counts motorway/trunk/primary/secondary roads within 500 m and maps the result
/// to an estimated dB level. No API key required.
struct AmbientNoiseSource: ExposomeSource {
    var supportedFactors: [ExposomeFactor] { [.ambientNoise] }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    func fetch(for factor: ExposomeFactor, at location: CLLocation) async throws -> ExposomeReading? {
        guard factor == .ambientNoise else { return nil }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let query = """
        [out:json][timeout:15];
        (
          way["highway"~"motorway|trunk|primary|secondary"](around:500,\(lat),\(lon));
        );
        out count;
        """

        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var formComponents = URLComponents()
        formComponents.queryItems = [URLQueryItem(name: "data", value: query)]
        request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NoiseError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]],
              let tags = elements.first?["tags"] as? [String: String],
              let totalStr = tags["total"],
              let total = Int(totalStr) else {
            throw NoiseError.unexpectedResponse
        }

        let db = estimatedDecibels(roadCount: total)
        return ExposomeReading(
            factor: .ambientNoise,
            numericValue: db,
            displayValue: String(format: "~%.0f dB (est.)", db),
            timestamp: Date()
        )
    }

    // Maps major-road count within 500 m to an estimated ambient noise level in dB.
    private func estimatedDecibels(roadCount count: Int) -> Double {
        switch count {
        case 0:       return 38   // rural/quiet residential
        case 1...2:   return 48   // quiet suburban
        case 3...5:   return 55   // suburban
        case 6...10:  return 62   // urban
        default:      return min(72, 62 + Double(count - 10) * 0.5)
        }
    }

    enum NoiseError: LocalizedError {
        case unexpectedResponse, httpError(Int)
        var errorDescription: String? {
            switch self {
            case .unexpectedResponse: return "Unexpected noise response"
            case .httpError(let c):   return "Noise service HTTP \(c)"
            }
        }
    }
}

struct LightPollutionSource: ExposomeSource {
    var supportedFactors: [ExposomeFactor] { [.lightPollution] }
    func fetch(for _: ExposomeFactor, at _: CLLocation) async throws -> ExposomeReading? { nil }
}

/// Estimates nearby green space using OpenStreetMap via the Overpass API (free, no key required).
/// Counts parks, forests, gardens, and natural green areas within 1 km and maps the result
/// to a rough coverage percentage shown on the dashboard.
struct GreenSpaceSource: ExposomeSource {
    var supportedFactors: [ExposomeFactor] { [.greenSpace] }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    func fetch(for factor: ExposomeFactor, at location: CLLocation) async throws -> ExposomeReading? {
        guard factor == .greenSpace else { return nil }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let query = """
        [out:json][timeout:15];
        (
          way["leisure"~"park|garden|nature_reserve|recreation_ground"](around:1000,\(lat),\(lon));
          way["landuse"~"grass|forest|meadow|village_green|allotments"](around:1000,\(lat),\(lon));
          way["natural"~"wood|grassland|scrub|heath"](around:1000,\(lat),\(lon));
        );
        out count;
        """

        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var formComponents = URLComponents()
        formComponents.queryItems = [URLQueryItem(name: "data", value: query)]
        request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GreenSpaceError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]],
              let tags = elements.first?["tags"] as? [String: String],
              let totalStr = tags["total"],
              let total = Int(totalStr) else {
            throw GreenSpaceError.unexpectedResponse
        }

        let pct = coveragePercent(featureCount: total)
        return ExposomeReading(
            factor: .greenSpace,
            numericValue: pct,
            displayValue: String(format: "~%.0f%%", pct),
            timestamp: Date()
        )
    }

    // Maps OSM green feature count within 1 km to an estimated coverage %.
    private func coveragePercent(featureCount n: Int) -> Double {
        switch n {
        case 0:       return 0
        case 1...2:   return 10
        case 3...5:   return 25
        case 6...10:  return 45
        case 11...20: return 65
        default:      return min(85, Double(n) * 2.0)
        }
    }

    enum GreenSpaceError: LocalizedError {
        case unexpectedResponse, httpError(Int)
        var errorDescription: String? {
            switch self {
            case .unexpectedResponse: return "Unexpected green space response"
            case .httpError(let c):   return "Green space service HTTP \(c)"
            }
        }
    }
}

/// Fetches grass pollen concentration from Open-Meteo Air Quality API (free, no key required).
/// Uses the CAMS global model — data is most reliable in Europe; US coverage is limited
/// and returns nil when out of season or when the model has no data for the area.
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
