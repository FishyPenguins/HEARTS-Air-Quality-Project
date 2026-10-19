import Foundation
import Observation

/// Holds the list of people the app can show and which one is active right now.
/// Switching the active person updates the risk card, the alerts and the chat.
@Observable
@MainActor
final class PatientStore {
    private(set) var builtIn: [Patient] = []
    private(set) var custom: Patient?
    private(set) var selectedID: String
    private(set) var loadError: String?

    private let defaults: UserDefaults
    private static let selectedKey = "hearts.selectedPatientID"
    private static let customKey = "hearts.customPatient"

    init(defaults: UserDefaults = .standard) {
        var loaded: [Patient] = []
        var failure: String?
        do {
            loaded = try PatientLoader.bundled()
        } catch {
            failure = error.localizedDescription
        }
        var saved: Patient?
        if let data = defaults.data(forKey: Self.customKey) {
            saved = try? JSONDecoder().decode(Patient.self, from: data)
        }
        self.defaults = defaults
        self.builtIn = loaded
        self.custom = saved
        self.loadError = failure
        // Default to Patient A so the demo always has someone selected.
        self.selectedID = defaults.string(forKey: Self.selectedKey) ?? loaded.first?.id ?? Patient.customID
    }

    var all: [Patient] { (custom.map { [$0] } ?? []) + builtIn }

    var selected: Patient? {
        all.first { $0.id == selectedID } ?? builtIn.first
    }

    func select(_ patient: Patient) {
        selectedID = patient.id
        defaults.set(patient.id, forKey: Self.selectedKey)
    }

    func saveCustom(_ patient: Patient) {
        var p = patient
        p.id = Patient.customID
        p.isCustom = true
        custom = p
        if let data = try? JSONEncoder().encode(p) {
            defaults.set(data, forKey: Self.customKey)
        }
        select(p)
    }

    func deleteCustom() {
        custom = nil
        defaults.removeObject(forKey: Self.customKey)
        if selectedID == Patient.customID, let first = builtIn.first { select(first) }
    }

    /// Next / previous person, for quick switching during a demo.
    func step(by offset: Int) {
        let list = all
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == selectedID } ?? 0
        select(list[(index + offset + list.count) % list.count])
    }
}
