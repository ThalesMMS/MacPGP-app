import Foundation
import SwiftUI
import Security

@MainActor
@Observable
final class EncryptViewModel {
    var passphrase: String = ""
    var showingPassphrasePrompt: Bool = false
    var isProcessing: Bool = false

    var requestOutputFolderPicker: Bool = false

    var alert: CryptoUserFacingError?
    var showingAlert: Bool = false

    private let keyringService: KeyringService
    private let sessionState: SessionStateManager
    private let notificationService: NotificationService

    private var encryptionTask: Task<Void, Never>?
    private var encryptionRunID: UUID?
    private var passphraseRequestID: UUID?
    private var pendingAction: PendingAction?

    private enum PendingAction {
        case clipboard
        case text
        case files
    }

    @ObservationIgnored private lazy var encryptionService = EncryptionService(keyringService: keyringService)

    init(
        keyringService: KeyringService,
        sessionState: SessionStateManager,
        notificationService: NotificationService
    ) {
        self.keyringService = keyringService
        self.sessionState = sessionState
        self.notificationService = notificationService
    }

    var canEncryptFromClipboard: Bool {
        !sessionState.encryptSelectedRecipients.isEmpty &&
        NSPasteboard.general.string(forType: .string) != nil
    }

    func requestChoosingOutputLocation() {
        requestOutputFolderPicker = true
    }

    func didChooseOutputLocation(_ url: URL?) {
        defer { requestOutputFolderPicker = false }
        guard let url else { return }
        sessionState.encryptOutputLocation = url
    }

    func encryptFromClipboard() {
        notificationService.requestAuthorizationIfNeeded()

        guard let clipboardText = NSPasteboard.general.string(forType: .string),
              !clipboardText.isEmpty else {
            showAlert(CryptoUserFacingError(title: "Error", message: "Clipboard is empty or does not contain text"))
            return
        }

        if let signerKey = sessionState.encryptSignerKey, passphrase.isEmpty {
            retrieveSigningPassphraseIfNeeded(for: signerKey, pending: .clipboard) { [weak self] in
                self?.encryptFromClipboard()
            }
            return
        }

        cancelEncryption()
        let runID = UUID()
        encryptionRunID = runID
        isProcessing = true
        alert = nil
        sessionState.encryptOutputText = ""
        sessionState.encryptOutputFiles = []

        let recipients = Array(sessionState.encryptSelectedRecipients)
        let signer = sessionState.encryptSignerKey
        let signingPassphrase = passphrase.isEmpty ? nil : passphrase
        let armored = sessionState.encryptArmorOutput
        encryptionTask = Task {
            guard await MainActor.run(body: { encryptionRunID == runID }) else { return }

            defer {
                Task { @MainActor in
                    guard encryptionRunID == runID else { return }
                    isProcessing = false
                    encryptionTask = nil
                    encryptionRunID = nil
                }
            }

            do {
                let encrypted = try await encryptionService.encryptAsync(
                    message: clipboardText,
                    for: recipients,
                    signedBy: signer,
                    passphrase: signingPassphrase,
                    armored: armored
                )

                try Task.checkCancellation()

                await MainActor.run {
                    guard encryptionRunID == runID else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(encrypted, forType: .string)

                    notificationService.showSuccess(
                        title: "Encryption Successful",
                        message: "Clipboard contents have been encrypted"
                    )

                    sessionState.encryptOutputFiles = []
                    sessionState.encryptOutputText = encrypted
                }

                await MainActor.run {
                    guard encryptionRunID == runID else { return }
                    passphrase = ""
                }
            } catch is CancellationError {
                // no-op
            } catch {
                await MainActor.run {
                    guard encryptionRunID == runID else { return }
                    showAlert(CryptoUserFacingError.from(error))
                }
            }
        }
    }

    func encrypt() {
        switch sessionState.encryptInputMode {
        case .text:
            encryptText()
        case .file:
            encryptFiles()
        }
    }

    func didSubmitPassphrase() {
        showingPassphrasePrompt = false
        passphraseRequestID = nil

        let action = pendingAction
        pendingAction = nil

        switch action {
        case .clipboard:
            encryptFromClipboard()
        case .text:
            encryptText()
        case .files:
            encryptFiles()
        case nil:
            encrypt()
        }
    }

    func cancelPassphrasePrompt() {
        passphrase = ""
        showingPassphrasePrompt = false
        passphraseRequestID = nil
        pendingAction = nil
    }

    func cancelEncryption() {
        encryptionTask?.cancel()
        encryptionTask = nil
        isProcessing = false
    }

    private func encryptText() {
        notificationService.requestAuthorizationIfNeeded()

        guard !sessionState.encryptSelectedRecipients.isEmpty else {
            showAlert(CryptoUserFacingError(title: "Error", message: "Please select at least one recipient"))
            return
        }

        guard !sessionState.encryptInputText.isEmpty else {
            showAlert(CryptoUserFacingError(title: "Error", message: "Please enter text to encrypt"))
            return
        }

        if let signerKey = sessionState.encryptSignerKey, passphrase.isEmpty {
            retrieveSigningPassphraseIfNeeded(for: signerKey, pending: .text) { [weak self] in
                self?.encryptText()
            }
            return
        }

        cancelEncryption()
        let runID = UUID()
        encryptionRunID = runID
        isProcessing = true
        alert = nil
        sessionState.encryptOutputText = ""
        sessionState.encryptOutputFiles = []

        let message = sessionState.encryptInputText
        let recipients = Array(sessionState.encryptSelectedRecipients)
        let signer = sessionState.encryptSignerKey
        let signingPassphrase = passphrase.isEmpty ? nil : passphrase
        let armored = sessionState.encryptArmorOutput
        encryptionTask = Task {
            guard await MainActor.run(body: { encryptionRunID == runID }) else { return }

            defer {
                Task { @MainActor in
                    guard encryptionRunID == runID else { return }
                    isProcessing = false
                    encryptionTask = nil
                    encryptionRunID = nil
                }
            }

            do {
                let encrypted = try await encryptionService.encryptAsync(
                    message: message,
                    for: recipients,
                    signedBy: signer,
                    passphrase: signingPassphrase,
                    armored: armored
                )

                try Task.checkCancellation()

                await MainActor.run {
                    guard encryptionRunID == runID else { return }
                    sessionState.encryptOutputFiles = []
                    sessionState.encryptOutputText = encrypted
                }

                await MainActor.run {
                    guard encryptionRunID == runID else { return }
                    passphrase = ""
                }
            } catch is CancellationError {
                // no-op
            } catch {
                await MainActor.run {
                    guard encryptionRunID == runID else { return }
                    showAlert(CryptoUserFacingError.from(error))
                }
            }
        }
    }

    private func encryptFiles() {
        notificationService.requestAuthorizationIfNeeded()

        guard !sessionState.encryptSelectedRecipients.isEmpty else {
            showAlert(CryptoUserFacingError(title: "Error", message: "Please select at least one recipient"))
            return
        }

        let inputFiles = sessionState.encryptSelectedFiles
        guard !inputFiles.isEmpty else {
            showAlert(CryptoUserFacingError(title: "Error", message: "Please select at least one file"))
            return
        }

        if let signerKey = sessionState.encryptSignerKey, passphrase.isEmpty {
            retrieveSigningPassphraseIfNeeded(for: signerKey, pending: .files) { [weak self] in
                self?.encryptFiles()
            }
            return
        }

        cancelEncryption()
        let runID = UUID()
        encryptionRunID = runID
        isProcessing = true
        alert = nil
        sessionState.encryptionProgress = 0.0
        sessionState.encryptOutputText = ""
        sessionState.encryptOutputFiles = []

        let outputLocation = sessionState.encryptOutputLocation
        let recipients = Array(sessionState.encryptSelectedRecipients)
        let signer = sessionState.encryptSignerKey
        let usePassphrase = passphrase.isEmpty ? nil : passphrase
        let armored = sessionState.encryptArmorOutput

        encryptionTask = Task {
            guard await MainActor.run(body: { encryptionRunID == runID }) else { return }

            defer {
                Task { @MainActor in
                    guard encryptionRunID == runID else { return }
                    isProcessing = false
                    encryptionTask = nil
                    encryptionRunID = nil
                }
            }

            var produced: [URL] = []
            do {
                for (index, file) in inputFiles.enumerated() {
                    try Task.checkCancellation()

                    let progressPerFile: Double = 1.0 / Double(max(inputFiles.count, 1))
                    let fileBase = Double(index) * progressPerFile

                    let outputURL = try await encryptionService.encryptAsync(
                        file: file,
                        for: recipients,
                        signedBy: signer,
                        passphrase: usePassphrase,
                        outputURL: outputLocation,
                        armored: armored,
                        progressCallback: { [weak self] fileProgress in
                            Task { @MainActor [weak self] in
                                guard let self else { return }
                                guard self.encryptionRunID == runID else { return }
                                self.sessionState.encryptionProgress = min(1.0, fileBase + fileProgress * progressPerFile)
                            }
                        }
                    )

                    produced.append(outputURL)
                    await MainActor.run {
                        guard encryptionRunID == runID else { return }
                        sessionState.encryptOutputFiles = produced
                    }
                }

                await MainActor.run {
                    guard encryptionRunID == runID else { return }
                    sessionState.encryptionProgress = 1.0
                    sessionState.encryptOutputFiles = produced
                }

                await MainActor.run {
                    guard encryptionRunID == runID else { return }
                    passphrase = ""
                }
            } catch is CancellationError {
                let shouldCleanUp = await MainActor.run(body: { encryptionRunID == runID })
                if shouldCleanUp {
                    CryptoPartialOutputCleanup.removeFiles(produced)
                }
                await MainActor.run {
                    guard encryptionRunID == runID else { return }
                    sessionState.encryptOutputFiles = []
                }
            } catch {
                let shouldCleanUp = await MainActor.run(body: { encryptionRunID == runID })
                if shouldCleanUp {
                    CryptoPartialOutputCleanup.removeFiles(produced)
                }
                await MainActor.run {
                    guard encryptionRunID == runID else { return }
                    sessionState.encryptOutputFiles = []
                    showAlert(CryptoUserFacingError.from(error))
                }
            }
        }
    }

    func copyOutputToClipboard() {
        NSPasteboard.general.clearContents()
        let content: String
        if !sessionState.encryptOutputFiles.isEmpty {
            content = sessionState.encryptOutputFiles
                .map { $0.path(percentEncoded: false) }
                .joined(separator: "\n")
        } else {
            content = sessionState.encryptOutputText
        }
        NSPasteboard.general.setString(content, forType: .string)
    }

    private func retrieveSigningPassphraseIfNeeded(
        for signerKey: PGPKeyModel,
        pending action: PendingAction,
        resume: @escaping () -> Void
    ) {
        showingPassphrasePrompt = false
        let requestID = UUID()
        passphraseRequestID = requestID
        let keyID = signerKey.shortKeyID

        DispatchQueue.global(qos: .userInitiated).async {
            let stored = try? KeychainManager.shared.retrievePassphrase(forKeyID: keyID)

            Task { @MainActor [weak self] in
                guard let self, self.passphraseRequestID == requestID else { return }
                self.passphraseRequestID = nil

                if let stored {
                    self.passphrase = stored
                    resume()
                } else {
                    self.pendingAction = action
                    self.showingPassphrasePrompt = true
                }
            }
        }
    }

    private func showAlert(_ alert: CryptoUserFacingError) {
        self.alert = alert
        showingAlert = true
    }
}
