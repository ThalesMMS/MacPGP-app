import Testing
import RNPKit
@testable import MacPGP

@Suite("Shared model helpers")
struct SharedModelTests {
    @Test("KeyIdentity parses name, comment, and email")
    func keyIdentityParsesNameCommentAndEmail() {
        let identity = KeyIdentity.parse(from: "Ada Lovelace (Work) <ada@example.com>")

        #expect(identity.name == "Ada Lovelace")
        #expect(identity.email == "ada@example.com")
        #expect(identity.comment == "Work")
        #expect(identity.displayString == "Ada Lovelace (Work) <ada@example.com>")
        #expect(identity.shortDisplayString == "Ada Lovelace")
    }

    @Test("KeyIdentity parses plain email user IDs")
    func keyIdentityParsesPlainEmail() {
        let identity = KeyIdentity.parse(from: "ada@example.com")

        #expect(identity.name == "")
        #expect(identity.email == "ada@example.com")
        #expect(identity.comment == nil)
        #expect(identity.shortDisplayString == "ada@example.com")
    }

    @Test("KeyAlgorithm maps RNP public key algorithms")
    func keyAlgorithmMapsRNPAlgorithms() {
        #expect(KeyAlgorithm.from(publicKeyAlgorithm: .rsa) == .rsa)
        #expect(KeyAlgorithm.from(publicKeyAlgorithm: .ecdsa) == .ecdsa)
        #expect(KeyAlgorithm.from(publicKeyAlgorithm: .eddsa) == .eddsa)
        #expect(KeyAlgorithm.from(publicKeyAlgorithm: .dsa) == .dsa)
        #expect(KeyAlgorithm.from(publicKeyAlgorithm: .elgamal) == .elgamal)
        #expect(KeyAlgorithm.from(publicKeyAlgorithm: .ecdh) == .unknown)
    }

    @Test("PGP key capability helpers require valid encryption and signing state")
    func capabilityHelpersRequireValidKeyState() {
        #expect(CapabilityProbe(canEncrypt: true).isUsableForEncryption)
        #expect(!CapabilityProbe(isExpired: true, canEncrypt: true).isUsableForEncryption)
        #expect(!CapabilityProbe(isRevoked: true, canEncrypt: true).isUsableForEncryption)
        #expect(!CapabilityProbe(canEncrypt: false).isUsableForEncryption)

        #expect(CapabilityProbe(isSecretKey: true, canSign: true).isUsableForSigning)
        #expect(!CapabilityProbe(isSecretKey: false, canSign: true).isUsableForSigning)
        #expect(!CapabilityProbe(isSecretKey: true, isExpired: true, canSign: true).isUsableForSigning)
        #expect(!CapabilityProbe(isSecretKey: true, isRevoked: true, canSign: true).isUsableForSigning)
        #expect(!CapabilityProbe(isSecretKey: true, canSign: false).isUsableForSigning)
    }
}

private struct CapabilityProbe: PGPKeyCapabilityProviding {
    var isSecretKey = false
    var isExpired = false
    var isRevoked = false
    var canEncrypt = false
    var canSign = false
}
