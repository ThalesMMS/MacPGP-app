import SwiftUI

struct SettingsView: View {
    @Environment(KeyringService.self) private var keyringService
    @State private var preferences = PreferencesManager.shared
    @State private var showingResetConfirmation = false
    @State private var showingClearKeychainConfirmation = false
    @State private var alertMessage: String?
    @State private var showingAlert = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            keySettings
                .tabItem {
                    Label("Keys", systemImage: "key")
                }

            securitySettings
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }
        }
        .frame(width: 450, height: 350)
        .confirmationDialog(
            "Reset Settings",
            isPresented: $showingResetConfirmation
        ) {
            Button("Reset to Defaults", role: .destructive) {
                preferences.resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset all settings to their default values.")
        }
        .confirmationDialog(
            "Clear Keychain",
            isPresented: $showingClearKeychainConfirmation
        ) {
            Button("Clear All Passphrases", role: .destructive) {
                clearKeychain()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all stored passphrases from the Keychain. You will need to enter them again when using your keys.")
        }
        .alert("Error", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "An error occurred")
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Display") {
                Toggle("Show Key ID in list", isOn: $preferences.showKeyIDInList)

                Toggle("Confirm before deleting keys", isOn: $preferences.confirmBeforeDelete)
            }

            Section("Output") {
                Toggle("ASCII armor output by default", isOn: $preferences.armorOutput)
            }

            Section("Storage") {
                Toggle("Auto-save keyring changes", isOn: $preferences.autoSaveKeyring)

                HStack {
                    Text("Keyring location")
                    Spacer()
                    Text(KeyringPersistence().keyringDirectory.path)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: KeyringPersistence().keyringDirectory.path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section {
                Button("Reset to Defaults") {
                    showingResetConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var keySettings: some View {
        Form {
            Section("Default Key Generation Settings") {
                Picker("Algorithm", selection: $preferences.defaultKeyAlgorithm) {
                    ForEach([KeyAlgorithm.rsa, .ecdsa, .eddsa]) { algo in
                        Text(algo.displayName).tag(algo)
                    }
                }

                Picker("Key Size", selection: $preferences.defaultKeySize) {
                    ForEach(preferences.defaultKeyAlgorithm.supportedKeySizes, id: \.self) { size in
                        Text("\(size) bits").tag(size)
                    }
                }

                Picker("Expiration", selection: $preferences.defaultKeyExpirationMonths) {
                    Text("6 months").tag(6)
                    Text("1 year").tag(12)
                    Text("2 years").tag(24)
                    Text("5 years").tag(60)
                    Text("Never").tag(0)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var securitySettings: some View {
        Form {
            Section("Passphrase Storage") {
                Toggle("Remember passphrases in Keychain", isOn: $preferences.rememberPassphrase)

                if preferences.rememberPassphrase {
                    Picker("Clear after", selection: $preferences.passphraseTimeoutMinutes) {
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("Never").tag(0)
                    }
                }
            }

            Section("Keychain") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Stored Passphrases")
                        Text("Clear all stored passphrases from the macOS Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear Keychain") {
                        showingClearKeychainConfirmation = true
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Security Note", systemImage: "info.circle")
                        .font(.headline)

                    Text("Passphrases are stored securely in the macOS Keychain, protected by your login password and optionally Touch ID or Apple Watch unlock.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func clearKeychain() {
        do {
            try KeychainManager.shared.deleteAllPassphrases()
        } catch {
            alertMessage = "Failed to clear keychain: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

#Preview {
    SettingsView()
        .environment(KeyringService())
}
