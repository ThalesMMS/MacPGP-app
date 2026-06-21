import Foundation

/// Orchestrates signing with a tracked, cancellable task, run identity, and
/// stale-result protection, plus the passphrase-cache and wrong-passphrase retry
/// behavior used by the other crypto features.
@MainActor
@Observable
final class SignViewModel: SensitiveSessionState {
    var passphrase = ""
    var showingPassphrasePrompt = false
    var isProcessing = false
    var errorMessage: String?
    var showingError = false

    private let keyringService: KeyringService
    private let sessionState: SessionStateManager
    private let signatureService: SignatureServicing
    private let passphraseCache: PassphraseCache

    private var signingTask: Task<Void, Never>?
    private var signRunID: UUID?
    /// Authorizes the in-flight file signing's output commit; invalidated on
    /// cancel or lock so a blocking backend that returns afterwards cannot
    /// promote its output.
    @ObservationIgnored private var fileCommitGate: FileCommitGate?

    init(
        keyringService: KeyringService,
        sessionState: SessionStateManager,
        signatureService: SignatureServicing? = nil,
        passphraseCache: PassphraseCache? = nil
    ) {
        self.keyringService = keyringService
        self.sessionState = sessionState
        self.signatureService = signatureService ?? SigningService(keyringService: keyringService)
        self.passphraseCache = passphraseCache ?? .shared
    }

    var signingKeys: [PGPKeyModel] {
        keyringService.signingKeys()
    }

    var signingKeyFingerprints: [String] {
        signingKeys.map(\.fingerprint)
    }

    var canSign: Bool {
        guard let signer = sessionState.signSignerKey,
              signingKeyFingerprints.contains(signer.fingerprint) else {
            return false
        }

        return (
            (sessionState.signInputMode == .text && !sessionState.signInputText.isEmpty) ||
            (sessionState.signInputMode == .file && sessionState.signSelectedFile != nil)
        )
    }

    var passphrasePromptMessage: String {
        if let key = sessionState.signSignerKey {
            return String(format: String(localized: "sign.enter_passphrase_key", comment: "Passphrase prompt for a specific signing key"), key.displayName)
        }
        return String(localized: "sign.enter_passphrase", comment: "Passphrase prompt to sign")
    }

    /// Drops the selected signer if it is no longer a usable signing key.
    func validateSelectedSigner() {
        guard let signer = sessionState.signSignerKey else { return }
        if !signingKeyFingerprints.contains(signer.fingerprint) {
            sessionState.signSignerKey = nil
        }
    }

    func promptForPassphrase() {
        guard !isProcessing else { return }

        guard sessionState.signSignerKey != nil else {
            errorMessage = String(localized: "sign.error.no_key_selected", comment: "Error when no signing key is selected")
            showingError = true
            return
        }

        if let signer = sessionState.signSignerKey,
           let cached = passphraseCache.passphrase(for: signer) {
            passphrase = cached
            sign()
            return
        }

        showingPassphrasePrompt = true
    }

    func cancelPassphrasePrompt() {
        passphrase = ""
        showingPassphrasePrompt = false
    }

    func sign() {
        guard !isProcessing else { return }

        guard !passphrase.isEmpty else {
            errorMessage = String(localized: "sign.error.passphrase_required", comment: "Error when passphrase field is empty on sign")
            showingError = true
            return
        }

        guard let key = sessionState.signSignerKey else { return }

        let inputMode = sessionState.signInputMode
        let inputText = sessionState.signInputText
        let selectedFile = sessionState.signSelectedFile
        let cleartextSignature = sessionState.signCleartextSignature
        let detachedSignature = sessionState.signDetachedSignature
        let armorOutput = sessionState.signArmorOutput
        let enteredPassphrase = passphrase

        if inputMode == .file && selectedFile == nil {
            errorMessage = String(localized: "sign.error.no_file_selected", comment: "Error when no file is selected for signing")
            showingError = true
            return
        }

        let runID = UUID()
        signRunID = runID
        let gate = FileCommitGate()
        fileCommitGate = gate
        let cacheGeneration = passphraseCache.lockGeneration
        isProcessing = true
        errorMessage = nil
        showingPassphrasePrompt = false
        sessionState.signOutputText = ""
        sessionState.signOutputFiles = []

        signingTask = Task { [signatureService, passphraseCache] in
            do {
                switch inputMode {
                case .text:
                    let signed = try await signatureService.signAsync(
                        message: inputText,
                        using: key,
                        passphrase: enteredPassphrase,
                        cleartext: cleartextSignature,
                        detached: detachedSignature,
                        armored: armorOutput
                    )
                    try Task.checkCancellation()
                    guard signRunID == runID else { return }
                    sessionState.signOutputFiles = []
                    sessionState.signOutputText = signed
                    passphraseCache.store(enteredPassphrase, for: key, lockGeneration: cacheGeneration)
                    passphrase = ""

                case .file:
                    guard let fileURL = selectedFile else {
                        throw OperationError.signingFailed(underlying: nil)
                    }
                    let outputURL = try await signatureService.signAsync(
                        file: fileURL,
                        using: key,
                        passphrase: enteredPassphrase,
                        detached: detachedSignature,
                        outputURL: nil,
                        armored: armorOutput,
                        commitGate: gate
                    )
                    try Task.checkCancellation()
                    guard signRunID == runID else { return }
                    sessionState.signOutputText = ""
                    sessionState.signOutputFiles = [outputURL]
                    passphraseCache.store(enteredPassphrase, for: key, lockGeneration: cacheGeneration)
                    passphrase = ""
                }
            } catch is CancellationError {
                // The run was superseded or cancelled; leave state to the new owner.
            } catch is SecureScopedFileAccess.CommitCancelledError {
                // Cancelled/locked before commit: no output was promoted.
            } catch {
                guard signRunID == runID else { return }
                handleSignFailure(error, attemptedPassphrase: enteredPassphrase)
            }

            guard signRunID == runID else { return }
            isProcessing = false
            signingTask = nil
        }
    }

    /// On a wrong passphrase, clears the invalid passphrase and re-prompts instead
    /// of surfacing a hard error, matching the other crypto features.
    private func handleSignFailure(_ error: Error, attemptedPassphrase: String) {
        if case OperationError.invalidPassphrase = error {
            if passphrase == attemptedPassphrase {
                passphrase = ""
            }
            showingPassphrasePrompt = true
            return
        }

        errorMessage = error.localizedDescription
        showingError = true
    }

    /// Cancels any in-flight signing and prevents its completion from updating state.
    func cancel() {
        fileCommitGate?.invalidate()
        signingTask?.cancel()
        signingTask = nil
        signRunID = nil
        isProcessing = false
    }

    /// Clears all in-memory passphrase state in response to a MacPGP lock event.
    func handleLock() {
        fileCommitGate?.invalidate()
        signingTask?.cancel()
        signingTask = nil
        signRunID = nil
        passphrase = ""
        showingPassphrasePrompt = false
        isProcessing = false
    }
}
