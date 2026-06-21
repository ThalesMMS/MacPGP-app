import Foundation
import SwiftUI
import RNPKit

@MainActor
@Observable
final class KeyGenerationViewModel: SensitiveSessionState {
    var name: String = ""
    var email: String = ""
    var comment: String = ""
    var passphrase: String = ""
    var confirmPassphrase: String = ""
    var algorithm: KeyAlgorithm = .rsa
    var keySize: Int = 4096
    var expirationMonths: Int = 24
    var neverExpires: Bool = false
    var storeInKeychain: Bool = true

    var isGenerating: Bool = false
    var progress: Double = 0
    var errorMessage: String?
    var generatedKey: PGPKeyModel?

    private let keyringService: KeyringService
    private let generationService: KeyGenerationService
    private let keychainManager = KeychainManager.shared

    /// Bumped on lock so an in-flight generation cannot persist a key or store a
    /// passphrase after the session is locked.
    private var lockGeneration = 0

    init(keyringService: KeyringService, generationService: KeyGenerationService = .shared) {
        self.keyringService = keyringService
        self.generationService = generationService

        let preferences = PreferencesManager.shared
        self.algorithm = preferences.defaultKeyAlgorithm
        self.keySize = algorithm.supportedKeySizes.contains(preferences.defaultKeySize)
            ? preferences.defaultKeySize
            : algorithm.defaultKeySize
        self.expirationMonths = preferences.defaultKeyExpirationMonths == 0 ? 24 : preferences.defaultKeyExpirationMonths
        self.neverExpires = preferences.defaultKeyExpirationMonths == 0
        self.storeInKeychain = preferences.rememberPassphrase
    }

    var availableKeySizes: [Int] {
        algorithm.supportedKeySizes
    }

    func updateAlgorithm(_ newAlgorithm: KeyAlgorithm) {
        algorithm = newAlgorithm

        if !algorithm.supportedKeySizes.contains(keySize) {
            keySize = algorithm.defaultKeySize
        }
    }

    var isValid: Bool {
        !name.isEmpty &&
        isValidEmail &&
        !passphrase.isEmpty &&
        passphraseMatch &&
        passphraseStrength.rawValue >= PassphraseStrength.fair.rawValue
    }

    var isValidEmail: Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }

    var passphraseMatch: Bool {
        passphrase == confirmPassphrase
    }

    var passphraseStrength: PassphraseStrength {
        generationService.passphraseStrength(passphrase)
    }

    var passphraseIssues: [PassphraseValidationIssue] {
        generationService.validatePassphrase(passphrase)
    }

    func generate() async {
        guard isValid else { return }

        let generation = lockGeneration
        isGenerating = true
        progress = 0
        errorMessage = nil

        let parameters = KeyGenerationParameters(
            name: name,
            email: email,
            comment: comment.isEmpty ? nil : comment,
            passphrase: passphrase,
            algorithm: algorithm,
            keySize: keySize,
            expirationMonths: neverExpires ? nil : expirationMonths
        )

        do {
            let key = try await generationService.generateKeyAsync(with: parameters) { progressValue in
                guard self.lockGeneration == generation else { return }
                self.progress = progressValue
            }
            handleGenerationResult(.success(key), generation: generation)
        } catch let error as OperationError {
            handleGenerationResult(.failure(error), generation: generation)
        } catch {
            handleGenerationResult(.failure(.keyGenerationFailed(underlying: error)), generation: generation)
        }
    }

    private func handleGenerationResult(_ result: Result<Key, OperationError>, generation: Int) {
        // A lock during generation invalidates the run: do not persist the key or
        // store the (now-cleared) passphrase.
        guard generation == lockGeneration else { return }

        isGenerating = false

        switch result {
        case .success(let key):
            do {
                try keyringService.addKey(key)
            } catch {
                errorMessage = "Failed to save key: \(error.localizedDescription)"
                return
            }

            let model = PGPKeyModel(from: key)
            generatedKey = model

            if storeInKeychain {
                do {
                    try keychainManager.storePassphrase(passphrase, for: model)
                } catch {
                    // The key was generated and saved; only Keychain passphrase
                    // storage failed (e.g. a missing entitlement). Surface the
                    // failure without implying the passphrase was stored.
                    errorMessage = error.userFacingMessage
                }
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        name = ""
        email = ""
        comment = ""
        passphrase = ""
        confirmPassphrase = ""
        generatedKey = nil
        errorMessage = nil
        progress = 0
    }

    /// Clears passphrase fields and invalidates any in-flight generation on
    /// **Lock MacPGP**. The generated key (a public projection) and any persisted
    /// keyring/Keychain data are left intact.
    func handleLock() {
        lockGeneration &+= 1
        passphrase = ""
        confirmPassphrase = ""
        isGenerating = false
        progress = 0
        errorMessage = nil
    }
}
