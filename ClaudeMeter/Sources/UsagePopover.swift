import SwiftUI
import ServiceManagement

// Claude's brand orange
extension Color {
    static let claudeOrange = Color(red: 0.85, green: 0.45, blue: 0.18)
    static let claudeOrangeLight = Color(red: 0.95, green: 0.60, blue: 0.30)
}

// MARK: - Main Popover

struct UsagePopover: View {
    @ObservedObject var viewModel: ClaudeUsageViewModel
    @ObservedObject var settings: AppSettings
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()
                .opacity(0.3)

            if showSettings {
                settingsSection
            } else if viewModel.isAuthenticated {
                if let usage = viewModel.usage {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            sessionSection(usage)
                            weeklySection(usage)

                            if let sonnet = usage.sonnetPercentUsed, sonnet > 0 {
                                sonnetSection(usage)
                            }

                            if let opus = usage.opusPercentUsed, opus > 0 {
                                opusSection(usage)
                            }

                            if usage.extraUsageEnabled {
                                extraUsageSection(usage)
                            }
                        }
                        .padding(16)
                    }
                } else if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                } else if let error = viewModel.error {
                    Spacer()
                    errorView(error)
                    Spacer()
                }
            } else {
                Spacer()
                notAuthenticatedView
                Spacer()
            }

            Divider()
                .opacity(0.3)

            // Footer
            footerSection
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "staroflife.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.claudeOrange)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Claude")
                        .font(.system(size: 15, weight: .semibold))
                    if let usage = viewModel.usage {
                        Text("Updated \(timeAgo(usage.lastUpdated))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let usage = viewModel.usage {
                Text(usage.plan)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(Capsule())
            }
        }
        .padding(16)
    }

    // MARK: - Usage Sections

    private func sessionSection(_ usage: ClaudeUsageData) -> some View {
        UsageCard(
            title: "Session",
            percent: usage.sessionPercentUsed,
            detail: "Resets in \(usage.sessionResetsIn)",
            subtitle: nil
        )
    }

    private func weeklySection(_ usage: ClaudeUsageData) -> some View {
        UsageCard(
            title: "Weekly",
            percent: usage.weeklyPercentUsed,
            detail: "Resets in \(usage.weeklyResetsIn)",
            subtitle: usage.weeklyPace
        )
    }

    private func sonnetSection(_ usage: ClaudeUsageData) -> some View {
        UsageCard(
            title: "Sonnet",
            percent: usage.sonnetPercentUsed ?? 0,
            detail: nil,
            subtitle: nil
        )
    }

    private func opusSection(_ usage: ClaudeUsageData) -> some View {
        UsageCard(
            title: "Opus",
            percent: usage.opusPercentUsed ?? 0,
            detail: nil,
            subtitle: nil
        )
    }

    private func extraUsageSection(_ usage: ClaudeUsageData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Extra Usage")
                .font(.system(size: 13, weight: .semibold))

            HStack {
                Text(String(format: "$%.2f / $%.2f", usage.extraCurrentSpend, usage.extraMonthlyLimit))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                let pct = usage.extraMonthlyLimit > 0
                    ? Int(usage.extraCurrentSpend / usage.extraMonthlyLimit * 100)
                    : 0
                Text("\(pct)%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            UsageBar(
                percent: usage.extraMonthlyLimit > 0
                    ? Int(usage.extraCurrentSpend / usage.extraMonthlyLimit * 100)
                    : 0
            )
        }
        .padding(12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - States

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(Color.claudeOrange)
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @State private var pastedKey: String = ""

    private var notAuthenticatedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "key")
                .font(.system(size: 28))
                .foregroundStyle(Color.claudeOrange.opacity(0.7))
            Text("Session key needed")
                .font(.system(size: 13, weight: .medium))

            VStack(spacing: 8) {
                Text("Paste your sessionKey from claude.ai cookies:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 6) {
                    SecureField("sk-ant-sid01-...", text: $pastedKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))

                    Button("Go") {
                        viewModel.setSessionKey(pastedKey)
                        pastedKey = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color.claudeOrange)
                    .disabled(pastedKey.isEmpty)
                }
                .padding(.horizontal, 16)

                Text("DevTools (Cmd+Opt+I) > Application > Cookies > claude.ai")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Inline Settings

    @State private var settingsKey: String = ""

    private var settingsSection: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                // Account
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account")
                        .font(.system(size: 13, weight: .semibold))

                    if viewModel.isAuthenticated {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 12))
                            Text("Connected")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Disconnect") {
                                viewModel.logout()
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Session Key")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            SecureField("sk-ant-sid01-...", text: $settingsKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                            Button("Set") {
                                viewModel.setSessionKey(settingsKey)
                                settingsKey = ""
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(Color.claudeOrange)
                            .disabled(settingsKey.isEmpty)
                        }
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Preferences
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preferences")
                        .font(.system(size: 13, weight: .semibold))

                    Toggle("Show usage % in menu bar", isOn: settings.$showPercentInMenuBar)
                        .font(.system(size: 12))

                    HStack {
                        Text("Refresh interval")
                            .font(.system(size: 12))
                        Spacer()
                        Picker("", selection: settings.$refreshInterval) {
                            Text("30s").tag(30.0)
                            Text("1m").tag(60.0)
                            Text("2m").tag(120.0)
                            Text("5m").tag(300.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .onChange(of: settings.refreshInterval) { _, newValue in
                            viewModel.setRefreshInterval(newValue)
                        }
                    }

                    Toggle("Launch at login", isOn: settings.$launchAtLogin)
                        .font(.system(size: 12))
                        .onChange(of: settings.launchAtLogin) { _, enabled in
                            if enabled {
                                try? SMAppService.mainApp.register()
                            } else {
                                try? SMAppService.mainApp.unregister()
                            }
                        }
                }
                .padding(12)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(16)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 16) {
            Button {
                if let url = URL(string: "https://claude.ai/settings/usage") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Usage Dashboard", systemImage: "chart.bar")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettings.toggle()
                }
            } label: {
                Label("Settings", systemImage: showSettings ? "xmark" : "gear")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - Usage Card (V1 style with Claude orange)

struct UsageCard: View {
    let title: String
    let percent: Int
    let detail: String?
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            UsageBar(percent: percent)

            HStack {
                Text("\(percent)% used")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                if let detail = detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .italic()
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Usage Bar (Claude orange gradient)

struct UsageBar: View {
    let percent: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.quaternary)
                    .frame(height: 6)

                // Fill
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(barGradient)
                    .frame(
                        width: max(4, geo.size.width * CGFloat(min(percent, 100)) / 100),
                        height: 6
                    )

                // Dot indicator
                if percent > 0 && percent < 100 {
                    Circle()
                        .fill(barColor)
                        .frame(width: 8, height: 8)
                        .offset(x: geo.size.width * CGFloat(min(percent, 100)) / 100 - 4)
                }
            }
        }
        .frame(height: 8)
    }

    private var barColor: Color {
        switch percent {
        case 0..<70: return .claudeOrange
        case 70..<90: return .claudeOrangeLight
        default: return .red
        }
    }

    private var barGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [barColor.opacity(0.7), barColor]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
