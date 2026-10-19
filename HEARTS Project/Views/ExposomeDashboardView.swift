import SwiftUI
import MapKit
import CoreLocation

struct ExposomeDashboardView: View {
    @State private var locationManager = LocationManager()
    @State private var exposomeService = ExposomeService()
    @State private var showStats = false
    @State private var showChat = false
    @State private var mapPosition: MapCameraPosition = .userLocation(
        followsHeading: false,
        fallback: .automatic
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $mapPosition) {
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 60)
                    .padding(.horizontal, 16)
                Spacer()
                askButton
                    .padding(.bottom, 12)
                statsButton
                    .padding(.bottom, 48)
            }
        }
        .onAppear {
            locationManager.requestLocation()
        }
        .onChange(of: locationManager.location) { _, newLocation in
            guard let loc = newLocation else { return }
            Task { await exposomeService.refresh(location: loc) }
        }
        .sheet(isPresented: $showStats) {
            StatsSheetView(
                locationLabel: locationManager.locationLabel,
                statuses: exposomeService.statuses,
                onRefresh: { Task { await forceRefresh() } }
            )
        }
        .sheet(isPresented: $showChat) {
            AgentChatView(
                locationLabel: locationManager.locationLabel,
                exposomeService: exposomeService
            )
        }
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
                    Image(systemName: "location.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(locationManager.locationLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task { await forceRefresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            .disabled(locationManager.location == nil)
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
        guard let loc = locationManager.location else {
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
