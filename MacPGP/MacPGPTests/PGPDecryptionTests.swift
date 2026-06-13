//
//  PGPDecryptionTests.swift
//  MacPGPTests
//

import Foundation
import RNPKit
import Testing
@testable import MacPGP

@Suite("PGPDecryption Tests")
struct PGPDecryptionTests {

    @Test("decrypt returns plaintext with a matching secret key")
    func testDecryptWithMatchingSecretKey() throws {
        let key = makeKey(email: "recipient@test.local", passphrase: "recipient-pass")
        let plaintext = Data("shared decrypt plaintext".utf8)
        let encrypted = try RNP.encrypt(plaintext, addSignature: false, using: [key])

        let decrypted = try PGPDecryption.decrypt(
            data: encrypted,
            using: key,
            passphrase: "recipient-pass"
        )

        #expect(decrypted == plaintext)
    }

    @Test("decrypt with any secret key returns the key that succeeds")
    func testDecryptWithAnySecretKeyReturnsMatchingKey() throws {
        let unrelatedKey = makeKey(email: "unrelated@test.local", passphrase: "unrelated-pass")
        let recipientKey = makeKey(email: "recipient@test.local", passphrase: "recipient-pass")
        let plaintext = Data("shared decrypt key selection".utf8)
        let encrypted = try RNP.encrypt(plaintext, addSignature: false, using: [recipientKey])

        let result = try PGPDecryption.decrypt(
            data: encrypted,
            usingAnySecretKeyIn: [unrelatedKey, recipientKey],
            passphrase: "recipient-pass"
        )

        #expect(result.decryptedData == plaintext)
        #expect(result.key.fingerprint == recipientKey.fingerprint)
    }

    @Test("decrypt with any secret key reports invalid passphrase")
    func testDecryptWithAnySecretKeyReportsInvalidPassphrase() throws {
        let key = makeKey(email: "recipient@test.local", passphrase: "recipient-pass")
        let encrypted = try RNP.encrypt(Data("secret".utf8), addSignature: false, using: [key])

        do {
            _ = try PGPDecryption.decrypt(
                data: encrypted,
                usingAnySecretKeyIn: [key],
                passphrase: "wrong-passphrase"
            )
            Issue.record("Expected invalid passphrase")
        } catch OperationError.invalidPassphrase {
        } catch {
            Issue.record("Expected OperationError.invalidPassphrase, got \(error)")
        }
    }

    @Test("decrypt with any secret key reports missing secret keys")
    func testDecryptWithAnySecretKeyReportsMissingSecretKeys() throws {
        let key = makeKey(email: "recipient@test.local", passphrase: "recipient-pass")
        guard let publicKey = key.publicKey else {
            Issue.record("Expected generated key to include public key")
            return
        }
        let publicOnlyKey = Key(secretKey: nil, publicKey: publicKey)

        do {
            _ = try PGPDecryption.decrypt(
                data: Data("secret".utf8),
                usingAnySecretKeyIn: [publicOnlyKey],
                passphrase: "recipient-pass"
            )
            Issue.record("Expected missing secret key")
        } catch OperationError.noSecretKey {
        } catch {
            Issue.record("Expected OperationError.noSecretKey, got \(error)")
        }
    }

    @Test("decrypt reports malformed input as decryption failure")
    func testDecryptReportsMalformedInputAsDecryptionFailure() throws {
        let key = makeKey(email: "recipient@test.local", passphrase: "recipient-pass")

        do {
            _ = try PGPDecryption.decrypt(
                data: Data("not pgp".utf8),
                using: key,
                passphrase: "recipient-pass"
            )
            Issue.record("Expected decryption failure")
        } catch let error as OperationError {
            guard case .decryptionFailed = error else {
                Issue.record("Expected OperationError.decryptionFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected OperationError.decryptionFailed, got \(error)")
        }
    }

    private func makeKey(email: String, passphrase: String) -> Key {
        let keyGen = KeyGenerator()
        keyGen.keyBitsLength = 2048
        return keyGen.generate(for: email, passphrase: passphrase)
    }
}
