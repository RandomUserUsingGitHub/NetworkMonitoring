import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var model: NetworkStateModel
    @Environment(\.dismiss) private var dismiss

    @State private var restartPending = false

    var theme: AppTheme { AppTheme.named(settings.theme) }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    settingsHeader
                    pingSection
                    ipSection
                    notificationSection
                    uiSection
                    systemSection
                    applyButton
                }
                .padding(20)
            }
        }
        .frame(width: 440, height: 600)
    }

    // MARK: Header
    private var settingsHeader: some View {
        HStack {
            Text("⚙️  Settings")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.accent2)
            Spacer()
            Button("Close") { dismiss() }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.dim)
                .buttonStyle(.plain)
        }
    }

    // MARK: - Sections
    private var pingSection: some View {
        SettingsSection(title: "PING", theme: theme) {
            SettingsRow(label: "Host", theme: theme) {
                TextField("8.8.8.8", text: $settings.pingHost)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .frame(width: 140)
                    .onChange(of: settings.pingHost) { _ in restartPending = true }
            }
            SettingsRow(label: "Interval (sec)", theme: theme) {
                StepperField(value: $settings.pingInterval, range: 0.5...60, step: 0.5, format: "%.1f")
                    .onChange(of: settings.pingInterval) { _ in restartPending = true }
            }
            SettingsRow(label: "Timeout (sec)", theme: theme) {
                StepperField(value: $settings.pingTimeout, range: 0.5...30, step: 0.5, format: "%.1f")
                    .onChange(of: settings.pingTimeout) { _ in restartPending = true }
            }
            SettingsRow(label: "Fail threshold", theme: theme) {
                IntStepperField(value: $settings.failThreshold, range: 1...20)
                    .onChange(of: settings.failThreshold) { _ in restartPending = true }
            }
            SettingsRow(label: "Packet size (bytes)", theme: theme) {
                IntStepperField(value: $settings.packetSize, range: 8...65507)
                    .onChange(of: settings.packetSize) { _ in restartPending = true }
            }
            SettingsRow(label: "History size", theme: theme) {
                IntStepperField(value: $settings.historySize, range: 10...500)
                    .onChange(of: settings.historySize) { _ in restartPending = true }
            }
        }
    }

    private var ipSection: some View {
        SettingsSection(title: "IP MONITORING", theme: theme) {
            SettingsRow(label: "Check interval (sec)", theme: theme) {
                StepperField(value: $settings.ipInterval, range: 5...300, step: 5, format: "%.0f")
                    .onChange(of: settings.ipInterval) { _ in restartPending = true }
            }
            SettingsRow(label: "Censor IP in notifications", theme: theme) {
                Toggle("", isOn: $settings.censorIPOnChange)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: settings.censorIPOnChange) { _ in restartPending = true }
            }
        }
    }

    private var notificationSection: some View {
        SettingsSection(title: "NOTIFICATIONS", theme: theme) {
            SettingsRow(label: "Enabled", theme: theme) {
                Toggle("", isOn: $settings.notificationsEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: settings.notificationsEnabled) { _ in restartPending = true }
            }
            SettingsRow(label: "Sound", theme: theme) {
                Picker("", selection: $settings.notificationSound) {
                    ForEach(["Basso", "Blow", "Bottle", "Frog", "Funk",
                             "Glass", "Hero", "Morse", "Ping", "Pop",
                             "Purr", "Sosumi", "Submarine", "Tink"], id: \.self) { s in
                        Text(s).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 120)
            }
        }
    }

    private var uiSection: some View {
        SettingsSection(title: "APPEARANCE", theme: theme) {
            SettingsRow(label: "Theme", theme: theme) {
                Picker("", selection: $settings.theme) {
                    Text("Green").tag("green")
                    Text("Amber").tag("amber")
                    Text("Blue").tag("blue")
                    Text("Red").tag("red")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            SettingsRow(label: "Graph width", theme: theme) {
                IntStepperField(value: $settings.graphWidth, range: 20...200)
            }
            SettingsRow(label: "Event log lines", theme: theme) {
                IntStepperField(value: $settings.logTailLines, range: 3...20)
            }
            SettingsRow(label: "Subtitle text", theme: theme) {
                TextField("by Armin Hashemi", text: $settings.subtitleText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .frame(width: 180)
            }
        }
    }

    private var systemSection: some View {
        SettingsSection(title: "SYSTEM", theme: theme) {
            SettingsRow(label: "Start daemon at login", theme: theme) {
                Toggle("", isOn: $settings.launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    private var applyButton: some View {
        HStack {
            Spacer()
            if restartPending {
                Text("Restart daemon to apply ping changes")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.warn)
            }
            Button(restartPending ? "Apply & Restart Daemon" : "Done") {
                settings.save()
                if restartPending {
                    model.restartDaemon()
                    restartPending = false
                }
                dismiss()
            }
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(theme.bg)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }
}

// MARK: - Reusable components

struct SettingsSection<Content: View>: View {
    let title: String
    let theme: AppTheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.dim)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(theme.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.border.opacity(0.25), lineWidth: 1))
        }
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    let theme: AppTheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.text)
            Spacer()
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        Divider().overlay(theme.border.opacity(0.1)).padding(.horizontal, 14)
    }
}

struct StepperField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step:  Double
    let format: String

    var body: some View {
        HStack(spacing: 6) {
            Text(String(format: format, value))
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 44, alignment: .trailing)
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
                .frame(width: 80)
        }
    }
}

struct IntStepperField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 44, alignment: .trailing)
            Stepper("", value: $value, in: range)
                .labelsHidden()
                .frame(width: 80)
        }
    }
}
