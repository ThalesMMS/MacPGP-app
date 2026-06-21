import SwiftUI

struct KeyServerSettingsView: View {
    @State private var preferences = PreferencesManager.shared
    @State private var showingTestConnection = false
    @State private var connectionStatus: String?
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var pendingInsecureServer: KeyServerConfig?

    private var enabledServers: [KeyServerConfig] {
        KeyServerConfig.defaults.filter { preferences.enabledKeyServers.contains($0.hostname) }
    }

    var body: some View {
        Form {
            Section("settings.enabled_keyservers") {
                ForEach(KeyServerConfig.defaults) { server in
                    Toggle(isOn: binding(for: server)) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(server.name)
                                if server.requiresInsecureOptIn {
                                    insecureBadge(for: server)
                                }
                            }
                            Text(server.hostname)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(enabledServers.count == 1 && enabledServers.contains(server))
                    .accessibilityIdentifier("Keyserver Toggle \(server.hostname)")
                }

                if enabledServers.count == 1 {
                    Text("settings.at_least_one_keyserver_must_remain_enabl")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("keyserver_settings.default_keyserver") {
                Picker("keyserver_settings.server", selection: $preferences.defaultKeyServer) {
                    ForEach(enabledServers) { server in
                        VStack(alignment: .leading) {
                            HStack(spacing: 6) {
                                Text(server.name)
                                if server.requiresInsecureOptIn {
                                    insecureBadge(for: server)
                                }
                            }
                            Text(server.hostname)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(server.hostname)
                    }
                }
                .accessibilityIdentifier("Default Keyserver Picker")
            }

            Section("keyserver_settings.network_settings") {
                HStack {
                    Text("keyserver_settings.timeout")
                    Spacer()
                    Picker("", selection: $preferences.keyServerTimeout) {
                        Text("keyserver_settings.timeout_15s").tag(15)
                        Text("keyserver_settings.timeout_30s").tag(30)
                        Text("keyserver_settings.timeout_60s").tag(60)
                        Text("keyserver_settings.timeout_90s").tag(90)
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("Keyserver Timeout Picker")
                }
            }

            Section("keyserver_settings.server_information") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("keyserver_settings.about_keyservers", systemImage: "info.circle")
                        .font(.headline)

                    Text("keyserver_settings.about_message")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(String(localized: "keyserver_settings.transport_security_note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("Keyserver Transport Security Note")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Connection Status", isPresented: $showingAlert) {
            Button("common.ok") {}
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog(
            String(localized: "keyserver_settings.insecure_confirm_title"),
            isPresented: insecureConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(String(localized: "keyserver_settings.insecure_confirm_enable"), role: .destructive) {
                confirmEnableInsecureServer()
            }
            .accessibilityIdentifier("Confirm Insecure Keyserver")
            Button(String(localized: "keyserver_settings.insecure_confirm_cancel"), role: .cancel) {
                pendingInsecureServer = nil
            }
            .accessibilityIdentifier("Cancel Insecure Keyserver")
        } message: {
            if let server = pendingInsecureServer {
                Text(String(format: String(localized: "keyserver_settings.insecure_confirm_message"), server.name))
            }
        }
    }

    private func insecureBadge(for server: KeyServerConfig) -> some View {
        Text(String(localized: "keyserver_settings.insecure_badge"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2), in: Capsule())
            .foregroundStyle(.orange)
            .accessibilityIdentifier("Insecure Badge \(server.hostname)")
    }

    private var insecureConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingInsecureServer != nil },
            set: { isPresented in
                if !isPresented { pendingInsecureServer = nil }
            }
        )
    }

    /// Returns a `Binding<Bool>` that reflects whether the given keyserver is enabled.
    ///
    /// Enabling a secure server applies immediately. Enabling an insecure (HKP/HTTP)
    /// server that has not been opted into instead routes through a security
    /// confirmation; the binding snaps back to `false` until the user confirms.
    /// - Parameter server: The keyserver configuration whose enabled state is being bound.
    /// - Returns: A binding that is `true` when the server is enabled, `false` otherwise.
    private func binding(for server: KeyServerConfig) -> Binding<Bool> {
        Binding(
            get: {
                preferences.enabledKeyServers.contains(server.hostname)
            },
            set: { isEnabled in
                if isEnabled {
                    if server.requiresInsecureOptIn,
                       !preferences.isInsecureKeyServerAllowed(server.hostname) {
                        pendingInsecureServer = server
                        return
                    }
                    enableServer(server)
                } else {
                    disableServer(server)
                }
            }
        )
    }

    private func enableServer(_ server: KeyServerConfig) {
        var enabledServers = preferences.enabledKeyServers
        if !enabledServers.contains(server.hostname) {
            enabledServers.append(server.hostname)
        }
        preferences.enabledKeyServers = enabledServers
    }

    private func disableServer(_ server: KeyServerConfig) {
        var enabledServers = preferences.enabledKeyServers
        enabledServers.removeAll { $0 == server.hostname }
        preferences.enabledKeyServers = enabledServers
        // Clearing the opt-in means re-enabling this server prompts for confirmation again.
        if server.requiresInsecureOptIn {
            preferences.setInsecureKeyServer(server.hostname, allowed: false)
        }
    }

    private func confirmEnableInsecureServer() {
        guard let server = pendingInsecureServer else { return }
        preferences.setInsecureKeyServer(server.hostname, allowed: true)
        enableServer(server)
        pendingInsecureServer = nil
    }
}

#Preview {
    KeyServerSettingsView()
}
