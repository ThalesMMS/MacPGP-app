//
//  FakeSignatureService.swift
//  MacPGPTests
//
//  A controllable SignatureServicing for SignViewModel / VerifyViewModel tests
//  (issue #130): results are configurable and operations can be gated to test
//  cancellation and stale-completion deterministically.
//

import Foundation
import Testing
@testable import MacPGP

@MainActor
final class FakeSignatureService: SignatureServicing {
    var signMessageResult: Result<String, Error> = .success("SIGNED-MESSAGE")
    var signFileResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/macpgp-test-output.sig"))
    var verifyResult: Result<VerificationResult, Error> = .success(.valid(signer: nil, date: nil))

    /// When true, every operation suspends until `release()` is called.
    var gate = false
    private var continuation: CheckedContinuation<Void, Never>?

    private(set) var startedCalls = 0
    private(set) var completedCalls = 0

    func signAsync(message: String, using key: PGPKeyModel, passphrase: String, cleartext: Bool, detached: Bool, armored: Bool) async throws -> String {
        startedCalls += 1
        await gateIfNeeded()
        completedCalls += 1
        return try signMessageResult.get()
    }

    func signAsync(file: URL, using key: PGPKeyModel, passphrase: String, detached: Bool, outputURL: URL?, armored: Bool, commitGate: FileCommitGate?) async throws -> URL {
        startedCalls += 1
        await gateIfNeeded()
        completedCalls += 1
        return try signFileResult.get()
    }

    func verifyAsync(message: String) async throws -> VerificationResult {
        startedCalls += 1
        await gateIfNeeded()
        completedCalls += 1
        return try verifyResult.get()
    }

    func verifyAsync(message: String, signature: String) async throws -> VerificationResult {
        startedCalls += 1
        await gateIfNeeded()
        completedCalls += 1
        return try verifyResult.get()
    }

    func verifyAsync(file: URL) async throws -> VerificationResult {
        startedCalls += 1
        await gateIfNeeded()
        completedCalls += 1
        return try verifyResult.get()
    }

    func verifyAsync(file: URL, signatureFile: URL?) async throws -> VerificationResult {
        startedCalls += 1
        await gateIfNeeded()
        completedCalls += 1
        return try verifyResult.get()
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }

    private func gateIfNeeded() async {
        guard gate else { return }
        await withCheckedContinuation { continuation = $0 }
    }
}

@MainActor
func waitUntil(_ description: String = "condition", _ condition: @MainActor () -> Bool) async {
    for _ in 0..<400 {
        if condition() { return }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    Issue.record("Timed out waiting for \(description)")
}
