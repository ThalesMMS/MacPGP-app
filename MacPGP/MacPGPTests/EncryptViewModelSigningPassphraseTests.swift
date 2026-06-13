import Foundation
import RNPKit
import Testing
@testable import MacPGP

@MainActor
@Suite("EncryptViewModel Signing Passphrase Tests")
struct EncryptViewModelSigningPassphraseTests {
    @Test("wrong signing passphrase is cleared so retry prompts again")
    func wrongSigningPassphraseRetryPromptsAgain() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncryptViewModelSigningPassphraseTests-\(UUID().uuidString)", isDirectory: true)
        let keyringDirectory = rootDirectory.appendingPathComponent("Keyring", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let keyring = KeyringService(persistence: KeyringPersistence(directoryOverride: keyringDirectory))
        let recipient = makeSecretKey(email: "recipient-\(UUID().uuidString)@example.com", passphrase: "RecipientPassphrase123!")
        let signer = makeSecretKey(email: "signer-\(UUID().uuidString)@example.com", passphrase: "SignerPassphrase123!")
        try keyring.addKey(recipient.rawKey)
        try keyring.addKey(signer.rawKey)

        let sessionState = SessionStateManager()
        sessionState.encryptInputMode = .text
        sessionState.encryptInputText = "message to encrypt and sign"
        sessionState.encryptSelectedRecipients = [recipient]
        sessionState.encryptSignerKey = signer

        let viewModel = EncryptViewModel(
            keyringService: keyring,
            sessionState: sessionState,
            notificationService: NotificationService()
        )
        viewModel.passphrase = "WrongPassphrase123!"

        viewModel.encrypt()
        await waitForEncryptionToFinish(viewModel)

        #expect(viewModel.alert != nil)
        #expect(viewModel.passphrase.isEmpty)

        viewModel.encrypt()
        await waitForPassphrasePrompt(viewModel)

        #expect(viewModel.showingPassphrasePrompt)
        #expect(viewModel.passphrase.isEmpty)
    }

    private func makeSecretKey(email: String, passphrase: String) -> PGPKeyModel {
        let generator = KeyGenerator()
        generator.keyBitsLength = 2048
        return PGPKeyModel(from: generator.generate(for: email, passphrase: passphrase))
    }

    private func waitForEncryptionToFinish(_ viewModel: EncryptViewModel) async {
        for _ in 0..<200 {
            if !viewModel.isProcessing {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        Issue.record("Timed out waiting for encryption to finish")
    }

    private func waitForPassphrasePrompt(_ viewModel: EncryptViewModel) async {
        for _ in 0..<200 {
            if viewModel.showingPassphrasePrompt {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        Issue.record("Timed out waiting for passphrase prompt")
    }
}
