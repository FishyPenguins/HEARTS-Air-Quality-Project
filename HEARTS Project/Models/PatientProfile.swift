import Foundation

// Basic patient info we send to the agent with each question.
// Only fake/demo patients for now until we have a HIPAA-safe setup.
struct PatientProfile: Codable {
    var condition: String
    var ageRange: String?
    var takesWaterPills: Bool
    var notes: String?

    static let demo = PatientProfile(
        condition: "heart failure",
        ageRange: "65-74",
        takesWaterPills: true,
        notes: "Demo patient (not a real person)"
    )
}
