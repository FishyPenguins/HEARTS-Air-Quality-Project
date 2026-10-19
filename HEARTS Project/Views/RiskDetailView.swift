import SwiftUI

/// Full risk breakdown for the selected person, with a what-if simulator for demos
/// ("what if it were a smoke day?") and quick switching between people.
struct RiskDetailView: View {
    let model: RiskModel
    let store: PatientStore
    let liveConditions: RiskConditions
    @Binding var whatIf: RiskConditions?
    let onAskHEARTS: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false

    private var conditions: RiskConditions { whatIf ?? liveConditions }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let patient = store.selected {
                    let risk = model.assess(patient, conditions: conditions)
                    VStack(spacing: 16) {
                        header(patient, risk: risk)
                        gaugeCard(risk)
                        driversCard(risk)
                        whatIfCard
                        chartCard(patient)
                        modelCard
                    }
                    .padding(16)
                    .animation(.snappy, value: patient.id)
                    .animation(.snappy, value: conditions)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Heart Risk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPicker = true } label: { Image(systemName: "person.2.fill") }
                        .accessibilityLabel("Switch patient")
                }
            }
            .sheet(isPresented: $showPicker) {
                PatientPickerView(store: store, model: model, conditions: conditions)
            }
        }
    }

    // MARK: - Cards

    private func header(_ patient: Patient, risk: RiskAssessment) -> some View {
        HStack(spacing: 12) {
            Button { store.step(by: -1) } label: { Image(systemName: "chevron.left.circle.fill").font(.title2) }
                .accessibilityLabel("Previous patient")
            PatientAvatar(patient: patient, level: risk.levelIndex, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(patient.displayName).font(.title3.weight(.bold))
                Text(patient.summaryLine).font(.subheadline).foregroundStyle(.secondary)
                Text(patient.livesInPollutedArea ? "Polluted / disadvantaged area" : "Cleaner area")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(patient.livesInPollutedArea ? .orange : .green)
            }
            Spacer()
            Button { store.step(by: 1) } label: { Image(systemName: "chevron.right.circle.fill").font(.title2) }
                .accessibilityLabel("Next patient")
        }
        .foregroundStyle(RiskStyle.purple)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func gaugeCard(_ risk: RiskAssessment) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: min(risk.currentRisk / 0.30, 1))
                        .stroke(RiskStyle.gradient(level: risk.levelIndex),
                                style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(risk.percentText)
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .contentTransition(.numericText())
                        Text("next \(risk.horizonDays) days").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 130, height: 130)

                VStack(alignment: .leading, spacing: 10) {
                    RiskPill(risk: risk)
                    compareRow("Clean, mild day", value: risk.baselineRisk, level: risk.levelIndex, faded: true)
                    compareRow(whatIf == nil ? "With today's air and heat" : "With what-if conditions",
                               value: risk.currentRisk, level: risk.levelIndex, faded: false)
                }
            }
            RiskMeter(level: risk.levelIndex)
            Text(summarySentence(risk))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func compareRow(_ title: String, value: Double, level: Int, faded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                GeometryReader { geo in
                    Capsule()
                        .fill(faded ? Color.secondary.opacity(0.35) : RiskStyle.color(level: level))
                        .frame(width: max(6, geo.size.width * min(value / 0.30, 1)))
                }
                .frame(height: 8)
                Text(RiskAssessment.percent(value)).font(.caption.weight(.bold)).monospacedDigit()
            }
        }
    }

    private func summarySentence(_ risk: RiskAssessment) -> String {
        let change = Int(risk.environmentChangePercent.rounded())
        let base = "\(risk.levelName) risk."
        if change >= 1 {
            return base + " Today's conditions raise it about \(change)% over a clean, mild day."
        }
        return base + " Today's air and heat aren't adding to it."
    }

    private func driversCard(_ risk: RiskAssessment) -> some View {
        let maxImpact = max((risk.raising + risk.lowering).map { abs($0.impact) }.max() ?? 1, 0.01)
        return VStack(alignment: .leading, spacing: 12) {
            Text("What's raising risk").font(.headline)
            if risk.raising.isEmpty {
                Text("Nothing stands out.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(risk.raising.prefix(6)) { driver in
                driverRow(driver, maxImpact: maxImpact, tint: driver.kind == .chart ? .orange : .red)
            }
            if !risk.lowering.isEmpty {
                Divider()
                Text("What's helping").font(.headline)
                ForEach(risk.lowering.prefix(4)) { driver in
                    driverRow(driver, maxImpact: maxImpact, tint: .green)
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func driverRow(_ driver: RiskAssessment.Driver, maxImpact: Double, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: RiskStyle.symbol(for: driver.kind))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(driver.label).font(.subheadline)
                GeometryReader { geo in
                    Capsule().fill(tint.opacity(0.75))
                        .frame(width: max(6, geo.size.width * abs(driver.impact) / maxImpact))
                }
                .frame(height: 5)
            }
        }
    }

    private var whatIfCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("What if…", systemImage: "slider.horizontal.3").font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { whatIf != nil },
                    set: { on in whatIf = on ? liveConditionsOrDefault : nil }
                ))
                .labelsHidden()
            }
            Text("Try different air and heat to see how this person's risk changes. The map card follows along until you turn this off.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    preset("Clean day", "leaf.fill", RiskConditions(aqi: 20, heatIndexF: 70, temperatureF: 70))
                    preset("Smoke day", "smoke.fill", RiskConditions(aqi: 180, heatIndexF: 78, temperatureF: 78))
                    preset("Heat wave", "sun.max.fill", RiskConditions(aqi: 85, heatIndexF: 104, temperatureF: 95))
                    preset("Cold snap", "snowflake", RiskConditions(aqi: 30, heatIndexF: 15, temperatureF: 15))
                }
            }

            if let current = whatIf {
                sliderRow(title: "AQI", value: "\(current.aqi ?? 0) · \(AQI.category(current.aqi ?? 0))",
                          binding: Binding(
                            get: { Double(current.aqi ?? 0) },
                            set: { v in
                                whatIf = RiskConditions(aqi: Int(v), heatIndexF: current.heatIndexF,
                                                        temperatureF: current.temperatureF)
                            }),
                          range: 0...300, step: 5)
                sliderRow(title: "Feels like", value: "\(Int((current.heatIndexF ?? 70).rounded()))°F",
                          binding: Binding(
                            get: { current.heatIndexF ?? 70 },
                            set: { v in
                                whatIf = RiskConditions(aqi: current.aqi, heatIndexF: v, temperatureF: v)
                            }),
                          range: 0...115, step: 1)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private var liveConditionsOrDefault: RiskConditions {
        RiskConditions(aqi: liveConditions.aqi ?? 40,
                       heatIndexF: liveConditions.heatIndexF ?? 70,
                       temperatureF: liveConditions.temperatureF ?? 70)
    }

    private func preset(_ title: String, _ symbol: String, _ value: RiskConditions) -> some View {
        Button {
            whatIf = value
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(whatIf == value ? RiskStyle.purple : RiskStyle.purple.opacity(0.12), in: Capsule())
                .foregroundStyle(whatIf == value ? .white : RiskStyle.purple)
        }
        .buttonStyle(.plain)
    }

    private func sliderRow(title: String, value: String, binding: Binding<Double>,
                           range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(value).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: binding, in: range, step: step).tint(RiskStyle.purple)
        }
    }

    private func chartCard(_ p: Patient) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("From the chart").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                fact("NYHA", "\(p.nyhaClass)")
                fact("EF", "\(p.ejectionFraction)%")
                fact("NT-proBNP", "\(Int(p.ntProBNP))")
                fact("Past stays", "\(p.priorHFHospitalizations)")
                fact("Sodium", "\(Int(p.sodium))")
                fact("O₂ sat", "\(p.o2Saturation)%")
            }
            if !p.conditions.isEmpty {
                Text(p.conditions.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            if !p.medications.isEmpty {
                Text("Meds: " + p.medications.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                dismiss()
                onAskHEARTS()
            } label: {
                Label("Ask HEARTS about this", systemImage: "bubble.left.and.text.bubble.right.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(LinearGradient(colors: [RiskStyle.blue, RiskStyle.purple],
                                               startPoint: .leading, endPoint: .trailing),
                                in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.weight(.bold)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("About this score", systemImage: "info.circle").font(.subheadline.weight(.bold))
            Text("Logistic regression trained on \(model.trainedOn). It ranks risk with an AUC of \(String(format: "%.2f", model.metrics.crossValidatedAUC)) on fake patients it never saw. Air and heat effects come from published studies (PM2.5: Chen et al. 2023). \(model.disclaimer)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }
}
