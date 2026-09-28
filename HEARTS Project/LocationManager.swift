import CoreLocation
import Foundation
import MapKit
import Observation

@Observable
@MainActor
final class LocationManager: NSObject {
    var location: CLLocation?
    var mapItem: MKMapItem?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var locationError: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            locationError = "Location access denied. Enable it in Settings."
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        guard let request = MKReverseGeocodingRequest(location: location) else { return }
        do {
            let mapItems: [MKMapItem] = try await withCheckedThrowingContinuation { continuation in
                request.getMapItems { items, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: items ?? []) }
                }
            }
            mapItem = mapItems.first
        } catch {
            // silently ignore geocoding errors
        }
    }

    var locationLabel: String {
        if let city = mapItem?.addressRepresentations?.cityName {
            return city
        } else if let location {
            let lat = String(format: "%.2f", location.coordinate.latitude)
            let lon = String(format: "%.2f", location.coordinate.longitude)
            return "\(lat), \(lon)"
        }
        return "Locating…"
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.location = loc
            self.locationError = nil
            self.mapItem = nil
            await self.reverseGeocode(loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationError = error.localizedDescription
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse ||
               manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }
}
