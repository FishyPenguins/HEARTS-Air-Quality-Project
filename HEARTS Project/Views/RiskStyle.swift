import SwiftUI

/// Colors and small pieces shared by the risk card, the detail screen and the patient list.
enum RiskStyle {
    static let purple = Color(red: 0.45, green: 0.18, blue: 0.92)
    static let blue = Color(red: 0.15, green: 0.47, blue: 1.0)

    static func color(level: Int) -> Color {
        switch level {
        case 0: return .green
        case 1: return .yellow
        case 2: return .orange
        default: return .red
        }
    }

    static func gradient(level: Int) -> LinearGradient {
        let c = color(level: level)
        return LinearGradient(colors: [c.opacity(0.85), c], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func symbol(for kind: RiskAssessment.DriverKind) -> String {
        switch kind {
        case .chart: return "stethoscope"
        case .air: return "aqi.medium"
        case .heat: return "thermometer.sun.fill"
        case .cold: return "snowflake"
        }
    }
}

/// Round avatar with the patient's letter(s), ringed in their risk color.
struct PatientAvatar: View {
    let patient: Patient
    var level: Int?
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [RiskStyle.blue, RiskStyle.purple],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if patient.isCustomProfile {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text(patient.badge)
                    .font(.system(size: size * (patient.badge.count > 1 ? 0.36 : 0.45), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if let level {
                Circle().strokeBorder(RiskStyle.color(level: level), lineWidth: 3)
                    .padding(-3)
            }
        }
    }
}

/// "High · 24%" pill.
struct RiskPill: View {
    let risk: RiskAssessment

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(RiskStyle.color(level: risk.levelIndex)).frame(width: 7, height: 7)
            Text(risk.levelName)
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RiskStyle.color(level: risk.levelIndex).opacity(0.18), in: Capsule())
    }
}

/// Four-segment meter: Low, Moderate, Elevated, High.
struct RiskMeter: View {
    let level: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(i <= level ? RiskStyle.color(level: i) : Color.secondary.opacity(0.2))
                    .frame(height: 6)
            }
        }
    }
}
