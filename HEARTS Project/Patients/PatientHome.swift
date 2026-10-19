import CoreLocation
import Foundation

/// Where each practice patient lives, so HEARTS can show the air and weather in their home town.
/// Points are the approximate center of each zip code in HEARTS_fake_patients_v2.
/// "My info" has no entry here and keeps using the phone's GPS.
nonisolated enum PatientHome {
    private static let zipCenters: [String: (lat: Double, lon: Double)] = [
        "06039": (41.961, -73.437),  // Lakeville
        "06051": (41.664, -72.770),  // New Britain
        "06070": (41.874, -72.808),  // Simsbury
        "06084": (41.879, -72.367),  // Tolland
        "06106": (41.749, -72.693),  // Hartford
        "06120": (41.787, -72.670),  // Hartford North End
        "06259": (41.873, -71.986),  // Pomfret Center
        "06410": (41.506, -72.905),  // Cheshire
        "06443": (41.279, -72.599),  // Madison
        "06511": (41.315, -72.929),  // New Haven
        "06519": (41.294, -72.936),  // New Haven (The Hill)
        "06604": (41.178, -73.199),  // Bridgeport
        "06608": (41.187, -73.172),  // Bridgeport East
        "06706": (41.535, -73.021),  // Waterbury
        "06840": (41.147, -73.495),  // New Canaan
        "06883": (41.222, -73.373)   // Weston
    ]

    /// The patient's home as a location, or nil for "My info" and unknown zip codes.
    static func location(for patient: Patient) -> CLLocation? {
        guard !patient.isCustomProfile else { return nil }
        let zip = patient.zip.count == 4 ? "0" + patient.zip : patient.zip
        guard let point = zipCenters[zip] else { return nil }
        return CLLocation(latitude: point.lat, longitude: point.lon)
    }
}
