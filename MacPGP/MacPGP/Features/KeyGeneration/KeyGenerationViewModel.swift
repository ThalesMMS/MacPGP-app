import Foundation
import SwiftUI
import ObjectivePGP

@Observable
final class KeyGenerationViewModel {
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
    private let generationService = KeyGenerationService.shared
    private let keychainManager = KeychainManager.shared

    init(keyringService: KeyringService) {
        self.keyringService = keyringService

        let preferences = PreferencesManager.shared
        self.algorithm = preferences.defaultKeyAlgorithm
        self.keySize = preferences.defaultKeySize
        self.expirationMonths = preferences.defaultKeyExpirationMonths
    }

    var availableKeySizes: [Int] {
        algorithm.supportedKeySizes
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

        generationService.generateKeyAsync(with: parameters) { [weak self] progressValue in
            Task { @MainActor in
                self?.progress = progressValue
            }
        } completion: { [weak self] result in
            Task { @MainActor in
                self?.handleGenerationResult(result)
            }
        }
    }

    @MainActor
    private func handleGenerationResult(_ result: Result<Key, OperationError>) {
        isGenerating = false

        switch result {
        case .success(let key):
            do {
                try keyringService.addKey(key)
                let model = PGPKeyModel(from: key)
                generatedKey = model

                if storeInKeychain {
                    try keychainManager.storePassphrase(passphrase, forKeyID: model.fingerprint)
                }
            } catch {
                errorMessage = "Failed to save key: \(error.localizedDescription)"
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
}
