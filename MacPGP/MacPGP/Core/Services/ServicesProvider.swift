import Foundation
import AppKit
import SwiftUI

/// Provides macOS Services menu integration for PGP operations
/// This class handles system-wide encrypt, decrypt, and sign services
/// that can be accessed from any application via the Services menu
final class ServicesProvider: NSObject {
    private let keyringService: KeyringService
    private let encryptionService: EncryptionService
    private let signingService: SigningService

    init(keyringService: KeyringService) {
        self.keyringService = keyringService
        self.encryptionService = EncryptionService(keyringService: keyringService)
        self.signingService = SigningService(keyringService: keyringService)
        super.init()
    }

    // MARK: - Service Methods

    /// Encrypts selected text from any application
    /// This method is called by macOS Services when "Encrypt with MacPGP" is selected
    @objc func encryptService(_ pasteboard: NSPasteboard, userData: String?, error: NSErrorPointer) {
        guard let inputText = pasteboard.string(forType: .string), !inputText.isEmpty else {
            showError("No text selected", description: "Please select text to encrypt")
            return
        }

        // Get available public keys for encryption
        let availableKeys = keyringService.publicKeys()
        guard !availableKeys.isEmpty else {
            showError("No public keys available", description: "Import public keys to encrypt messages")
            return
        }

        // Show recipient picker on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard let selectedRecipients = self.showRecipientPicker(),
                  !selectedRecipients.isEmpty else {
                return // User cancelled or no recipients selected
            }

            // Perform encryption with selected recipients
            do {
                let encryptedMessage = try self.encryptionService.encrypt(
                    message: inputText,
                    for: Array(selectedRecipients),
                    signedBy: nil,
                    passphrase: nil,
                    armored: true
                )
                self.writeResult(encryptedMessage, to: pasteboard)
            } catch {
                self.showError("Encryption failed", description: error.localizedDescription)
            }
        }
    }

    /// Decrypts selected PGP message from any application
    /// This method is called by macOS Services when "Decrypt with MacPGP" is selected
    @objc func decryptService(_ pasteboard: NSPasteboard, userData: String?, error: NSErrorPointer) {
        guard let inputText = pasteboard.string(forType: .string), !inputText.isEmpty else {
            showError("No text selected", description: "Please select a PGP encrypted message to decrypt")
            return
        }

        // Verify this looks like a PGP message
        guard inputText.contains("-----BEGIN PGP MESSAGE-----") else {
            showError("Invalid PGP message", description: "The selected text does not appear to be a PGP encrypted message")
            return
        }

        // Get available secret keys for decryption
        let secretKeys = keyringService.secretKeys()
        guard !secretKeys.isEmpty else {
            showError("No secret keys available", description: "Import a secret key to decrypt messages")
            return
        }

        // Show key picker on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard let (selectedKey, passphrase) = self.showKeyPicker(
                secretKeys: secretKeys,
                operation: "Decrypt Message"
            ) else {
                return // User cancelled
            }

            // Perform decryption with selected key and passphrase
            do {
                let decryptedMessage = try self.encryptionService.decrypt(
                    message: inputText,
                    using: selectedKey,
                    passphrase: passphrase
                )
                self.writeResult(decryptedMessage, to: pasteboard)
            } catch {
                self.showError("Decryption failed", description: error.localizedDescription)
            }
        }
    }

    /// Signs selected text from any application
    /// This method is called by macOS Services when "Sign with MacPGP" is selected
    @objc func signService(_ pasteboard: NSPasteboard, userData: String?, error: NSErrorPointer) {
        guard let inputText = pasteboard.string(forType: .string), !inputText.isEmpty else {
            showError("No text selected", description: "Please select text to sign")
            return
        }

        // Get available secret keys for signing
        let secretKeys = keyringService.secretKeys()
        guard !secretKeys.isEmpty else {
            showError("No secret keys available", description: "Import or generate a key pair to sign messages")
            return
        }

        // Show key picker on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard let (selectedKey, passphrase) = self.showKeyPicker(
                secretKeys: secretKeys,
                operation: "Sign Message"
            ) else {
                return // User cancelled
            }

            // Perform signing with selected key and passphrase
            do {
                let signedMessage = try self.signingService.sign(
                    message: inputText,
                    using: selectedKey,
                    passphrase: passphrase,
                    cleartext: true,
                    detached: false,
                    armored: true
                )
                self.writeResult(signedMessage, to: pasteboard)
            } catch {
                self.showError("Signing failed", description: error.localizedDescription)
            }
        }
    }

    // MARK: - UI Selection Methods

    /// Shows a modal dialog for selecting recipients (public keys) for encryption
    /// - Returns: Set of selected keys, or nil if cancelled
    private func showRecipientPicker() -> Set<PGPKeyModel>? {
        let availableKeys = keyringService.publicKeys().filter { !$0.isExpired }
        var selectedRecipients: Set<PGPKeyModel> = []
        var dialogResult: NSApplication.ModalResponse?

        let pickerView = RecipientSelectionView(
            availableKeys: availableKeys,
            selectedRecipients: Binding(
                get: { selectedRecipients },
                set: { selectedRecipients = $0 }
            ),
            onComplete: { result in
                dialogResult = result
            }
        )

        let hostingController = NSHostingController(rootView: pickerView)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 450, height: 400)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Select Recipients"
        panel.contentView = hostingController.view
        panel.center()
        panel.isReleasedWhenClosed = false

        let response = NSApp.runModal(for: panel)
        panel.close()

        return response == .OK ? selectedRecipients : nil
    }

    /// Shows a modal dialog for selecting a secret key and entering passphrase
    /// - Returns: Tuple of selected key and passphrase, or nil if cancelled
    private func showKeyPicker(secretKeys: [PGPKeyModel], operation: String) -> (key: PGPKeyModel, passphrase: String)? {
        var selectedKey: PGPKeyModel?
        var passphrase: String = ""
        var dialogResult: NSApplication.ModalResponse?

        let pickerView = KeyPassphraseSelectionView(
            secretKeys: secretKeys,
            operation: operation,
            selectedKey: Binding(
                get: { selectedKey },
                set: { selectedKey = $0 }
            ),
            passphrase: Binding(
                get: { passphrase },
                set: { passphrase = $0 }
            ),
            onComplete: { result in
                dialogResult = result
            }
        )

        let hostingController = NSHostingController(rootView: pickerView)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 400, height: 280)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = operation
        panel.contentView = hostingController.view
        panel.center()
        panel.isReleasedWhenClosed = false

        let response = NSApp.runModal(for: panel)
        panel.close()

        if response == .OK, let key = selectedKey, !passphrase.isEmpty {
            return (key, passphrase)
        }
        return nil
    }

    // MARK: - Helper Methods

    /// Shows an error alert to the user
    private func showError(_ message: String, description: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = description
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Writes encrypted/signed result back to pasteboard
    private func writeResult(_ result: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(result, forType: .string)
    }
}

// MARK: - SwiftUI Selection Views

/// SwiftUI view for selecting recipients (public keys) for encryption
private struct RecipientSelectionView: View {
    let availableKeys: [PGPKeyModel]
    @Binding var selectedRecipients: Set<PGPKeyModel>
    let onComplete: (NSApplication.ModalResponse) -> Void

    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if availableKeys.isEmpty {
                ContentUnavailableView(
                    "No Keys Available",
                    systemImage: "key",
                    description: Text("Import recipient public keys first")
                )
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select one or more recipients to encrypt for:")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    TextField("Search recipients...", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredKeys) { key in
                                RecipientRowButton(
                                    key: key,
                                    isSelected: selectedRecipients.contains(key)
                                ) {
                                    toggleSelection(key)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)

                    if !selectedRecipients.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected (\(selectedRecipients.count))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            FlowLayout(spacing: 8) {
                                ForEach(Array(selectedRecipients)) { key in
                                    SelectedRecipientChip(key: key) {
                                        selectedRecipients.remove(key)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    onComplete(.cancel)
                    NSApp.stopModal(withCode: .cancel)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Encrypt") {
                    onComplete(.OK)
                    NSApp.stopModal(withCode: .OK)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedRecipients.isEmpty)
            }
        }
        .padding()
    }

    private var filteredKeys: [PGPKeyModel] {
        if searchText.isEmpty {
            return availableKeys
        }

        let query = searchText.lowercased()
        return availableKeys.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.email?.lowercased().contains(query) == true ||
            $0.shortKeyID.lowercased().contains(query)
        }
    }

    private func toggleSelection(_ key: PGPKeyModel) {
        if selectedRecipients.contains(key) {
            selectedRecipients.remove(key)
        } else {
            selectedRecipients.insert(key)
        }
    }
}

/// SwiftUI view for selecting a secret key and entering passphrase
private struct KeyPassphraseSelectionView: View {
    let secretKeys: [PGPKeyModel]
    let operation: String
    @Binding var selectedKey: PGPKeyModel?
    @Binding var passphrase: String
    let onComplete: (NSApplication.ModalResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select key for \(operation.lowercased()):")
                .font(.body)
                .foregroundStyle(.secondary)

            Picker("Key:", selection: $selectedKey) {
                Text("Select a key...").tag(nil as PGPKeyModel?)
                ForEach(secretKeys) { key in
                    Text("\(key.displayName) (\(String(key.shortKeyID.suffix(8))))")
                        .tag(key as PGPKeyModel?)
                }
            }
            .pickerStyle(.menu)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Passphrase:")
                    .font(.body)

                SecureField("Enter passphrase", text: $passphrase)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    onComplete(.cancel)
                    NSApp.stopModal(withCode: .cancel)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(operation) {
                    onComplete(.OK)
                    NSApp.stopModal(withCode: .OK)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedKey == nil || passphrase.isEmpty)
            }
        }
        .padding()
    }
}

/// Button view for selecting a recipient key
private struct RecipientRowButton: View {
    let key: PGPKeyModel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(key.displayName)
                        .font(.body)
                    if let email = key.email {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(String(key.shortKeyID.suffix(8)))
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
