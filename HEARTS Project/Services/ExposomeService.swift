import CoreLocation
import Foundation
import Observation

@Observable
@MainActor
final class ExposomeService {
    var statuses: [ExposomeFactor: ExposomeStatus] = Dictionary(
        uniqueKeysWithValues: ExposomeFactor.allCases.map { ($0, .loading) }
    )

    private let noaa: NOAAWeatherSource
    private let airNow    = AirNowSource()
    private let heatIndex: HeatIndexSource
    private let noise     = AmbientNoiseSource()
    private let light     = LightPollutionSource()
    private let green     = GreenSpaceSource()
    private let pollen    = PollenSource()

    private var lastFetchKey: String?

    init() {
        noaa = NOAAWeatherSource()
        heatIndex = HeatIndexSource(weatherSource: noaa)
    }

    private var allSources: [(ExposomeFactor, any ExposomeSource)] {
        [
            (.temperature,    noaa),
            (.humidity,       noaa),
            (.pm25,           airNow),
            (.aqi,            airNow),
            (.heatIndex,      heatIndex),
            (.ambientNoise,   noise),
            (.lightPollution, light),
            (.greenSpace,     green),
            (.pollen,         pollen)
        ]
    }

    func refresh(location: CLLocation) async {
        let key = String(format: "%.2f,%.2f",
                         location.coordinate.latitude,
                         location.coordinate.longitude)
        guard key != lastFetchKey else { return }
        lastFetchKey = key

        // Reset to loading
        for factor in ExposomeFactor.allCases {
            statuses[factor] = .loading
        }

        // Capture snapshot before resetting, so error paths can reference the last-known value.
        let previousStatuses = statuses

        await withTaskGroup(of: (ExposomeFactor, ExposomeStatus).self) { group in
            for (factor, source) in allSources {
                group.addTask {
                    do {
                        if let reading = try await source.fetch(for: factor, at: location) {
                            return (factor, .available(reading))
                        } else {
                            return (factor, .notAvailable)
                        }
                    } catch {
                        let lastKnown: ExposomeReading?
                        if case .available(let r) = previousStatuses[factor] { lastKnown = r }
                        else { lastKnown = nil }
                        return (factor, .failed(error.localizedDescription, lastKnown: lastKnown))
                    }
                }
            }
            for await (factor, status) in group {
                // Drop late results from an older location (for example after switching patients quickly).
                guard lastFetchKey == key else { continue }
                statuses[factor] = status
            }
        }
    }

    func forceRefresh(location: CLLocation) async {
        lastFetchKey = nil
        await refresh(location: location)
    }
}
