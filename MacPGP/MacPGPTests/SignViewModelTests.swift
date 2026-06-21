//
//  SignViewModelTests.swift
//  MacPGPTests
//
//  Coverage for issue #130: cancellable, stale-result-protected sign orchestration
//  with passphrase cache and wrong-passphrase retry.
//

import Foundation
import RNPKit
import Testing
@testable import MacPGP

@MainActor
@Suite("SignViewModel Tests")
struct SignViewModelTests {
    private static let sharedSigner: PGPKeyModel = {
        let generator = KeyGenerator()
        generator.keyBitsLength = 2048
        return PGPKeyModel(from: try! generator.generate(for: "signviewmodel-signer@example.com", passphrase: "pp"))
    }()

    private func signer() -> PGPKeyModel { Self.sharedSigner }

    private func makeCache() -> PassphraseCache {
        PassphraseCache(
            isEnabled: { true },
            timeoutMinutes: { 0 },
            now: { Date(timeIntervalSince1970: 1_000) }
        )
    }

    private func textSession(signer: PGPKeyModel) -> SessionStateManager {
        let session = SessionStateManager()
        session.signInputMode = .text
        session.signInputText = "message to sign"
        session.signSignerKey = signer
        return session
    }

    @Test("successful text signing publishes output, caches passphrase, clears field")
    func signTextSuccess() async {
        let key = signer()
        let session = textSession(signer: key)
        let fake = FakeSignatureService()
        fake.signMessageResult = .success("-----BEGIN PGP SIGNED MESSAGE-----")
        let cache = makeCache()
        let vm = SignViewModel(keyringService: KeyringService(), sessionState: session, signatureService: fake, passphraseCache: cache)
        vm.passphrase = "pp"

        vm.sign()
        await waitUntil("sign output") { !session.signOutputText.isEmpty }

        #expect(session.signOutputText == "-----BEGIN PGP SIGNED MESSAGE-----")
        #expect(vm.passphrase.isEmpty)
        #expect(cache.passphrase(for: key) == "pp")
        #expect(!vm.isProcessing)
    }

    @Test("successful file signing publishes the output file")
    func signFileSuccess() async {
        let key = signer()
        let session = SessionStateManager()
        session.signInputMode = .file
        session.signSelectedFile = URL(fileURLWithPath: "/tmp/input.txt")
        session.signSignerKey = key
        let outputURL = URL(fileURLWithPath: "/tmp/output.sig")
        let fake = FakeSignatureService()
        fake.signFileResult = .success(outputURL)
        let vm = SignViewModel(keyringService: KeyringService(), sessionState: session, signatureService: fake, passphraseCache: makeCache())
        vm.passphrase = "pp"

        vm.sign()
        await waitUntil("sign file output") { !session.signOutputFiles.isEmpty }

        #expect(session.signOutputFiles == [outputURL])
        #expect(!vm.isProcessing)
    }

    @Test("wrong passphrase clears the field and re-prompts")
    func wrongPassphraseRetries() async {
        let key = signer()
        let session = textSession(signer: key)
        let fake = FakeSignatureService()
        fake.signMessageResult = .failure(OperationError.invalidPassphrase)
        let vm = SignViewModel(keyringService: KeyringService(), sessionState: session, signatureService: fake, passphraseCache: makeCache())
        vm.passphrase = "wrong"

        vm.sign()
        await waitUntil("retry prompt") { vm.showingPassphrasePrompt }

        #expect(vm.passphrase.isEmpty)
        #expect(!vm.showingError)
        #expect(!vm.isProcessing)
    }

    @Test("non-passphrase failure surfaces an error")
    func genericFailureShowsError() async {
        let key = signer()
        let session = textSession(signer: key)
        let fake = FakeSignatureService()
        fake.signMessageResult = .failure(OperationError.signingFailed(underlying: nil))
        let vm = SignViewModel(keyringService: KeyringService(), sessionState: session, signatureService: fake, passphraseCache: makeCache())
        vm.passphrase = "pp"

        vm.sign()
        await waitUntil("error shown") { vm.showingError }

        #expect(vm.errorMessage != nil)
        #expect(!vm.showingPassphrasePrompt)
        #expect(!vm.isProcessing)
    }

    @Test("cancel prevents a late completion from updating output")
    func cancelPreventsStaleOutput() async {
        let key = signer()
        let session = textSession(signer: key)
        let fake = FakeSignatureService()
        fake.gate = true
        fake.signMessageResult = .success("STALE OUTPUT")
        let vm = SignViewModel(keyringService: KeyringService(), sessionState: session, signatureService: fake, passphraseCache: makeCache())
        vm.passphrase = "pp"

        vm.sign()
        await waitUntil("sign started") { fake.startedCalls == 1 }
        #expect(vm.isProcessing)

        vm.cancel()
        fake.release()
        await waitUntil("fake completed") { fake.completedCalls == 1 }
        for _ in 0..<5 { await Task.yield() }

        #expect(session.signOutputText.isEmpty)
        #expect(!vm.isProcessing)
    }

    @Test("signer removal clears the stale selection")
    func signerRemovalClearsSelection() {
        let key = signer()
        let session = SessionStateManager()
        session.signSignerKey = key
        // An empty keyring exposes no signing keys, so the selected signer is stale.
        let vm = SignViewModel(keyringService: KeyringService(), sessionState: session, signatureService: FakeSignatureService(), passphraseCache: makeCache())

        vm.validateSelectedSigner()
        #expect(session.signSignerKey == nil)
    }

    @Test("handleLock clears passphrase state")
    func handleLockClearsState() {
        let key = signer()
        let session = textSession(signer: key)
        let vm = SignViewModel(keyringService: KeyringService(), sessionState: session, signatureService: FakeSignatureService(), passphraseCache: makeCache())
        vm.passphrase = "secret"
        vm.showingPassphrasePrompt = true

        vm.handleLock()

        #expect(vm.passphrase.isEmpty)
        #expect(!vm.showingPassphrasePrompt)
        #expect(!vm.isProcessing)
    }
}
