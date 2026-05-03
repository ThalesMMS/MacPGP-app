import Foundation
import SwiftUI
import AppKit


@MainActor
@Observable
final class DecryptViewModel {
    var passphrase: String = ""
    var showingPassphrasePrompt: Bool = false
    var isProcessing: Bool = false

    var passphrasePromptKey: PGPKeyModel?
    var shouldPerformDecryptionAfterPassphrasePrompt: Bool = false

    var alert: CryptoUserFacingError?
    var showingAlert: Bool = false

    var requestOutputFolderPicker: Bool = false

    private var decryptionTask: Task<Void, Never>?
    private var decryptionRunID: UUID?
    private var passphraseRequestID: UUID?
    private var pendingDecryptFromClipboard: Bool = false
    private var pendingClipboardInput: String?

    enum DecryptInput {
        case text(String)
        case files([URL])
    }

    func currentInput() -> DecryptInput? {
        switch sessionState.decryptInputMode {
        case .text:
            let trimmed = sessionState.decryptInputText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .text(trimmed)
        case .file:
            return sessionState.decryptSelectedFiles.isEmpty ? nil : .files(sessionState.decryptSelectedFiles)
        }
    }

    func applyAutoDetection(to input: DecryptInput) {
        switch input {
        case .text(let text):
            // Minimal heuristic: treat PGP armor as text; otherwise leave as-is.
            // (Binary PGP from clipboard isn't supported by NSPasteboard string anyway.)
            if text.contains("-----BEGIN PGP") {
                sessionState.decryptInputMode = .text
            }
        case .files:
            sessionState.decryptInputMode = .file
        }
    }

    var canDecryptFromClipboard: Bool {
        guard let clipboardText = NSPasteboard.general.string(forType: .string) else {
            return false
        }

        return sessionState.decryptInputMode == .text &&
        !keyringService.secretKeys().isEmpty &&
        (sessionState.decryptAutoDetectKey || sessionState.decryptSelectedKey != nil) &&
        !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let keyringService: KeyringService
    private let sessionState: SessionStateManager
    private let notificationService: NotificationService

    private var decryptionService: EncryptionService {
        EncryptionService(keyringService: keyringService)
    }

    init(
        keyringService: KeyringService,
        sessionState: SessionStateManager,
        notificationService: NotificationService
    ) {
        self.keyringService = keyringService
        self.sessionState = sessionState
        self.notificationService = notificationService
    }

    func pasteFromClipboard() {
        if let string = NSPasteboard.general.string(forType: .string) {
            sessionState.decryptInputText = string
        }
    }

    func copyOutputToClipboard() {
        NSPasteboard.general.clearContents()
        let content: String
        if !sessionState.decryptOutputFiles.isEmpty {
            content = sessionState.decryptOutputFiles.map(\.path).joined(separator: "\n")
        } else {
            content = sessionState.decryptOutputText
        }
        NSPasteboard.general.setString(content, forType: .string)
    }

    func revealOutputFilesInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(sessionState.decryptOutputFiles)
    }

    func decryptFromClipboard() {
        guard canDecryptFromClipboard else { return }
        guard let clipboardText = NSPasteboard.general.string(forType: .string) else { return }
        guard !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        pendingClipboardInput = clipboardText

        requestPassphraseAndDecrypt(fromClipboard: true)
    }

    func requestPassphraseAndDecrypt(fromClipboard: Bool = false) {
        guard !isProcessing else { return }

        passphrase = ""
        showingPassphrasePrompt = false
        shouldPerformDecryptionAfterPassphrasePrompt = true
        pendingDecryptFromClipboard = fromClipboard
        let requestID = UUID()
        passphraseRequestID = requestID

        if sessionState.decryptAutoDetectKey {
            passphrasePromptKey = nil
        } else {
            passphrasePromptKey = sessionState.decryptSelectedKey
        }

        if let keyToUnlock = passphrasePromptKey {
            let keyID = keyToUnlock.shortKeyID
            DispatchQueue.global(qos: .userInitiated).async {
                let stored = try? KeychainManager.shared.retrievePassphrase(forKeyID: keyID)

                Task { @MainActor in
                    guard self.passphraseRequestID == requestID else { return }

                    if let stored {
                        self.passphrase = stored
                        self.showingPassphrasePrompt = false
                        self.didSubmitPassphrase()
                    } else {
                        self.showingPassphrasePrompt = true
                    }
                }
            }
        } else {
            showingPassphrasePrompt = true
        }
    }

    func didSubmitPassphrase() {
        showingPassphrasePrompt = false

        guard shouldPerformDecryptionAfterPassphrasePrompt else {
            shouldPerformDecryptionAfterPassphrasePrompt = false
            pendingDecryptFromClipboard = false
            pendingClipboardInput = nil
            passphraseRequestID = nil
            return
        }

        let fromClipboard = pendingDecryptFromClipboard
        shouldPerformDecryptionAfterPassphrasePrompt = false
        pendingDecryptFromClipboard = false
        passphraseRequestID = nil
        decrypt(fromClipboard: fromClipboard)
    }

    func cancelPassphrasePrompt() {
        passphrase = ""
        showingPassphrasePrompt = false
        pendingDecryptFromClipboard = false
        pendingClipboardInput = nil
        passphraseRequestID = nil
        shouldPerformDecryptionAfterPassphrasePrompt = false
    }

    func decrypt(fromClipboard: Bool = false) {
        switch sessionState.decryptInputMode {
        case .text:
            decryptText(fromClipboard: fromClipboard)
        case .file:
            decryptFiles()
        }
    }

    func cancel() {
        decryptionTask?.cancel()
        decryptionTask = nil
        decryptionRunID = nil
        passphraseRequestID = nil
        passphrase = ""
        showingPassphrasePrompt = false
        pendingDecryptFromClipboard = false
        pendingClipboardInput = nil
        shouldPerformDecryptionAfterPassphrasePrompt = false
        requestOutputFolderPicker = false
        isProcessing = false
    }

    func cancelDecryption() {
        decryptionTask?.cancel()
        decryptionTask = nil
        isProcessing = false
        pendingClipboardInput = nil
    }

    private func decryptText(fromClipboard: Bool) {
        notificationService.requestAuthorizationIfNeeded()

        guard !keyringService.secretKeys().isEmpty else {
            showAlert(CryptoUserFacingError(title: "Error", message: "No secret keys available for decryption"))
            pendingClipboardInput = nil
            return
        }

        let pendingInput = fromClipboard ? pendingClipboardInput : nil
        guard let encryptedText = pendingInput ?? textInput() else {
            showAlert(CryptoUserFacingError(title: "Error", message: "Please enter text to decrypt"))
            pendingClipboardInput = nil
            return
        }

        cancelDecryption()
        pendingClipboardInput = nil
        let runID = UUID()
        decryptionRunID = runID
        isProcessing = true
        alert = nil
        sessionState.decryptionProgress = 0.0
        sessionState.decryptOutputText = ""
        sessionState.decryptOutputFiles = []

        let passphrase = self.passphrase
        let shouldAutoDetectKey = sessionState.decryptAutoDetectKey
        let selectedKey = sessionState.decryptSelectedKey

        decryptionTask = Task {
            guard await MainActor.run(body: { decryptionRunID == runID }) else { return }

            defer {
                Task { @MainActor in
                    guard decryptionRunID == runID else { return }
                    isProcessing = false
                    decryptionTask = nil
                    decryptionRunID = nil
                }
            }

            do {
                let decrypted: String

                if shouldAutoDetectKey {
                    let encryptedData = Data(encryptedText.utf8)
                    let (decryptedData, _) = try await decryptionService.tryDecryptAsync(data: encryptedData, passphrase: passphrase)
                    guard let decoded = String(data: decryptedData, encoding: .utf8) else {
                        await MainActor.run {
                            guard decryptionRunID == runID else { return }
                            showAlert(CryptoUserFacingError(
                                title: "Unable to Decode Text",
                                message: "The decrypted data is not valid UTF-8 text. Use file decryption for binary output."
                            ))
                        }
                        return
                    }
                    decrypted = decoded
                } else {
                    guard let key = selectedKey else {
                        await MainActor.run {
                            guard decryptionRunID == runID else { return }
                            showAlert(CryptoUserFacingError(title: "Error", message: "Please select a decryption key"))
                        }
                        return
                    }
                    decrypted = try await decryptionService.decryptAsync(message: encryptedText, using: key, passphrase: passphrase)
                }

                try Task.checkCancellation()

                await MainActor.run {
                    guard decryptionRunID == runID else { return }
                    sessionState.decryptOutputFiles = []
                    sessionState.decryptOutputText = decrypted

                    if fromClipboard {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(decrypted, forType: .string)
                        notificationService.showSuccess(
                            title: "Decryption Successful",
                            message: "Clipboard contents have been decrypted"
                        )
                    }
                }

                await MainActor.run {
                    guard decryptionRunID == runID else { return }
                    self.passphrase = ""
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard decryptionRunID == runID else { return }
                    pendingClipboardInput = nil
                }
                // no-op
            } catch {
                await MainActor.run {
                    guard decryptionRunID == runID else { return }
                    pendingClipboardInput = nil
                    showAlert(CryptoUserFacingError.from(error))
                }
            }
        }
    }

    private func textInput() -> String? {
        guard case .text(let encryptedText) = currentInput() else { return nil }
        return encryptedText
    }

    private func decryptFiles() {
        notificationService.requestAuthorizationIfNeeded()

        guard !keyringService.secretKeys().isEmpty else {
            showAlert(CryptoUserFacingError(title: "Error", message: "No secret keys available for decryption"))
            return
        }

        guard case .files(let inputFiles) = currentInput() else {
            showAlert(CryptoUserFacingError(title: "Error", message: "Please select at least one file"))
            return
        }

        guard let outputLocation = sessionState.decryptOutputLocation else {
            showAlert(CryptoUserFacingError(title: "Error", message: "Please choose an output location"))
            return
        }

        cancelDecryption()
        let runID = UUID()
        decryptionRunID = runID
        isProcessing = true
        alert = nil
        sessionState.decryptionProgress = 0.0
        sessionState.decryptOutputText = ""
        sessionState.decryptOutputFiles = []

        let passphrase = self.passphrase
        let shouldAutoDetectKey = sessionState.decryptAutoDetectKey
        let selectedKey = sessionState.decryptSelectedKey

        decryptionTask = Task {
            guard await MainActor.run(body: { decryptionRunID == runID }) else { return }

            defer {
                Task { @MainActor in
                    guard decryptionRunID == runID else { return }
                    isProcessing = false
                    decryptionTask = nil
                    decryptionRunID = nil
                }
            }

            var produced: [URL] = []
            do {
                for (index, file) in inputFiles.enumerated() {
                    try Task.checkCancellation()

                    let progressPerFile: Double = 1.0 / Double(max(inputFiles.count, 1))
                    let fileBase = Double(index) * progressPerFile

                    let outputURL: URL
                    if shouldAutoDetectKey {
                        let (url, _) = try await decryptionService.tryDecryptAsync(
                            file: file,
                            passphrase: passphrase,
                            outputURL: outputLocation,
                            progressCallback: { [weak self] fileProgress in
                                Task { @MainActor [weak self] in
                                    guard let self else { return }
                                    guard self.decryptionRunID == runID else { return }
                                    self.sessionState.decryptionProgress = min(1.0, fileBase + fileProgress * progressPerFile)
                                }
                            }
                        )
                        outputURL = url
                    } else {
                        guard let key = selectedKey else {
                            await MainActor.run {
                                guard decryptionRunID == runID else { return }
                                showAlert(CryptoUserFacingError(title: "Error", message: "Please select a decryption key"))
                            }
                            return
                        }
                        outputURL = try await decryptionService.decryptAsync(
                            file: file,
                            using: key,
                            passphrase: passphrase,
                            outputURL: outputLocation,
                            progressCallback: { [weak self] fileProgress in
                                Task { @MainActor [weak self] in
                                    guard let self else { return }
                                    guard self.decryptionRunID == runID else { return }
                                    self.sessionState.decryptionProgress = min(1.0, fileBase + fileProgress * progressPerFile)
                                }
                            }
                        )
                    }

                    produced.append(outputURL)
                    await MainActor.run {
                        guard decryptionRunID == runID else { return }
                        sessionState.decryptOutputFiles = produced
                    }
                }

                await MainActor.run {
                    guard decryptionRunID == runID else { return }
                    sessionState.decryptionProgress = 1.0
                    sessionState.decryptOutputFiles = produced
                }

                await MainActor.run {
                    guard decryptionRunID == runID else { return }
                    self.passphrase = ""
                }
            } catch is CancellationError {
                let shouldCleanUp = await MainActor.run(body: { decryptionRunID == runID })
                if shouldCleanUp {
                    CryptoPartialOutputCleanup.removeFiles(produced)
                }
                await MainActor.run {
                    guard decryptionRunID == runID else { return }
                    sessionState.decryptOutputFiles = []
                }
            } catch {
                let shouldCleanUp = await MainActor.run(body: { decryptionRunID == runID })
                if shouldCleanUp {
                    CryptoPartialOutputCleanup.removeFiles(produced)
                }
                await MainActor.run {
                    guard decryptionRunID == runID else { return }
                    sessionState.decryptOutputFiles = []
                    showAlert(CryptoUserFacingError.from(error))
                }
            }
        }
    }

    func requestChoosingOutputLocation() {
        requestOutputFolderPicker = true
    }

    func didChooseOutputLocation(_ url: URL?) {
        requestOutputFolderPicker = false
        if let url {
            sessionState.decryptOutputLocation = url
        }
    }

    private func showAlert(_ alert: CryptoUserFacingError) {
        self.alert = alert
        showingAlert = true
    }
}
