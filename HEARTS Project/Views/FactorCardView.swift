import SwiftUI

struct FactorCardView: View {
    let factor: ExposomeFactor
    let status: ExposomeStatus

    var body: some View {
        HStack(spacing: 16) {
            iconView
            VStack(alignment: .leading, spacing: 4) {
                Text(factor.shortName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                valueLabel
            }
            Spacer()
            metaLabel
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [factor.color.opacity(0.5), factor.color.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: factor.color.opacity(0.15), radius: 8, y: 3)
    }

    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [factor.color.opacity(0.25), factor.color.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 54, height: 54)
            Image(systemName: factor.symbolName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(factor.color)
        }
    }

    @ViewBuilder
    private var valueLabel: some View {
        switch status {
        case .loading:
            ProgressView()
                .scaleEffect(0.8)
                .frame(height: 28)
        case .available(let r):
            Text(r.displayValue)
                .font(.title2.weight(.bold))
                .foregroundStyle(r.isStale ? .orange : .primary)
        case .notAvailable:
            Text("Not available")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .failed(_, let last):
            if let last {
                Text(last.displayValue)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.orange)
            } else {
                Text("Unavailable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var metaLabel: some View {
        VStack(alignment: .trailing, spacing: 4) {
            switch status {
            case .loading:
                EmptyView()
            case .available(let r):
                Text(r.ageString)
                    .font(.caption2)
                    .foregroundStyle(r.isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                if r.isStale {
                    Text("STALE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15), in: Capsule())
                }
            case .notAvailable:
                Text("—")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            case .failed(_, let last):
                Text(last != nil ? last!.ageString : "Error")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
