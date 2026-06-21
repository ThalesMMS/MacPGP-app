import Foundation

/// Orchestrates signature verification with a tracked, cancellable task and
/// stale-result protection, so a late completion cannot update state after the
/// initiating view has gone away or a newer run has started.
@MainActor
@Observable
final class VerifyViewModel {
    var isProcessing = false
    var errorMessage: String?
    var showingError = false

    private let keyringService: KeyringService
    private let sessionState: SessionStateManager
    private let signatureService: SignatureServicing

    private var verifyTask: Task<Void, Never>?
    private var verifyRunID: UUID?

    init(
        keyringService: KeyringService,
        sessionState: SessionStateManager,
        signatureService: SignatureServicing? = nil
    ) {
        self.keyringService = keyringService
        self.sessionState = sessionState
        self.signatureService = signatureService ?? SigningService(keyringService: keyringService)
    }

    var canVerify: Bool {
        guard !isProcessing else { return false }

        switch sessionState.verifyInputMode {
        case .text:
            if sessionState.verifySignatureMode == .inline {
                return !sessionState.verifyInputText.isEmpty
            } else {
                return !sessionState.verifyInputText.isEmpty && !sessionState.verifySignatureText.isEmpty
            }
        case .file:
            if sessionState.verifySignatureMode == .inline {
                return sessionState.verifySelectedFile != nil
            } else {
                return sessionState.verifySelectedFile != nil && sessionState.verifySelectedSignatureFile != nil
            }
        }
    }

    func verify() {
        guard !isProcessing else { return }

        let inputMode = sessionState.verifyInputMode
        let signatureMode = sessionState.verifySignatureMode
        let inputText = sessionState.verifyInputText
        let signatureText = sessionState.verifySignatureText
        let selectedFile = sessionState.verifySelectedFile
        let selectedSignatureFile = sessionState.verifySelectedSignatureFile

        if inputMode == .file && selectedFile == nil {
            errorMessage = String(localized: "verify.error.no_file_selected", comment: "Error when no file is selected for verification")
            showingError = true
            return
        }

        if inputMode == .file && signatureMode == .detached && selectedSignatureFile == nil {
            errorMessage = String(localized: "verify.error.no_signature_file", comment: "Error when no detached signature file is selected")
            showingError = true
            return
        }

        let runID = UUID()
        verifyRunID = runID
        isProcessing = true
        sessionState.verifyResult = nil
        errorMessage = nil

        verifyTask = Task { [signatureService] in
            do {
                let result: VerificationResult
                switch inputMode {
                case .text:
                    if signatureMode == .inline {
                        result = try await signatureService.verifyAsync(message: inputText)
                    } else {
                        result = try await signatureService.verifyAsync(message: inputText, signature: signatureText)
                    }
                case .file:
                    guard let fileURL = selectedFile else {
                        throw OperationError.verificationFailed(underlying: nil)
                    }
                    if signatureMode == .inline {
                        result = try await signatureService.verifyAsync(file: fileURL)
                    } else {
                        result = try await signatureService.verifyAsync(file: fileURL, signatureFile: selectedSignatureFile)
                    }
                }

                try Task.checkCancellation()
                guard verifyRunID == runID else { return }
                sessionState.verifyResult = result
            } catch is CancellationError {
                // The run was superseded or cancelled; leave state to the new owner.
            } catch {
                guard verifyRunID == runID else { return }
                sessionState.verifyResult = .verificationError(reason: error.localizedDescription)
            }

            guard verifyRunID == runID else { return }
            isProcessing = false
            verifyTask = nil
        }
    }

    /// Cancels any in-flight verification and prevents its completion from updating
    /// state. Called on explicit cancel and on view disappearance.
    func cancel() {
        verifyTask?.cancel()
        verifyTask = nil
        verifyRunID = nil
        isProcessing = false
    }
}
