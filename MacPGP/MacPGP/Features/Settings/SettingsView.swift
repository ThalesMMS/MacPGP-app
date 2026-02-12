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
                    Label(String(localized: "settings.tab.general", comment: "General settings tab label"), systemImage: "gearshape")
                }

            keySettings
                .tabItem {
                    Label(String(localized: "settings.tab.keys", comment: "Keys settings tab label"), systemImage: "key")
                }

            securitySettings
                .tabItem {
                    Label(String(localized: "settings.tab.security", comment: "Security settings tab label"), systemImage: "lock.shield")
                }

            backupSettings
                .tabItem {
                    Label(String(localized: "settings.tab.backup", comment: "Backup settings tab label"), systemImage: "externaldrive")
                }

            keyserverSettings
                .tabItem {
                    Label(String(localized: "settings.tab.keyserver", comment: "Keyserver settings tab label"), systemImage: "server.rack")
                }
        }
        .frame(width: 500, height: 420)
        .confirmationDialog(
            String(localized: "settings.reset_dialog.title", comment: "Title for reset settings confirmation dialog"),
            isPresented: $showingResetConfirmation
        ) {
            Button(String(localized: "settings.reset_dialog.reset_button", comment: "Button to confirm reset to defaults"), role: .destructive) {
                preferences.resetToDefaults()
            }
            Button(String(localized: "settings.button.cancel", comment: "Cancel button"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.reset_dialog.message", comment: "Message explaining reset will restore default values"))
        }
        .confirmationDialog(
            String(localized: "settings.clear_keychain_dialog.title", comment: "Title for clear keychain confirmation dialog"),
            isPresented: $showingClearKeychainConfirmation
        ) {
            Button(String(localized: "settings.clear_keychain_dialog.clear_button", comment: "Button to confirm clearing all passphrases"), role: .destructive) {
                clearKeychain()
            }
            Button(String(localized: "settings.button.cancel", comment: "Cancel button"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.clear_keychain_dialog.message", comment: "Message explaining keychain clear will remove stored passphrases"))
        }
        .alert(String(localized: "settings.alert.error", comment: "Error alert title"), isPresented: $showingAlert) {
            Button(String(localized: "settings.button.ok", comment: "OK button")) {}
        } message: {
            Text(alertMessage ?? String(localized: "settings.alert.error_occurred", comment: "Generic error message"))
        }
    }

    private var generalSettings: some View {
        Form {
            Section(String(localized: "settings.general.language", comment: "Language section header")) {
                Picker(String(localized: "settings.general.language_picker", comment: "Label for language picker"), selection: $preferences.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }

            Section(String(localized: "settings.general.display", comment: "Display section header")) {
                Toggle(String(localized: "settings.general.show_key_id", comment: "Toggle to show Key ID in list"), isOn: $preferences.showKeyIDInList)

                Toggle(String(localized: "settings.general.confirm_delete", comment: "Toggle to confirm before deleting keys"), isOn: $preferences.confirmBeforeDelete)
            }

            Section(String(localized: "settings.general.output", comment: "Output section header")) {
                Toggle(String(localized: "settings.general.armor_output", comment: "Toggle for ASCII armor output by default"), isOn: $preferences.armorOutput)
            }

            Section(String(localized: "settings.general.storage", comment: "Storage section header")) {
                Toggle(String(localized: "settings.general.auto_save", comment: "Toggle to auto-save keyring changes"), isOn: $preferences.autoSaveKeyring)

                HStack {
                    Text(String(localized: "settings.general.keyring_location", comment: "Label for keyring location"))
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
                Button(String(localized: "settings.general.reset_button", comment: "Button to reset settings to defaults")) {
                    showingResetConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var keySettings: some View {
        Form {
            Section(String(localized: "settings.keys.section_title", comment: "Default key generation settings section header")) {
                Picker(String(localized: "settings.keys.algorithm", comment: "Label for algorithm picker"), selection: $preferences.defaultKeyAlgorithm) {
                    ForEach([KeyAlgorithm.rsa, .ecdsa, .eddsa]) { algo in
                        Text(algo.displayName).tag(algo)
                    }
                }

                Picker(String(localized: "settings.keys.key_size", comment: "Label for key size picker"), selection: $preferences.defaultKeySize) {
                    ForEach(preferences.defaultKeyAlgorithm.supportedKeySizes, id: \.self) { size in
                        Text("\(size) bits").tag(size)
                    }
                }

                Picker(String(localized: "settings.keys.expiration", comment: "Label for expiration picker"), selection: $preferences.defaultKeyExpirationMonths) {
                    Text(String(localized: "settings.keys.expiration.6_months", comment: "6 months expiration option")).tag(6)
                    Text(String(localized: "settings.keys.expiration.1_year", comment: "1 year expiration option")).tag(12)
                    Text(String(localized: "settings.keys.expiration.2_years", comment: "2 years expiration option")).tag(24)
                    Text(String(localized: "settings.keys.expiration.5_years", comment: "5 years expiration option")).tag(60)
                    Text(String(localized: "settings.keys.expiration.never", comment: "Never expire option")).tag(0)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var securitySettings: some View {
        Form {
            Section(String(localized: "settings.security.passphrase_storage", comment: "Passphrase storage section header")) {
                Toggle(String(localized: "settings.security.remember_passphrases", comment: "Toggle to remember passphrases in Keychain"), isOn: $preferences.rememberPassphrase)

                if preferences.rememberPassphrase {
                    Picker(String(localized: "settings.security.clear_after", comment: "Label for passphrase timeout picker"), selection: $preferences.passphraseTimeoutMinutes) {
                        Text(String(localized: "settings.security.timeout.5_minutes", comment: "5 minutes timeout option")).tag(5)
                        Text(String(localized: "settings.security.timeout.10_minutes", comment: "10 minutes timeout option")).tag(10)
                        Text(String(localized: "settings.security.timeout.30_minutes", comment: "30 minutes timeout option")).tag(30)
                        Text(String(localized: "settings.security.timeout.1_hour", comment: "1 hour timeout option")).tag(60)
                        Text(String(localized: "settings.security.timeout.never", comment: "Never clear timeout option")).tag(0)
                    }
                }
            }

            Section(String(localized: "settings.security.keychain", comment: "Keychain section header")) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(String(localized: "settings.security.stored_passphrases", comment: "Label for stored passphrases"))
                        Text(String(localized: "settings.security.clear_keychain_description", comment: "Description for clearing stored passphrases"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.security.clear_keychain_button", comment: "Button to clear keychain")) {
                        showingClearKeychainConfirmation = true
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "settings.security.note_title", comment: "Security note title"), systemImage: "info.circle")
                        .font(.headline)

                    Text(String(localized: "settings.security.note_message", comment: "Security note explaining keychain protection"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var backupSettings: some View {
        Form {
            Section(String(localized: "settings.backup.reminders", comment: "Backup reminders section header")) {
                Toggle(String(localized: "settings.backup.enable_reminders", comment: "Toggle to enable backup reminders"), isOn: $preferences.backupReminderEnabled)

                if preferences.backupReminderEnabled {
                    Picker(String(localized: "settings.backup.remind_every", comment: "Label for reminder interval picker"), selection: $preferences.backupReminderIntervalDays) {
                        Text(String(localized: "settings.backup.interval.7_days", comment: "7 days interval option")).tag(7)
                        Text(String(localized: "settings.backup.interval.14_days", comment: "14 days interval option")).tag(14)
                        Text(String(localized: "settings.backup.interval.30_days", comment: "30 days interval option")).tag(30)
                        Text(String(localized: "settings.backup.interval.60_days", comment: "60 days interval option")).tag(60)
                        Text(String(localized: "settings.backup.interval.90_days", comment: "90 days interval option")).tag(90)
                    }
                }
            }

            Section(String(localized: "settings.backup.status", comment: "Backup status section header")) {
                HStack {
                    Text(String(localized: "settings.backup.last_backup", comment: "Label for last backup date"))
                    Spacer()
                    if let lastBackup = preferences.lastBackupDate {
                        Text(lastBackup, style: .date)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(localized: "settings.backup.never", comment: "Never backed up status"))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "settings.backup.note_title", comment: "Backup note title"), systemImage: "info.circle")
                        .font(.headline)

                    Text(String(localized: "settings.backup.note_message", comment: "Backup note explaining importance of backups"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var keyserverSettings: some View {
        KeyServerSettingsView()
    }

    private func clearKeychain() {
        do {
            try KeychainManager.shared.deleteAllPassphrases()
        } catch {
            alertMessage = String(localized: "settings.error.clear_keychain_failed", defaultValue: "Failed to clear keychain", comment: "Error message when clearing keychain fails") + ": \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

#Preview {
    SettingsView()
        .environment(KeyringService())
}
