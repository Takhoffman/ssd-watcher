import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            general
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            detection
                .tabItem {
                    Label("Detection", systemImage: "scope")
                }

            privacy
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
        }
        .padding(20)
    }

    private var general: some View {
        Form {
            Section("Startup") {
                Toggle(
                    "Launch SSD Watcher at login",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: model.toggleLaunchAtLogin
                    )
                )

                Toggle(
                    "Show activity notifications",
                    isOn: $model.notificationsEnabled
                )
                .onChange(of: model.notificationsEnabled) { _, enabled in
                    if enabled {
                        model.requestNotificationPermission()
                    }
                }
            }

            Section("Monitoring") {
                Picker("Check activity every", selection: $model.scanInterval) {
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                }

                LabeledContent("Last discovery scan") {
                    if let lastScan = model.lastScan {
                        Text(lastScan, style: .relative)
                    } else {
                        Text("Not completed")
                    }
                }

                Button("Scan for agent data now") {
                    model.scan()
                }
                .disabled(model.isScanning)

                Button("Check for Updates…") {
                    model.checkForUpdates()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var detection: some View {
        Form {
            Section {
                LabeledContent("Elevated alert") {
                    HStack(spacing: 6) {
                        TextField(
                            "Rate",
                            value: $model.warningRecordRate,
                            format: .number.precision(.fractionLength(0))
                        )
                        .frame(width: 72)
                        Text("records/s")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Critical alert") {
                    HStack(spacing: 6) {
                        TextField(
                            "Rate",
                            value: $model.criticalRecordRate,
                            format: .number.precision(.fractionLength(0))
                        )
                        .frame(width: 72)
                        Text("records/s")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Thresholds")
            } footer: {
                Text("Defaults are intentionally far above normal append activity. Database growth of 1 MB/s also triggers an elevated warning, even when a record counter is unavailable.")
            }

            Section {
                if model.customHomePaths.isEmpty {
                    Text("No manually added locations")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.customHomePaths, id: \.self) { path in
                        HStack {
                            Text(path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                model.removeCustomHome(path: path)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Stop monitoring \(path)")
                        }
                    }
                }

                Button("Add Location…") {
                    model.chooseCustomHome()
                }
            } header: {
                Text("Additional locations")
            } footer: {
                Text("Automatic discovery recognizes Codex, OpenClaw, and Hermes database structures, live processes, profiles, your home folder, and mounted local drives. It checks again every five minutes; add a folder only if it is still missed.")
            }
        }
        .formStyle(.grouped)
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsHero(
                icon: "hand.raised.fill",
                title: "Private by design",
                detail: "SSD Watcher operates locally and collects no analytics."
            )

            PrivacyRow(
                icon: "checkmark.shield",
                title: "What it reads",
                detail: "Database schemas, sequence counters, file sizes, timestamps, and active file paths."
            )
            PrivacyRow(
                icon: "eye.slash",
                title: "What it never reads",
                detail: "Prompts, responses, authentication files, credentials, or SQLite log messages."
            )
            PrivacyRow(
                icon: "trash.slash",
                title: "What it never changes",
                detail: "SSD Watcher does not delete databases, stop processes, or modify agent configuration."
            )

            Spacer()

            HStack {
                Text("SSD Watcher")
                    .fontWeight(.semibold)
                Spacer()
                Text(version)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(8)
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(short) (\(build))"
    }
}

private struct SettingsHero: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.accent)
                .frame(width: 48, height: 48)
                .background(DesignSystem.Colors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PrivacyRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
