//
//  VerifyViewModelTests.swift
//  MacPGPTests
//
//  Coverage for issue #130: cancellable, stale-result-protected verify orchestration.
//

import Foundation
import Testing
@testable import MacPGP

@MainActor
@Suite("VerifyViewModel Tests")
struct VerifyViewModelTests {
    private func textInlineSession() -> SessionStateManager {
        let session = SessionStateManager()
        session.verifyInputMode = .text
        session.verifySignatureMode = .inline
        session.verifyInputText = "signed message"
        return session
    }

    @Test("successful verification publishes the result")
    func verifySuccess() async {
        let session = textInlineSession()
        let fake = FakeSignatureService()
        fake.verifyResult = .success(.valid(signer: nil, date: nil))
        let vm = VerifyViewModel(keyringService: KeyringService(), sessionState: session, signatureService: fake)

        vm.verify()
        await waitUntil("verify result") { session.verifyResult != nil }

        #expect(session.verifyResult?.outcome == .valid)
        #expect(!vm.isProcessing)
    }

    @Test("verification failure publishes an error result")
    func verifyFailure() async {
        let session = textInlineSession()
        let fake = FakeSignatureService()
        fake.verifyResult = .failure(OperationError.verificationFailed(underlying: nil))
        let vm = VerifyViewModel(keyringService: KeyringService(), sessionState: session, signatureService: fake)

        vm.verify()
        await waitUntil("verify error result") { session.verifyResult != nil }

        #expect(session.verifyResult?.outcome == .error)
        #expect(!vm.isProcessing)
    }

    @Test("cancel prevents a late completion from updating state")
    func cancelPreventsStaleResult() async {
        let session = textInlineSession()
        let fake = FakeSignatureService()
        fake.gate = true
        fake.verifyResult = .success(.valid(signer: nil, date: nil))
        let vm = VerifyViewModel(keyringService: KeyringService(), sessionState: session, signatureService: fake)

        vm.verify()
        await waitUntil("verify started") { fake.startedCalls == 1 }
        #expect(vm.isProcessing)

        vm.cancel()
        fake.release()
        await waitUntil("fake completed") { fake.completedCalls == 1 }
        for _ in 0..<5 { await Task.yield() }

        #expect(session.verifyResult == nil)
        #expect(!vm.isProcessing)
    }

    @Test("missing file input is reported without starting a task")
    func missingFileInput() {
        let session = SessionStateManager()
        session.verifyInputMode = .file
        session.verifySignatureMode = .inline
        session.verifySelectedFile = nil
        let fake = FakeSignatureService()
        let vm = VerifyViewModel(keyringService: KeyringService(), sessionState: session, signatureService: fake)

        vm.verify()
        #expect(vm.showingError)
        #expect(fake.startedCalls == 0)
    }
}
