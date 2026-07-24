import SwiftUI

struct MenuBarPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.hasCompletedOnboarding {
                dashboard
            } else {
                OnboardingView(model: model)
            }
        }
        .frame(width: 390)
        .background(.ultraThinMaterial)
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.roomy) {
                    StatusHeader(model: model)
                    metrics
                    homeSection
                }
                .padding(DesignSystem.Spacing.roomy)
            }
            .frame(maxHeight: 610)

            Divider()
            footer
        }
    }

    private var metrics: some View {
        HStack(spacing: DesignSystem.Spacing.compact) {
            MetricTile(
                title: "MONITORED",
                value: "\(model.homes.count)",
                detail: model.homes.count == 1 ? "Codex home" : "Codex homes",
                systemImage: "folder.badge.gearshape"
            )
            MetricTile(
                title: "LOG STORAGE",
                value: Formatters.byteCount(model.totalDatabaseBytes),
                detail: "Across all homes",
                systemImage: "cylinder.split.1x2"
            )
            MetricTile(
                title: "DISK FREE",
                value: model.availableDiskBytes.map(Formatters.byteCount) ?? "—",
                detail: "Internal volume",
                systemImage: "internaldrive"
            )
        }
    }

    @ViewBuilder
    private var homeSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.standard) {
            HStack {
                Text("CODEX HOMES")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                Spacer()

                if model.isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        model.scan()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Discover Codex homes again")
                }
            }

            if model.homes.isEmpty {
                EmptyHomesView(
                    isScanning: model.isScanning,
                    addFolder: model.chooseCustomHome,
                    rescan: model.scan
                )
            } else {
                ForEach(model.homes) { home in
                    HomeCard(
                        home: home,
                        reveal: { model.reveal(home) }
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DesignSystem.Spacing.standard) {
            Button {
                model.openActivityMonitor()
            } label: {
                Label("Activity Monitor", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button {
                model.quit()
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit SSD Watcher")
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, DesignSystem.Spacing.roomy)
        .padding(.vertical, DesignSystem.Spacing.standard)
    }
}

private struct StatusHeader: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.standard) {
            ZStack {
                Circle()
                    .fill(model.overallHealth.color.opacity(0.13))
                    .frame(width: 48, height: 48)

                Image(systemName: model.overallHealth.systemImage)
                    .font(.system(size: 23, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(model.overallHealth.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.overallHealth == .healthy ? "Your writes look normal" : model.overallHealth.title)
                    .font(.title3.weight(.semibold))

                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            StatusPill(health: model.overallHealth)
        }
    }

    private var statusDetail: String {
        if model.homes.isEmpty {
            return model.isScanning ? "Looking for Codex homes…" : "No Codex databases found yet."
        }
        if model.overallHealth == .healthy {
            if model.activeHomeCount == 0 {
                return "No active database writes detected."
            }
            return "Monitoring \(model.homes.count) homes for unusual activity."
        }
        return model.overallHealth.message
    }
}

struct StatusPill: View {
    let health: HealthLevel

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(health.color)
                .frame(width: 6, height: 6)
            Text(health.title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(health.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(health.color.opacity(0.1), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(health.title)")
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.55)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 2)
                Image(systemName: systemImage)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(DesignSystem.Colors.cardBorder, lineWidth: 1)
        )
    }
}

private struct EmptyHomesView: View {
    let isScanning: Bool
    let addFolder: () -> Void
    let rescan: () -> Void

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.standard) {
            Image(systemName: isScanning ? "magnifyingglass" : "folder.badge.questionmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(isScanning ? "Searching for Codex homes" : "No Codex homes found")
                    .font(.headline)
                Text("SSD Watcher validates database structure, so renamed and custom locations are supported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !isScanning {
                HStack {
                    Button("Scan Again", action: rescan)
                    Button("Choose Folder…", action: addFolder)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .cardSurface()
    }
}
