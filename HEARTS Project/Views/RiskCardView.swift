import SwiftUI

/// The card on the map: who is selected, their risk this week, and any air or heat alert.
struct RiskCardView: View {
    let patient: Patient
    let risk: RiskAssessment?
    let alert: RiskAlert?
    let isSimulated: Bool
    let onSwitchPatient: () -> Void
    let onOpenDetails: () -> Void
    let onStep: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let alert { alertBanner(alert) }
            content
        }
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(RiskStyle.color(level: risk?.levelIndex ?? 0).opacity(0.45), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        .animation(.snappy, value: patient.id)
        .animation(.snappy, value: risk?.currentRisk)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { onStep(-1) } label: {
                    Image(systemName: "chevron.left").font(.caption.weight(.bold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Previous patient")

                Button(action: onSwitchPatient) {
                    HStack(spacing: 10) {
                        PatientAvatar(patient: patient, level: risk?.levelIndex, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(patient.displayName).font(.subheadline.weight(.bold))
                                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(patient.summaryLine).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Button { onStep(1) } label: {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Next patient")

                Spacer()
                if let risk { RiskPill(risk: risk) }
            }

            if let risk {
                Button(action: onOpenDetails) { riskBody(risk) }
                    .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Scoring risk…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }

    private func riskBody(_ risk: RiskAssessment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(risk.percentText)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(RiskStyle.color(level: risk.levelIndex))
                        .contentTransition(.numericText())
                    Text("chance of a heart failure hospital stay in the next \(risk.horizonDays) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                RiskMeter(level: risk.levelIndex)
                HStack(spacing: 6) {
                    Image(systemName: risk.environmentChangePercent >= 0.5 ? "arrow.up.right" : "checkmark.circle")
                        .font(.caption.weight(.bold))
                    Text(environmentLine(risk))
                        .font(.caption.weight(.medium))
                    Spacer()
                    if isSimulated {
                        Label("What-if", systemImage: "slider.horizontal.3")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RiskStyle.purple.opacity(0.15), in: Capsule())
                    }
                    Text("Details").font(.caption.weight(.semibold)).foregroundStyle(RiskStyle.purple)
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(RiskStyle.purple)
                }
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func environmentLine(_ risk: RiskAssessment) -> String {
        let change = Int(risk.environmentChangePercent.rounded())
        if change >= 1 {
            let causes = risk.environmentDrivers.map { driver -> String in
                switch driver.kind {
                case .air: return "air"
                case .heat: return "heat"
                case .cold: return "cold"
                case .chart: return ""
                }
            }.filter { !$0.isEmpty }
            return "Today's \(causes.isEmpty ? "conditions" : causes.joined(separator: " + ")) add +\(change)%"
        }
        return "Today's air and heat aren't adding risk"
    }

    private func alertBanner(_ alert: RiskAlert) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: alert.symbol)
                .font(.title3)
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: .repeating)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                Text(alert.message).font(.caption).foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            LinearGradient(colors: alert.severity == .warning ? [.red, .orange] : [.orange, .yellow],
                           startPoint: .leading, endPoint: .trailing),
            in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 0,
                                       bottomTrailingRadius: 0, topTrailingRadius: 22)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
