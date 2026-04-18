import SwiftUI

struct KeyServerSettingsView: View {
    @State private var preferences = PreferencesManager.shared
    @State private var showingTestConnection = false
    @State private var connectionStatus: String?
    @State private var alertMessage: String?
    @State private var showingAlert = false

    private var enabledServers: [KeyServerConfig] {
        KeyServerConfig.defaults.filter { preferences.enabledKeyServers.contains($0.hostname) }
    }

    var body: some View {
        Form {
            Section("Enabled Keyservers") {
                ForEach(KeyServerConfig.defaults) { server in
                    Toggle(isOn: binding(for: server)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                            Text(server.hostname)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(enabledServers.count == 1 && enabledServers.contains(server))
                    .accessibilityIdentifier("Keyserver Toggle \(server.hostname)")
                }

                if enabledServers.count == 1 {
                    Text("At least one keyserver must remain enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Default Keyserver") {
                Picker("Server", selection: $preferences.defaultKeyServer) {
                    ForEach(enabledServers) { server in
                        VStack(alignment: .leading) {
                            Text(server.name)
                            Text(server.hostname)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(server.hostname)
                    }
                }
                .accessibilityIdentifier("Default Keyserver Picker")
            }

            Section("Network Settings") {
                HStack {
                    Text("Timeout")
                    Spacer()
                    Picker("", selection: $preferences.keyServerTimeout) {
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                        Text("90 seconds").tag(90)
                    }
                    .labelsHidden()
                }
            }

            Section("Key Management") {
                Toggle("Automatically refresh keys from keyserver", isOn: $preferences.autoRefreshKeys)

                if preferences.autoRefreshKeys {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Auto-refresh checks for key updates")
                            Text(
                                String(
                                    localized: "keyserver_settings.auto_refresh_message",
                                    defaultValue: "Keys will be refreshed periodically to get the latest updates from keyservers",
                                    comment: "Caption explaining what automatic key refresh does"
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Server Information") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("About Keyservers", systemImage: "info.circle")
                        .font(.headline)

                    Text("Public keyservers allow you to share your public key and discover keys from other users. The selected server will be used for search, upload, and refresh operations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Connection Status", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    /// Returns a `Binding<Bool>` that reflects whether the given keyserver is enabled.
    /// 
    /// When read, the binding reports whether `server.hostname` exists in the shared preferences. When written, it updates `preferences.enabledKeyServers`.
    /// - Parameter server: The keyserver configuration whose enabled state is being bound.
    /// - Returns: A binding that is `true` when the server is enabled, `false` otherwise.
    private func binding(for server: KeyServerConfig) -> Binding<Bool> {
        Binding(
            get: {
                preferences.enabledKeyServers.contains(server.hostname)
            },
            set: { isEnabled in
                var enabledServers = preferences.enabledKeyServers

                if isEnabled {
                    if !enabledServers.contains(server.hostname) {
                        enabledServers.append(server.hostname)
                    }
                } else {
                    enabledServers.removeAll { $0 == server.hostname }
                }

                preferences.enabledKeyServers = enabledServers
            }
        )
    }
}

#Preview {
    KeyServerSettingsView()
}
