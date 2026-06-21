import Foundation

/// Injectable seam over the async signing and verification operations used by
/// `SignViewModel` and `VerifyViewModel`. Injecting a protocol (rather than the
/// concrete `SigningService`) lets the orchestration be unit-tested with a
/// controllable service for cancellation, stale-completion, and retry behavior.
protocol SignatureServicing {
    func signAsync(
        message: String,
        using key: PGPKeyModel,
        passphrase: String,
        cleartext: Bool,
        detached: Bool,
        armored: Bool
    ) async throws -> String

    func signAsync(
        file: URL,
        using key: PGPKeyModel,
        passphrase: String,
        detached: Bool,
        outputURL: URL?,
        armored: Bool,
        commitGate: FileCommitGate?
    ) async throws -> URL

    func verifyAsync(message: String) async throws -> VerificationResult
    func verifyAsync(message: String, signature: String) async throws -> VerificationResult
    func verifyAsync(file: URL) async throws -> VerificationResult
    func verifyAsync(file: URL, signatureFile: URL?) async throws -> VerificationResult
}

extension SigningService: SignatureServicing {}
