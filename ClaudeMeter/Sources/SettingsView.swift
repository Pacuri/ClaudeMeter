import SwiftUI
import ServiceManagement

// MARK: - App Settings

class AppSettings: ObservableObject {
    @AppStorage("refreshInterval") var refreshInterval: Double = 60
    @AppStorage("showInMenuBar") var showPercentInMenuBar: Bool = true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("hasCompletedFirstLaunch") var hasCompletedFirstLaunch: Bool = false
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: ClaudeUsageViewModel
    @State private var manualKey: String = ""
    @State private var isDetecting = false

    var body: some View {
        TabView {
            accountTab
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }

            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 420, height: 280)
    }

    // MARK: - Account Tab

    private var accountTab: some View {
        Form {
            if viewModel.isAuthenticated {
                Section("Connected") {
                    if let email = viewModel.usage?.email {
                        LabeledContent("Email", value: email)
                    }
                    if let plan = viewModel.usage?.plan {
                        LabeledContent("Plan", value: plan)
                    }

                    Button("Disconnect", role: .destructive) {
                        viewModel.logout()
                    }
                }
            }

            Section("Authentication") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste your session key from claude.ai to connect.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Or paste manually:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack {
                        SecureField("sk-ant-sid01-...", text: $manualKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))

                        Button("Set") {
                            viewModel.setSessionKey(manualKey)
                            manualKey = ""
                        }
                        .disabled(manualKey.isEmpty)
                    }

                    Text("Find it in browser DevTools: Application > Cookies > claude.ai > sessionKey")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show usage % in menu bar", isOn: settings.$showPercentInMenuBar)

                Picker("Refresh interval", selection: settings.$refreshInterval) {
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                }
                .onChange(of: settings.refreshInterval) { _, newValue in
                    viewModel.setRefreshInterval(newValue)
                }
            }

            Section("System") {
                Toggle("Launch at login", isOn: settings.$launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            }

            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 2) {
                        Text("ClaudeMeter")
                            .font(.system(size: 11, weight: .medium))
                        Text("v1.0.0")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    // MARK: - Launch at Login

    private func setLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}
