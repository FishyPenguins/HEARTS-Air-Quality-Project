import SwiftUI
import MapKit
import CoreLocation

struct ExposomeDashboardView: View {
    @State private var locationManager = LocationManager()
    @State private var exposomeService = ExposomeService()
    @State private var patientStore = PatientStore()
    @State private var alertManager = RiskAlertManager()
    @State private var showStats = false
    @State private var showChat = false
    @State private var showPicker = false
    @State private var showRisk = false
    /// Set from the risk screen's "What if…" simulator; nil means use live readings.
    @State private var whatIf: RiskConditions?
    @State private var mapPosition: MapCameraPosition = .userLocation(
        followsHeading: false,
        fallback: .automatic
    )

    private static let riskModel: RiskModel? = try? RiskModel.bundled()

    /// A practice patient's home town, or nil when "My info" is selected (then the phone's GPS is used).
    private var patientHome: CLLocation? {
        patientStore.selected.flatMap { PatientHome.location(for: $0) }
    }

    /// Where the live air and weather come from: the selected patient's home town, else the phone.
    private var activeLocation: CLLocation? { patientHome ?? locationManager.location }

    private var activeLabel: String {
        if patientHome != nil, let town = patientStore.selected?.town { return town }
        return locationManager.locationLabel
    }

    /// Tells the chat whether these readings are the patient's home town or where the phone is.
    private var chatLocationName: String {
        patientHome != nil ? "\(activeLabel) (the patient's home town)" : activeLabel
    }

    private var snapshot: EnvironmentSnapshot {
        EnvironmentSnapshot(statuses: exposomeService.statuses, locationName: chatLocationName)
    }

    private var liveConditions: RiskConditions { RiskConditions(snapshot: snapshot) }

    private var conditions: RiskConditions { whatIf ?? liveConditions }

    private var currentRisk: RiskAssessment? {
        guard let model = Self.riskModel, let patient = patientStore.selected else { return nil }
        return model.assess(patient, conditions: conditions)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $mapPosition) {
                UserAnnotation()
                if let home = patientHome, let patient = patientStore.selected {
                    Marker("\(patient.displayName) · \(patient.town)",
                           systemImage: "house.fill",
                           coordinate: home.coordinate)
                        .tint(.red)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 60)
                    .padding(.horizontal, 16)
                Spacer()
                if let patient = patientStore.selected {
                    RiskCardView(
                        patient: patient,
                        risk: currentRisk,
                        alert: alertManager.top,
                        isSimulated: whatIf != nil,
                        onSwitchPatient: { showPicker = true },
                        onOpenDetails: { showRisk = true },
                        onStep: { patientStore.step(by: $0) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                askButton
                    .padding(.bottom, 10)
                statsButton
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            locationManager.requestLocation()
            refreshAlerts()
            moveToActiveLocation()
        }
        .onChange(of: locationManager.location) { _, _ in
            // GPS only matters when "My info" is selected; practice patients use their home town.
            guard patientHome == nil else { return }
            moveToActiveLocation()
        }
        .onChange(of: patientStore.selectedID) { _, _ in
            moveToActiveLocation()
        }
        .onChange(of: currentRisk) { _, _ in refreshAlerts() }
        .sheet(isPresented: $showStats) {
            StatsSheetView(
                locationLabel: activeLabel,
                statuses: exposomeService.statuses,
                onRefresh: { Task { await forceRefresh() } }
            )
        }
        .sheet(isPresented: $showChat) {
            AgentChatView(
                locationLabel: chatLocationName,
                exposomeService: exposomeService,
                patient: patientStore.selected,
                risk: currentRisk,
                whatIf: whatIf
            )
        }
        .sheet(isPresented: $showPicker) {
            PatientPickerView(store: patientStore, model: Self.riskModel, conditions: conditions)
        }
        .sheet(isPresented: $showRisk) {
            if let model = Self.riskModel {
                RiskDetailView(
                    model: model,
                    store: patientStore,
                    liveConditions: liveConditions,
                    whatIf: $whatIf,
                    onAskHEARTS: {
                        Task {
                            try? await Task.sleep(for: .milliseconds(450))
                            showChat = true
                        }
                    }
                )
            }
        }
    }

    /// Loads live air and weather for the active location and centers the map on it.
    private func moveToActiveLocation() {
        if let home = patientHome {
            withAnimation(.easeInOut(duration: 0.6)) {
                mapPosition = .region(MKCoordinateRegion(
                    center: home.coordinate,
                    latitudinalMeters: 9000,
                    longitudinalMeters: 9000))
            }
        } else {
            withAnimation(.easeInOut(duration: 0.6)) {
                mapPosition = .userLocation(followsHeading: false, fallback: .automatic)
            }
        }
        guard let loc = activeLocation else { return }
        Task { await exposomeService.refresh(location: loc) }
    }

    private func refreshAlerts() {
        // Phone notifications only for real readings, not the what-if simulator.
        alertManager.update(patient: patientStore.selected, risk: currentRisk, notify: whatIf == nil)
    }

    private var askButton: some View {
        Button {
            showChat = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.subheadline.weight(.bold))
                Text("Ask HEARTS")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(Color(red: 0.45, green: 0.18, blue: 0.92))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.thickMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundStyle(
                    LinearGradient(colors: [.red, .orange], startPoint: .top, endPoint: .bottom)
                )
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("HEARTS")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Image(systemName: patientHome != nil ? "house.fill" : "location.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(activeLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let patient = patientStore.selected {
                Button { showPicker = true } label: {
                    PatientAvatar(patient: patient, level: currentRisk?.levelIndex, size: 32)
                }
                .accessibilityLabel("Switch patient, now \(patient.displayName)")
            }

            Button {
                Task { await forceRefresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            .disabled(activeLocation == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private var statsButton: some View {
        Button {
            showStats = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 34, height: 34)
                    Image(systemName: "chart.bar.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("View Area Stats")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(loadedCount) of \(ExposomeFactor.allCases.count) factors loaded")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.47, blue: 1.0),
                        Color(red: 0.45, green: 0.18, blue: 0.92)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .shadow(color: Color(red: 0.45, green: 0.18, blue: 0.92).opacity(0.45), radius: 20, y: 8)
            .padding(.horizontal, 20)
        }
    }

    private var loadedCount: Int {
        exposomeService.statuses.values.filter {
            if case .available = $0 { return true }
            return false
        }.count
    }

    private func forceRefresh() async {
        guard let loc = activeLocation else {
            locationManager.requestLocation()
            return
        }
        await exposomeService.forceRefresh(location: loc)
    }
}

// MARK: - Stats Sheet

struct StatsSheetView: View {
    let locationLabel: String
    let statuses: [ExposomeFactor: ExposomeStatus]
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    headerBanner
                        .padding(.bottom, 4)
                    ForEach(ExposomeFactor.allCases) { factor in
                        FactorCardView(
                            factor: factor,
                            status: statuses[factor] ?? .loading
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                        Text(locationLabel)
                            .font(.subheadline.weight(.semibold))
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .font(.body)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private var headerBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "leaf.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Environmental Exposome")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Live factors in your area")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            LinearGradient(
                colors: [.teal, .blue, Color(red: 0.45, green: 0.18, blue: 0.92)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .shadow(color: .blue.opacity(0.3), radius: 10, y: 4)
    }
}

#Preview {
    ExposomeDashboardView()
}
