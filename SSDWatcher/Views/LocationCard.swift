import SwiftUI

struct LocationCard: View {
    let location: MonitoredLocation
    let reveal: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.standard) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                header
            }
            .buttonStyle(.plain)

            HStack(alignment: .bottom, spacing: DesignSystem.Spacing.roomy) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Formatters.recordRate(location.metrics.recordRate))
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("Current record activity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                SparklineView(
                    values: location.history.map(\.value),
                    color: location.health.color
                )
                .frame(width: 106, height: 34)
                .accessibilityLabel("Recent record-rate history")
            }

            if isExpanded {
                Divider()
                details
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardSurface()
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(location.health.color.opacity(0.11))
                    .frame(width: 32, height: 32)
                Image(systemName: location.candidate.product.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(location.health.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(location.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(location.candidate.product.displayName.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.45)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            DesignSystem.Colors.accent.opacity(0.09),
                            in: Capsule()
                        )
                }
                Text(location.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(location.candidate.rootURL.path)
            }

            Spacer()

            StatusPill(health: location.health)

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .contentShape(Rectangle())
    }

    private var details: some View {
        VStack(spacing: 10) {
            detailRow(
                "Database storage",
                value: Formatters.byteCount(location.metrics.totalBytes)
            )
            detailRow(
                "Growth rate",
                value: Formatters.byteRate(location.metrics.growthBytesPerSecond)
            )
            detailRow("Detection", value: location.confidenceLabel)
            detailRow("Databases", value: "\(location.candidate.databases.count)")

            HStack {
                Button {
                    reveal()
                } label: {
                    Label(
                        location.candidate.databases.count == 1
                            ? "Reveal Database"
                            : "Reveal Databases",
                        systemImage: "folder"
                    )
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("Updated \(location.metrics.lastUpdated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 2)
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.caption)
    }
}
