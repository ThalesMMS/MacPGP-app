import SwiftUI

struct SettingsView: View {
    @Environment(KeyringService.self) private var keyringService
    @State private var preferences = PreferencesManager.shared
    @State private var showingResetConfirmation = false
    @State private var showingClearKeychainConfirmation = false
    @State private var alertMessage: String?
    @State private var showingAlert = false
    @State private var backupReminderService = BackupReminderService()

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label(String(localized: "settings.general", comment: "General settings tab label"), systemImage: "gearshape")
                }

            keySettings
                .tabItem {
                    Label(String(localized: "settings.keys", comment: "Keys settings tab label"), systemImage: "key")
                }

            securitySettings
                .tabItem {
                    Label(String(localized: "settings.security", comment: "Security settings tab label"), systemImage: "lock.shield")
                }

            backupSettings
                .tabItem {
                    Label(String(localized: "settings.backup", comment: "Backup settings tab label"), systemImage: "externaldrive")
                }

            keyserverSettings
                .tabItem {
                    Label(String(localized: "settings.keyserver", comment: "Keyserver settings tab label"), systemImage: "server.rack")
                }
        }
        .frame(width: 500, height: 420)
        .confirmationDialog(
            String(localized: "settings.reset_settings", comment: "Title for reset settings confirmation dialog"),
            isPresented: $showingResetConfirmation
        ) {
            Button(String(localized: "settings.reset_defaults", comment: "Button to confirm reset to defaults"), role: .destructive) {
                resetPreferencesToDefaults()
            }
            Button(String(localized: "common.cancel", comment: "Cancel button"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.reset_confirmation", comment: "Message explaining reset will restore default values"))
        }
        .confirmationDialog(
            String(localized: "settings.clear_keychain_title", comment: "Title for clear keychain confirmation dialog"),
            isPresented: $showingClearKeychainConfirmation
        ) {
            Button(String(localized: "settings.clear_keychain", comment: "Button to confirm clearing all passphrases"), role: .destructive) {
                clearKeychain()
            }
            Button(String(localized: "common.cancel", comment: "Cancel button"), role: .cancel) {}
        } message: {
            Text(String(localized: "settings.clear_keychain_confirmation", comment: "Message explaining keychain clear will remove stored passphrases"))
        }
        .alert(String(localized: "common.error", comment: "Error alert title"), isPresented: $showingAlert) {
            Button(String(localized: "common.ok", comment: "OK button")) {}
        } message: {
            Text(alertMessage ?? String(localized: "error.generic", comment: "Generic error message"))
        }
    }

    private var generalSettings: some View {
        Form {
            Section(String(localized: "settings.language", comment: "Language section header")) {
                Picker(String(localized: "settings.language_picker", comment: "Label for language picker"), selection: $preferences.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }

            Section(String(localized: "settings.display", comment: "Display section header")) {
                Toggle(String(localized: "settings.show_key_id", comment: "Toggle to show Key ID in list"), isOn: $preferences.showKeyIDInList)

                Toggle(String(localized: "settings.confirm_delete", comment: "Toggle to confirm before deleting keys"), isOn: $preferences.confirmBeforeDelete)
            }

            Section(String(localized: "settings.output", comment: "Output section header")) {
                Toggle(String(localized: "settings.ascii_armor_default", comment: "Toggle for ASCII armor output by default"), isOn: $preferences.armorOutput)
            }

            Section(String(localized: "settings.storage", comment: "Storage section header")) {
                Toggle(String(localized: "settings.auto_save", comment: "Toggle to auto-save keyring changes"), isOn: $preferences.autoSaveKeyring)

                HStack {
                    Text(String(localized: "settings.keyring_location", comment: "Label for keyring location"))
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
                Button(String(localized: "settings.reset_defaults", comment: "Button to reset settings to defaults")) {
                    showingResetConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var keySettings: some View {
        Form {
            Section(String(localized: "settings.default_keygen", comment: "Default key generation settings section header")) {
                Picker(String(localized: "settings.algorithm", comment: "Label for algorithm picker"), selection: $preferences.defaultKeyAlgorithm) {
                    ForEach([KeyAlgorithm.rsa, .ecdsa, .eddsa]) { algo in
                        Text(algo.displayName).tag(algo)
                    }
                }

                Picker(String(localized: "settings.key_size", comment: "Label for key size picker"), selection: $preferences.defaultKeySize) {
                    ForEach(preferences.defaultKeyAlgorithm.supportedKeySizes, id: \.self) { size in
                        Text(String.localizedStringWithFormat(NSLocalizedString("keygen.bits_format", comment: ""), size)).tag(size)
                    }
                }
                .disabled(preferences.defaultKeyAlgorithm.supportedKeySizes.count == 1)

                Picker(String(localized: "settings.expiration", comment: "Label for expiration picker"), selection: $preferences.defaultKeyExpirationMonths) {
                    Text(String(localized: "settings.expiry_6_months", comment: "6 months expiration option")).tag(6)
                    Text(String(localized: "settings.expiry_1_year", comment: "1 year expiration option")).tag(12)
                    Text(String(localized: "settings.expiry_2_years", comment: "2 years expiration option")).tag(24)
                    Text(String(localized: "settings.expiry_5_years", comment: "5 years expiration option")).tag(60)
                    Text(String(localized: "settings.never", comment: "Never expire option")).tag(0)
                }

                if preferences.defaultKeyAlgorithm == .ecdsa {
                    Text(String(localized: "settings.keys.algorithm_help.ecdsa", comment: "Help text explaining that ECDSA keys include an encryption subkey"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if preferences.defaultKeyAlgorithm == .eddsa {
                    Text(String(localized: "settings.keys.algorithm_help.eddsa", comment: "Help text explaining that EdDSA keys include an encryption subkey"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var securitySettings: some View {
        Form {
            Section(String(localized: "settings.passphrase_storage", comment: "Passphrase storage section header")) {
                Toggle(String(localized: "settings.remember_passphrases", comment: "Toggle to remember passphrases in Keychain"), isOn: $preferences.rememberPassphrase)
                    .onChange(of: preferences.rememberPassphrase) { _, rememberPassphrases in
                        if !rememberPassphrases {
                            PassphraseCache.shared.clear()
                        }
                    }

                if preferences.rememberPassphrase {
                    Picker(String(localized: "settings.clear_after", comment: "Label for passphrase timeout picker"), selection: $preferences.passphraseTimeoutMinutes) {
                        Text(String(localized: "settings.clear_5_min", comment: "5 minutes timeout option")).tag(5)
                        Text(String(localized: "settings.clear_10_min", comment: "10 minutes timeout option")).tag(10)
                        Text(String(localized: "settings.clear_30_min", comment: "30 minutes timeout option")).tag(30)
                        Text(String(localized: "settings.clear_1_hour", comment: "1 hour timeout option")).tag(60)
                        Text(String(localized: "settings.never", comment: "Never clear timeout option")).tag(0)
                    }
                }
            }

            Section(String(localized: "settings.keychain", comment: "Keychain section header")) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(String(localized: "settings.stored_passphrases", comment: "Label for stored passphrases"))
                        Text(String(localized: "settings.clear_keychain_message", comment: "Description for clearing stored passphrases"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.clear_keychain", comment: "Button to clear keychain")) {
                        showingClearKeychainConfirmation = true
                    }
                }
            }

            Section(String(localized: "settings.security.session_lock", comment: "Session lock section header")) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(String(localized: "settings.security.lock_now_title", comment: "In-memory passphrase lock row title"))
                        Text(String(localized: "settings.security.lock_now_description", comment: "Explanation distinguishing the temporary cache, Keychain persistence, and system-lock behavior"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "settings.security.lock_now_button", comment: "Button to lock MacPGP now")) {
                        SessionLockController.shared.lock()
                    }
                    .accessibilityIdentifier("Lock MacPGP Now")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "settings.security_note", comment: "Security note title"), systemImage: "info.circle")
                        .font(.headline)

                    Text(String(localized: "settings.security_note_message", comment: "Security note explaining keychain protection"))
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
                Toggle(String(localized: "settings.backup.enable_reminders", comment: "Toggle to enable backup reminders"), isOn: backupReminderEnabled)

                Text(String(localized: "settings.backup.notification_permission_note", comment: "Explains contextual notification permission for backup reminders"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if preferences.backupReminderEnabled {
                    Picker(String(localized: "settings.backup.remind_every", comment: "Label for reminder interval picker"), selection: backupReminderIntervalDays) {
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

    private var backupReminderEnabled: Binding<Bool> {
        Binding {
            preferences.backupReminderEnabled
        } set: { isEnabled in
            preferences.backupReminderEnabled = isEnabled
            updateBackupReminderSchedule()
        }
    }

    private var backupReminderIntervalDays: Binding<Int> {
        Binding {
            preferences.backupReminderIntervalDays
        } set: { intervalDays in
            preferences.backupReminderIntervalDays = intervalDays
            updateBackupReminderSchedule()
        }
    }

    private func updateBackupReminderSchedule() {
        if preferences.backupReminderEnabled {
            backupReminderService.updateReminderSchedule()
        } else {
            backupReminderService.cancelScheduledReminder()
        }
    }

    private func resetPreferencesToDefaults() {
        preferences.resetToDefaults()
        updateBackupReminderSchedule()
    }

    /// Clears all stored passphrases from the keychain.
    ///
    /// If the operation fails, displays an error alert.
    private func clearKeychain() {
        do {
            try KeychainManager.shared.deleteAllPassphrases()
        } catch {
            alertMessage = String(localized: "error.keychain_error.description", comment: "Error message when clearing keychain fails") + ": \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

#Preview {
    SettingsView()
        .environment(KeyringService())
}
