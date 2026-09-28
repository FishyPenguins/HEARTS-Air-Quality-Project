import CoreLocation
import Foundation

/// Every data source conforms to this protocol.
/// Stub sources return `.notAvailable`; real sources fetch and decode.
protocol ExposomeSource {
    /// Which factor(s) this source can provide. Usually one, sometimes several (e.g., NOAA gives temp + humidity).
    var supportedFactors: [ExposomeFactor] { get }

    /// Fetch the latest reading for the given location.
    /// Returns nil if the source produces nothing for a given factor.
    func fetch(for factor: ExposomeFactor, at location: CLLocation) async throws -> ExposomeReading?
}

/// A source that always reports not-available (placeholder for future real sources).
struct StubExposomeSource: ExposomeSource {
    let factor: ExposomeFactor
    var supportedFactors: [ExposomeFactor] { [factor] }

    func fetch(for _: ExposomeFactor, at _: CLLocation) async throws -> ExposomeReading? {
        return nil
    }
}
