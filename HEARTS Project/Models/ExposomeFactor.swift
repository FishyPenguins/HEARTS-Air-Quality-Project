import Foundation
import SwiftUI

enum ExposomeFactor: String, CaseIterable, Identifiable {
    case temperature    = "Temperature"
    case humidity       = "Humidity"
    case pm25           = "PM2.5"
    case aqi            = "Air Quality Index"
    case heatIndex      = "Heat Index"
    case ambientNoise   = "Ambient Noise"
    case lightPollution = "Light Pollution"
    case greenSpace     = "Green Space"
    case pollen         = "Pollen Count"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .temperature:    return "°F"
        case .humidity:       return "%"
        case .pm25:           return "µg/m³"
        case .aqi:            return ""
        case .heatIndex:      return "°F"
        case .ambientNoise:   return "dB"
        case .lightPollution: return "mag/arcsec²"
        case .greenSpace:     return "%"
        case .pollen:         return "grains/m³"
        }
    }

    var symbolName: String {
        switch self {
        case .temperature:    return "thermometer.medium"
        case .humidity:       return "humidity"
        case .pm25:           return "aqi.medium"
        case .aqi:            return "aqi.high"
        case .heatIndex:      return "sun.max.fill"
        case .ambientNoise:   return "ear"
        case .lightPollution: return "moon.stars.fill"
        case .greenSpace:     return "leaf.fill"
        case .pollen:         return "allergens"
        }
    }

    var sourceName: String {
        switch self {
        case .temperature, .humidity: return "Open-Meteo"
        case .pm25, .aqi:             return "Open-Meteo"
        case .heatIndex:              return "Derived"
        case .ambientNoise:           return "—"
        case .lightPollution:         return "—"
        case .greenSpace:             return "—"
        case .pollen:                 return "—"
        }
    }

    var color: Color {
        switch self {
        case .temperature:    return .orange
        case .humidity:       return .blue
        case .pm25:           return .purple
        case .aqi:            return .teal
        case .heatIndex:      return .red
        case .ambientNoise:   return .yellow
        case .lightPollution: return .indigo
        case .greenSpace:     return .green
        case .pollen:         return .brown
        }
    }

    var shortName: String {
        switch self {
        case .temperature:    return "Temperature"
        case .humidity:       return "Humidity"
        case .pm25:           return "PM2.5"
        case .aqi:            return "Air Quality"
        case .heatIndex:      return "Heat Index"
        case .ambientNoise:   return "Noise"
        case .lightPollution: return "Light"
        case .greenSpace:     return "Green Space"
        case .pollen:         return "Pollen"
        }
    }

    var factorDescription: String {
        switch self {
        case .temperature:
            return "Ambient air temperature measured at your current location."
        case .humidity:
            return "Relative humidity indicating the amount of moisture in the air."
        case .pm25:
            return "Concentration of fine particulate matter smaller than 2.5 micrometers."
        case .aqi:
            return "Composite index summarizing overall air quality conditions."
        case .heatIndex:
            return "Perceived temperature combining actual heat and relative humidity."
        case .ambientNoise:
            return "Background sound level in your surrounding environment."
        case .lightPollution:
            return "Brightness of the artificial night sky in your area."
        case .greenSpace:
            return "Percentage of nearby land covered by vegetation and green areas."
        case .pollen:
            return "Concentration of airborne pollen grains in the atmosphere."
        }
    }
}

struct ExposomeReading {
    let factor: ExposomeFactor
    let numericValue: Double
    let displayValue: String
    let timestamp: Date

    var isStale: Bool {
        Date().timeIntervalSince(timestamp) > 3600
    }

    var ageString: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "just now" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(interval / 3600)
        return "\(hours)h ago"
    }
}

enum ExposomeStatus {
    case loading
    case available(ExposomeReading)
    case notAvailable
    case failed(String, lastKnown: ExposomeReading?)
}
