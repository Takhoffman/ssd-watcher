import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.section) {
            hero
            benefits
            discovery
            actions
            privacyNote
        }
        .padding(24)
    }

    private var hero: some View {
        VStack(spacing: DesignSystem.Spacing.standard) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.accent.opacity(0.18),
                                DesignSystem.Colors.healthy.opacity(0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DesignSystem.Colors.accent)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.healthy)
                    .background(Circle().fill(.background).padding(2))
                    .offset(x: 27, y: 26)
            }

            VStack(spacing: 5) {
                Text("Protect your SSD quietly")
                    .font(.title2.weight(.bold))
                Text("SSD Watcher catches abnormal database writes before they become expensive.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var benefits: some View {
        VStack(spacing: 10) {
            BenefitRow(
                icon: "magnifyingglass",
                title: "Finds custom locations",
                detail: "Uses verified database structure and live activity—not one folder name."
            )
            BenefitRow(
                icon: "bell.badge",
                title: "Warns before damage",
                detail: "Alerts explain what is writing, where, and how unusual it is."
            )
            BenefitRow(
                icon: "hand.raised",
                title: "Private by design",
                detail: "Reads counters and file metadata, never prompts, logs, or credentials."
            )
        }
    }

    private var discovery: some View {
        HStack(spacing: DesignSystem.Spacing.standard) {
            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: model.homes.isEmpty ? "folder.badge.questionmark" : "checkmark.circle.fill")
                    .foregroundStyle(model.homes.isEmpty ? .secondary : DesignSystem.Colors.healthy)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(discoveryTitle)
                    .font(.subheadline.weight(.semibold))
                Text(discoveryDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 9) {
            Button {
                model.completeOnboarding()
            } label: {
                Text("Start Monitoring")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isScanning)

            Button("Add another location…") {
                model.chooseCustomHome()
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var privacyNote: some View {
        Text("No account · No analytics · Open source")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.tertiary)
    }

    private var discoveryTitle: String {
        if model.isScanning { return "Looking for Codex homes…" }
        if model.homes.isEmpty { return "No Codex homes found yet" }
        return "Found \(model.homes.count) \(model.homes.count == 1 ? "Codex home" : "Codex homes")"
    }

    private var discoveryDetail: String {
        if model.isScanning { return "Checking filenames, database schemas, and live processes." }
        if model.homes.isEmpty { return "You can add a custom location now or rescan later." }
        return "Each location was validated before being added."
    }
}

private struct BenefitRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 26, height: 26)
                .background(DesignSystem.Colors.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
