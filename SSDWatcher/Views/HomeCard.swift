import SwiftUI

struct HomeCard: View {
    let home: MonitoredHome
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
                    Text(Formatters.rate(home.metrics.insertRate))
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("Current database activity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                SparklineView(
                    values: home.history.map(\.value),
                    color: home.health.color
                )
                .frame(width: 106, height: 34)
                .accessibilityLabel("Recent insert-rate history")
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
                    .fill(home.health.color.opacity(0.11))
                    .frame(width: 32, height: 32)
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(home.health.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(home.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(home.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(home.candidate.rootURL.path)
            }

            Spacer()

            StatusPill(health: home.health)

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .contentShape(Rectangle())
    }

    private var details: some View {
        VStack(spacing: 10) {
            detailRow("Database storage", value: Formatters.byteCount(home.metrics.totalBytes))
            detailRow("Growth rate", value: Formatters.byteRate(home.metrics.growthBytesPerSecond))
            detailRow("Detection", value: home.confidenceLabel)
            detailRow("Databases", value: "\(home.candidate.databaseURLs.count)")

            HStack {
                Button {
                    reveal()
                } label: {
                    Label("Reveal Database", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text("Updated \(home.metrics.lastUpdated, style: .relative) ago")
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
