import Foundation
import Observation
import UserNotifications

/// A heads-up for the selected person when today's air or heat is risky for them.
nonisolated struct RiskAlert: Equatable, Sendable, Identifiable {
    enum Severity: Int, Sendable { case watch = 1, warning = 2 }

    let id: String          // stable per reason, used so each alert only notifies once a day
    let severity: Severity
    let title: String
    let message: String
    let symbol: String
}

/// Decides when to warn the selected person, shows a banner on the map, and sends a phone
/// notification at most once per person, per reason, per day.
@Observable
@MainActor
final class RiskAlertManager {
    private(set) var alerts: [RiskAlert] = []

    private let defaults: UserDefaults
    private static let sentKey = "hearts.sentAlerts"
    private var askedPermission = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var top: RiskAlert? { alerts.max { $0.severity.rawValue < $1.severity.rawValue } }

    /// Pure rules, so they are easy to test and reuse.
    nonisolated static func alerts(for patient: Patient, risk: RiskAssessment) -> [RiskAlert] {
        var list: [RiskAlert] = []
        let c = risk.conditions
        let possessive = patient.isCustomProfile ? "your" : "their"

        if let aqi = c.aqi, aqi > 100 {
            let severe = aqi > 150
            list.append(RiskAlert(
                id: "aqi",
                severity: severe ? .warning : .watch,
                title: severe ? "Unhealthy air today (AQI \(aqi))" : "Air is bad for heart conditions (AQI \(aqi))",
                message: "With heart failure, stay inside with windows closed and skip hard activity outside. "
                    + "Today's air raises \(possessive) risk by about \(Int(risk.environmentChangePercent.rounded()))%.",
                symbol: "aqi.high"))
        }
        if let hi = c.heatIndexF, hi >= 90 {
            list.append(RiskAlert(
                id: "heat",
                severity: hi >= 103 ? .warning : .watch,
                title: "Heat alert: feels like \(Int(hi.rounded()))°F",
                message: patient.takesDiuretic
                    ? "Water pills make heat harder on the body. Stay cool, and ask the care team how much to drink."
                    : "Stay in the AC during the hottest part of the day and watch for dizziness or swelling.",
                symbol: "sun.max.trianglebadge.exclamationmark.fill"))
        }
        if let t = c.temperatureF, t <= 32 {
            list.append(RiskAlert(
                id: "cold",
                severity: .watch,
                title: "Cold snap: \(Int(t.rounded()))°F",
                message: "Cold raises heart failure risk 3 to 5 days later. Skip shoveling and watch weight and swelling this week.",
                symbol: "snowflake"))
        }
        if risk.levelIndex >= 3 {
            list.append(RiskAlert(
                id: "risk-high",
                severity: .warning,
                title: "\(risk.levelName) risk this week (\(risk.percentText))",
                message: "Check weight every morning. A gain of 2 to 3 pounds in a day or 5 in a week means call the care team.",
                symbol: "heart.text.square.fill"))
        }
        return list
    }

    func update(patient: Patient?, risk: RiskAssessment?, notify: Bool) {
        guard let patient, let risk else {
            alerts = []
            return
        }
        alerts = Self.alerts(for: patient, risk: risk)
        guard notify, let alert = top, alert.severity == .warning else { return }
        Task { await sendOncePerDay(alert, patient: patient) }
    }

    private func sendOncePerDay(_ alert: RiskAlert, patient: Patient) async {
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let key = "\(day)|\(patient.id)|\(alert.id)"
        var sent = defaults.stringArray(forKey: Self.sentKey) ?? []
        guard !sent.contains(key) else { return }

        let center = UNUserNotificationCenter.current()
        if !askedPermission {
            askedPermission = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "HEARTS: " + alert.title
        content.body = alert.message
        content.sound = .default
        let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
        try? await center.add(request)

        sent.append(key)
        defaults.set(Array(sent.suffix(50)), forKey: Self.sentKey)
    }
}
