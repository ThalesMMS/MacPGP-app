import Foundation
import RNPKit
import Testing
@testable import MacPGP

@MainActor
@Suite("RevocationManagementView Tests")
struct RevocationManagementViewTests {
    @Test("exporter modifier is hosted by stable management content")
    func exporterModifierIsHostedByStableManagementContent() throws {
        let source = try revocationManagementSource()
        let managementStart = try #require(source.range(of: "private func managementContent")?.lowerBound)
        let formStart = try #require(source.range(of: "private func formView")?.lowerBound)
        let managementContent = source[managementStart..<formStart]

        #expect(managementContent.contains(".fileExporter("))
    }

    @Test("generated revocation certificate remains available after success transition")
    func generatedRevocationCertificateRemainsAvailableAfterSuccessTransition() async throws {
        let passphrase = "TestPassword123!"
        let key = makeSecretKey(passphrase: passphrase)
        let keyring = KeyringService(
            persistence: KeyringPersistence(
                directoryOverride: FileManager.default.temporaryDirectory
                    .appendingPathComponent("RevocationManagementViewTests-\(UUID().uuidString)", isDirectory: true)
            )
        )
        try keyring.addKey(key.rawKey)

        let viewModel = RevocationManagementViewModel(
            key: key,
            keyringService: keyring,
            onKeyUpdated: { _ in }
        )

        viewModel.generatePassphrase = passphrase
        await viewModel.generateCertificate()

        #expect(!viewModel.isProcessing)
        #expect(viewModel.isSuccess)
        #expect(viewModel.showingExportSheet)
        #expect(viewModel.exportData?.isEmpty == false)
        #expect(!viewModel.exportFileName.isEmpty)
    }

    private func revocationManagementSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MacPGP/Features/KeyDetails/RevocationManagementView.swift")

        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func makeSecretKey(passphrase: String) -> PGPKeyModel {
        let generator = KeyGenerator()
        generator.keyBitsLength = 2048
        return PGPKeyModel(from: generator.generate(for: "revocation-management@example.com", passphrase: passphrase))
    }
}
