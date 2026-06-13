import Foundation
import RNPKit
import Testing
@testable import MacPGP

@MainActor
@Suite("Encryption Batch Output Tests")
struct EncryptionBatchOutputTests {
    @Test("batch encryption preserves existing output and cleans only created files")
    func batchEncryptionPreservesExistingOutputAndCleansOnlyCreatedFiles() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncryptionBatchOutputTests-\(UUID().uuidString)", isDirectory: true)
        let outputDirectory = rootDirectory.appendingPathComponent("Output", isDirectory: true)
        let keyringDirectory = rootDirectory.appendingPathComponent("Keyring", isDirectory: true)

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let firstInput = rootDirectory.appendingPathComponent("first.txt")
        let secondInput = rootDirectory.appendingPathComponent("second.txt")
        try Data("first".utf8).write(to: firstInput)
        try Data("second".utf8).write(to: secondInput)

        let firstOutput = outputDirectory.appendingPathComponent("first.txt.gpg")
        let existingSecondOutput = outputDirectory.appendingPathComponent("second.txt.gpg")
        let existingOutputData = Data("existing user output".utf8)
        try existingOutputData.write(to: existingSecondOutput)

        let keyring = KeyringService(persistence: KeyringPersistence(directoryOverride: keyringDirectory))
        let recipient = makeSecretKey(email: "batch-output-\(UUID().uuidString)@example.com")
        try keyring.addKey(recipient.rawKey)

        let sessionState = SessionStateManager()
        sessionState.encryptInputMode = .file
        sessionState.encryptSelectedFiles = [firstInput, secondInput]
        sessionState.encryptSelectedRecipients = [recipient]
        sessionState.encryptOutputLocation = outputDirectory
        sessionState.encryptArmorOutput = false

        let viewModel = EncryptViewModel(
            keyringService: keyring,
            sessionState: sessionState,
            notificationService: NotificationService()
        )

        viewModel.encrypt()
        await waitForEncryptionToFinish(viewModel)

        #expect(viewModel.alert != nil)
        #expect(sessionState.encryptOutputFiles.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: firstOutput.path))
        #expect(try Data(contentsOf: existingSecondOutput) == existingOutputData)
    }

    private func makeSecretKey(email: String) -> PGPKeyModel {
        let generator = KeyGenerator()
        generator.keyBitsLength = 2048
        return PGPKeyModel(from: generator.generate(for: email, passphrase: "TestPassword123!"))
    }

    private func waitForEncryptionToFinish(_ viewModel: EncryptViewModel) async {
        for _ in 0..<200 {
            if !viewModel.isProcessing {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        Issue.record("Timed out waiting for encryption batch to finish")
    }
}
