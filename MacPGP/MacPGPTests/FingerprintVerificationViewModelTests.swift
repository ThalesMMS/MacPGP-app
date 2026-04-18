import Foundation
import Testing
@testable import MacPGP

@MainActor
@Suite("Fingerprint Verification View Model Tests")
struct FingerprintVerificationViewModelTests {
    private struct IsolatedKeyring {
        let service: KeyringService
        let cleanup: () -> Void
    }

    private func makeIsolatedKeyring() -> IsolatedKeyring {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FingerprintVerificationViewModelTests-\(UUID().uuidString)", isDirectory: true)
        let keyringDirectory = rootDirectory.appendingPathComponent("Keyring", isDirectory: true)

        return IsolatedKeyring(
            service: KeyringService(persistence: KeyringPersistence(directoryOverride: keyringDirectory)),
            cleanup: { try? FileManager.default.removeItem(at: rootDirectory) }
        )
    }

    @Test("Verification stays disabled until a matching fingerprint is provided")
    func testCanMarkAsVerifiedRequiresMatchingFingerprint() {
        let isolatedKeyring = makeIsolatedKeyring()
        defer { isolatedKeyring.cleanup() }

        let keyringService = isolatedKeyring.service
        let previewKey = PGPKeyModel.preview
        let viewModel = FingerprintVerificationViewModel(key: previewKey, keyringService: keyringService)

        #expect(!viewModel.canMarkAsVerified)

        viewModel.comparisonFingerprint = "DEAD BEEF"
        #expect(!viewModel.canMarkAsVerified)

        viewModel.comparisonFingerprint = previewKey.formattedFingerprint
        #expect(viewModel.fingerprintsMatch)
        #expect(viewModel.canMarkAsVerified)
    }

    @Test("Already verified keys stay locked")
    func testCanMarkAsVerifiedStaysFalseForVerifiedKeys() {
        let isolatedKeyring = makeIsolatedKeyring()
        defer { isolatedKeyring.cleanup() }

        let keyringService = isolatedKeyring.service
        let verifiedKey = PGPKeyModel(
            from: PGPKeyModel.preview.rawKey,
            isVerified: true,
            verificationDate: Date(),
            verificationMethod: .trusted
        )
        let viewModel = FingerprintVerificationViewModel(key: verifiedKey, keyringService: keyringService)

        viewModel.comparisonFingerprint = verifiedKey.formattedFingerprint

        #expect(viewModel.fingerprintsMatch)
        #expect(!viewModel.canMarkAsVerified)
    }

    @Test("markAsVerified sets errorMessage and does not succeed when fingerprints do not match")
    func testMarkAsVerifiedFailsWhenFingerprintsDoNotMatch() {
        let isolatedKeyring = makeIsolatedKeyring()
        defer { isolatedKeyring.cleanup() }

        let keyringService = isolatedKeyring.service
        let previewKey = PGPKeyModel.preview
        let viewModel = FingerprintVerificationViewModel(key: previewKey, keyringService: keyringService)

        // Provide a non-matching fingerprint
        viewModel.comparisonFingerprint = "DEAD BEEF CAFE"

        viewModel.markAsVerified()

        #expect(!viewModel.isSuccess)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.errorMessage == "Paste a matching fingerprint before marking this key as verified.")
    }

    @Test("markAsVerified sets errorMessage when comparison fingerprint is empty")
    func testMarkAsVerifiedFailsWhenComparisonFingerprintIsEmpty() {
        let isolatedKeyring = makeIsolatedKeyring()
        defer { isolatedKeyring.cleanup() }

        let keyringService = isolatedKeyring.service
        let previewKey = PGPKeyModel.preview
        let viewModel = FingerprintVerificationViewModel(key: previewKey, keyringService: keyringService)

        // No comparison fingerprint set (empty by default)
        #expect(viewModel.comparisonFingerprint.isEmpty)

        viewModel.markAsVerified()

        #expect(!viewModel.isSuccess)
        #expect(viewModel.errorMessage == "Paste a matching fingerprint before marking this key as verified.")
    }

    @Test("fingerprintsMatch is false when comparison fingerprint is empty")
    func testFingerprintsMatchFalseForEmptyComparison() {
        let isolatedKeyring = makeIsolatedKeyring()
        defer { isolatedKeyring.cleanup() }

        let keyringService = isolatedKeyring.service
        let previewKey = PGPKeyModel.preview
        let viewModel = FingerprintVerificationViewModel(key: previewKey, keyringService: keyringService)

        #expect(!viewModel.fingerprintsMatch)
        #expect(!viewModel.canMarkAsVerified)
    }

    @Test("markAsVerified succeeds when the pasted fingerprint matches exactly")
    func testMarkAsVerifiedSucceedsWhenFingerprintsMatch() throws {
        let isolatedKeyring = makeIsolatedKeyring()
        defer { isolatedKeyring.cleanup() }

        let keyringService = isolatedKeyring.service
        let previewKey = PGPKeyModel.preview
        try keyringService.addKey(previewKey.rawKey)

        let viewModel = FingerprintVerificationViewModel(key: previewKey, keyringService: keyringService)
        viewModel.comparisonFingerprint = previewKey.fingerprint

        viewModel.markAsVerified()

        #expect(viewModel.isSuccess)
        #expect(viewModel.errorMessage == nil)
        #expect(keyringService.key(withFingerprint: previewKey.fingerprint)?.isVerified == true)
    }

    @Test("editing comparisonFingerprint clears the stale verification prompt")
    func testEditingComparisonFingerprintClearsErrorMessage() {
        let isolatedKeyring = makeIsolatedKeyring()
        defer { isolatedKeyring.cleanup() }

        let keyringService = isolatedKeyring.service
        let previewKey = PGPKeyModel.preview
        let viewModel = FingerprintVerificationViewModel(key: previewKey, keyringService: keyringService)

        viewModel.markAsVerified()
        #expect(viewModel.errorMessage == "Paste a matching fingerprint before marking this key as verified.")

        viewModel.comparisonFingerprint = "ABCD"

        #expect(viewModel.errorMessage == nil)
    }

    @Test("fingerprintsMatch ignores whitespace, separators, and non-hex characters")
    func testFingerprintsMatchNormalizesPastedFingerprintNoise() {
        let isolatedKeyring = makeIsolatedKeyring()
        defer { isolatedKeyring.cleanup() }

        let keyringService = isolatedKeyring.service
        let previewKey = PGPKeyModel.preview
        let viewModel = FingerprintVerificationViewModel(key: previewKey, keyringService: keyringService)

        let noisyFingerprint = previewKey.formattedFingerprint
            .lowercased()
            .replacingOccurrences(of: " ", with: " - \n\t ")
            + " xyz"
        viewModel.comparisonFingerprint = noisyFingerprint

        #expect(viewModel.fingerprintsMatch)
        #expect(viewModel.canMarkAsVerified)
    }
}
