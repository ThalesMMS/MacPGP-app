import SwiftUI

struct KeyServerSettingsView: View {
    @State private var preferences = PreferencesManager.shared
    @State private var showingTestConnection = false
    @State private var connectionStatus: String?
    @State private var alertMessage: String?
    @State private var showingAlert = false

    var body: some View {
        Form {
            Section("Default Keyserver") {
                Picker("Server", selection: $preferences.defaultKeyServer) {
                    ForEach(KeyServerConfig.defaults) { server in
                        VStack(alignment: .leading) {
                            Text(server.name)
                            Text(server.hostname)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(server.hostname)
                    }
                }
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
                            Text("Keys will be refreshed periodically to get revocation status and new signatures")
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
}

#Preview {
    KeyServerSettingsView()
}
