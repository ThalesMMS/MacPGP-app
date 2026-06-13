import Foundation
import RNPKit
import Testing
@testable import MacPGP

@MainActor
@Suite("Crypto Run Lifecycle Tests")
struct CryptoRunLifecycleTests {
    @Test("decrypt cancel removes partial batch outputs")
    func decryptCancelRemovesPartialBatchOutputs() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CryptoRunLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        let inputDirectory = rootDirectory.appendingPathComponent("Input", isDirectory: true)
        let encryptedDirectory = rootDirectory.appendingPathComponent("Encrypted", isDirectory: true)
        let outputDirectory = rootDirectory.appendingPathComponent("Output", isDirectory: true)
        let keyringDirectory = rootDirectory.appendingPathComponent("Keyring", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: encryptedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let keyring = KeyringService(persistence: KeyringPersistence(directoryOverride: keyringDirectory))
        let key = makeSecretKey(email: "cancel-\(UUID().uuidString)@example.com", passphrase: "CancelPassphrase123!")
        try keyring.addKey(key.rawKey)

        let service = EncryptionService(keyringService: keyring)
        let encryptedFiles = try (0..<20).map { index in
            let inputFile = inputDirectory.appendingPathComponent("plain-\(index).txt")
            let payload = Data(repeating: UInt8(index), count: 256 * 1024)
            try payload.write(to: inputFile)
            return try service.encrypt(file: inputFile, for: [key], outputURL: encryptedDirectory, armored: false)
        }
        let expectedOutputs = (0..<20).map { index in
            outputDirectory.appendingPathComponent("plain-\(index).txt")
        }

        let sessionState = SessionStateManager()
        sessionState.decryptInputMode = .file
        sessionState.decryptSelectedFiles = encryptedFiles
        sessionState.decryptOutputLocation = outputDirectory
        sessionState.decryptAutoDetectKey = false
        sessionState.decryptSelectedKey = key

        let viewModel = DecryptViewModel(
            keyringService: keyring,
            sessionState: sessionState,
            notificationService: NotificationService()
        )
        viewModel.passphrase = "CancelPassphrase123!"

        viewModel.decrypt()
        await waitForFirstOutput(sessionState)

        viewModel.cancel()
        await waitForDecryptionToFinish(viewModel)

        #expect(sessionState.decryptOutputFiles.isEmpty)
        #expect(expectedOutputs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test("encrypt ignores duplicate submission while processing")
    func encryptIgnoresDuplicateSubmissionWhileProcessing() throws {
        let keyring = KeyringService(
            persistence: KeyringPersistence(
                directoryOverride: FileManager.default.temporaryDirectory
                    .appendingPathComponent("CryptoRunLifecycleTests-\(UUID().uuidString)", isDirectory: true)
            )
        )
        let key = makeSecretKey(email: "duplicate-\(UUID().uuidString)@example.com", passphrase: "DuplicatePassphrase123!")
        try keyring.addKey(key.rawKey)

        let sessionState = SessionStateManager()
        sessionState.encryptInputMode = .text
        sessionState.encryptInputText = "new message"
        sessionState.encryptSelectedRecipients = [key]
        sessionState.encryptOutputText = "existing output"

        let viewModel = EncryptViewModel(
            keyringService: keyring,
            sessionState: sessionState,
            notificationService: NotificationService()
        )
        viewModel.isProcessing = true

        viewModel.encrypt()

        #expect(viewModel.isProcessing)
        #expect(sessionState.encryptOutputText == "existing output")
    }

    private func makeSecretKey(email: String, passphrase: String) -> PGPKeyModel {
        let generator = KeyGenerator()
        generator.keyBitsLength = 2048
        return PGPKeyModel(from: generator.generate(for: email, passphrase: passphrase))
    }

    private func waitForFirstOutput(_ sessionState: SessionStateManager) async {
        for _ in 0..<300 {
            if !sessionState.decryptOutputFiles.isEmpty {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        Issue.record("Timed out waiting for first decrypted output")
    }

    private func waitForDecryptionToFinish(_ viewModel: DecryptViewModel) async {
        for _ in 0..<300 {
            if !viewModel.isProcessing {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        Issue.record("Timed out waiting for decryption to finish")
    }
}
