import SwiftUI

/// Pick which person HEARTS is tailored to: one of the 38 fake practice patients, or "My info".
struct PatientPickerView: View {
    let store: PatientStore
    let model: RiskModel?
    let conditions: RiskConditions

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var sort: Sort = .risk
    @State private var editingCustom: Patient?

    enum Sort: String, CaseIterable, Identifiable {
        case risk = "Highest risk"
        case name = "Patient letter"
        case age = "Age"
        var id: String { rawValue }
    }

    private func risk(_ p: Patient) -> RiskAssessment? { model?.assess(p, conditions: conditions) }

    private var filtered: [Patient] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let list = store.builtIn.filter { p in
            q.isEmpty || p.id.lowercased() == q || p.town.lowercased().contains(q)
                || p.conditions.joined(separator: " ").lowercased().contains(q)
        }
        switch sort {
        case .risk: return list.sorted { (risk($0)?.currentRisk ?? 0) > (risk($1)?.currentRisk ?? 0) }
        case .name: return list.sorted { ($0.id.count, $0.id) < ($1.id.count, $1.id) }
        case .age: return list.sorted { $0.age > $1.age }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let me = store.custom {
                        row(me)
                            .swipeActions {
                                Button(role: .destructive) { store.deleteCustom() } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button { editingCustom = me } label: { Label("Edit", systemImage: "pencil") }
                            }
                    }
                    Button {
                        editingCustom = store.custom ?? Patient.customTemplate
                    } label: {
                        Label(store.custom == nil ? "Enter my own info" : "Edit my info",
                              systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                    }
                } header: {
                    Text("You")
                } footer: {
                    Text("Your info stays on this phone.")
                }

                Section {
                    ForEach(filtered) { row($0) }
                } header: {
                    Text("Practice patients (\(store.builtIn.count), fake data)")
                } footer: {
                    Text("From HEARTS_fake_patients_v2. Risk uses \(conditionsLabel).")
                }
            }
            .searchable(text: $search, prompt: "Patient letter, town or condition")
            .navigationTitle("Who is HEARTS for?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            .sheet(item: $editingCustom) { draft in
                CustomPatientForm(draft: draft) { saved in
                    store.saveCustom(saved)
                    dismiss()
                }
            }
        }
    }

    private var conditionsLabel: String {
        var parts: [String] = []
        if let aqi = conditions.aqi { parts.append("AQI \(aqi)") }
        if let hi = conditions.heatIndexF { parts.append("feels like \(Int(hi.rounded()))°F") }
        return parts.isEmpty ? "a clean, mild day" : parts.joined(separator: ", ")
    }

    private func row(_ p: Patient) -> some View {
        let r = risk(p)
        return Button {
            store.select(p)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                PatientAvatar(patient: p, level: r?.levelIndex, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.displayName).font(.subheadline.weight(.bold))
                    Text(p.summaryLine).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        chip("NYHA \(p.nyhaClass)")
                        chip("EF \(p.ejectionFraction)%")
                        if p.livesInPollutedArea { chip("Polluted area", tint: .orange) }
                    }
                }
                Spacer()
                if let r {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(r.percentText)
                            .font(.subheadline.weight(.heavy)).monospacedDigit()
                            .foregroundStyle(RiskStyle.color(level: r.levelIndex))
                        Text(r.levelName).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if p.id == store.selectedID {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(RiskStyle.purple)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chip(_ text: String, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint == .secondary ? Color.primary : tint)
    }
}

/// "Enter my own info" form, so anyone can use HEARTS (the course professor's ask).
struct CustomPatientForm: View {
    @State var draft: Patient
    let onSave: (Patient) -> Void
    @Environment(\.dismiss) private var dismiss

    private let genders = ["Female", "Male", "Other"]
    private let employment = ["Employed full-time", "Employed part-time", "Retired", "Disabled", "Unemployed"]

    var body: some View {
        NavigationStack {
            Form {
                Section("About you") {
                    Stepper("Age: \(draft.age)", value: $draft.age, in: 18...105)
                    Picker("Gender", selection: $draft.gender) {
                        ForEach(genders, id: \.self) { Text($0) }
                    }
                    TextField("Town", text: $draft.town)
                    Picker("Work", selection: $draft.employment) {
                        ForEach(employment, id: \.self) { Text($0) }
                    }
                    Toggle("I live in a polluted area", isOn: Binding(
                        get: { draft.livesInPollutedArea },
                        set: { draft.areaType = $0 ? "Polluted/disadvantaged" : "Clean" }))
                }

                Section {
                    Picker("NYHA class", selection: $draft.nyhaClass) {
                        Text("1 · no limits").tag(1)
                        Text("2 · tired with normal activity").tag(2)
                        Text("3 · tired with light activity").tag(3)
                        Text("4 · symptoms at rest").tag(4)
                    }
                    Stepper("Ejection fraction: \(draft.ejectionFraction)%", value: $draft.ejectionFraction, in: 10...75, step: 5)
                    Stepper("Hospital stays for heart failure: \(draft.priorHFHospitalizations)",
                            value: $draft.priorHFHospitalizations, in: 0...10)
                    HStack {
                        Text("NT-proBNP")
                        Spacer()
                        TextField("pg/mL", value: $draft.ntProBNP, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    HStack {
                        Text("Sodium")
                        Spacer()
                        TextField("mEq/L", value: $draft.sodium, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                } header: {
                    Text("Heart")
                } footer: {
                    Text("Ask your care team if you don't know these. Leave the defaults if you're not sure.")
                }

                Section("Other conditions") {
                    yesNoToggle("Diabetes", \.diabetes)
                    yesNoToggle("High blood pressure", \.hypertension)
                    yesNoToggle("Kidney disease", \.ckd)
                    yesNoToggle("COPD", \.copd)
                    Toggle("Home oxygen", isOn: Binding(
                        get: { draft.homeOxygenL > 0 },
                        set: { draft.homeOxygenL = $0 ? 2 : 0 }))
                }

                Section("Medicines") {
                    yesNoToggle("Water pill (diuretic)", \.onDiuretics)
                    yesNoToggle("Beta blocker", \.onBetaBlockers)
                    yesNoToggle("SGLT2 inhibitor (like Jardiance or Farxiga)", \.onSGLT2)
                }
            }
            .navigationTitle("My info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if draft.town.trimmingCharacters(in: .whitespaces).isEmpty { draft.town = "My town" }
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    private func yesNoToggle(_ title: String, _ keyPath: WritableKeyPath<Patient, String>) -> some View {
        Toggle(title, isOn: Binding(
            get: { Patient.yes(draft[keyPath: keyPath]) },
            set: { draft[keyPath: keyPath] = Patient.yesNo($0) }))
    }
}
