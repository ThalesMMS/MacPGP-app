//
//  PGPFileExtensionsTests.swift
//  MacPGPTests
//

import Foundation
import Testing
@testable import MacPGP

@Suite("PGPFileExtensions Tests")
struct PGPFileExtensionsTests {

    @Test("Supported PGP extensions are case insensitive")
    func testSupportedPGPExtensionsAreCaseInsensitive() {
        #expect(PGPFileExtensions.isPGPFileExtension("asc"))
        #expect(PGPFileExtensions.isPGPFileExtension("GPG"))
        #expect(PGPFileExtensions.isPGPFileExtension("Pgp"))
        #expect(!PGPFileExtensions.isPGPFileExtension("txt"))
    }

    @Test("Encrypted output extension follows armor mode")
    func testEncryptedOutputExtension() {
        #expect(PGPFileExtensions.encryptedOutputExtension(armored: true) == "asc")
        #expect(PGPFileExtensions.encryptedOutputExtension(armored: false) == "gpg")
    }

    @Test("Signed output extension follows detached and armor mode")
    func testSignedOutputExtension() {
        #expect(PGPFileExtensions.signedOutputExtension(detached: true, armored: true) == "asc")
        #expect(PGPFileExtensions.signedOutputExtension(detached: false, armored: true) == "asc")
        #expect(PGPFileExtensions.signedOutputExtension(detached: true, armored: false) == "sig")
        #expect(PGPFileExtensions.signedOutputExtension(detached: false, armored: false) == "gpg")
    }

    @Test("Default decrypted output removes PGP extension")
    func testDefaultDecryptedOutputRemovesPGPExtension() {
        let encryptedURL = URL(fileURLWithPath: "/tmp/message.txt.asc")
        let binaryURL = URL(fileURLWithPath: "/tmp/message.txt.gpg")
        let pgpURL = URL(fileURLWithPath: "/tmp/message.txt.pgp")

        #expect(PGPFileExtensions.defaultDecryptedOutputURL(for: encryptedURL).lastPathComponent == "message.txt")
        #expect(PGPFileExtensions.defaultDecryptedOutputURL(for: binaryURL).lastPathComponent == "message.txt")
        #expect(PGPFileExtensions.defaultDecryptedOutputURL(for: pgpURL).lastPathComponent == "message.txt")
    }

    @Test("Default decrypted output appends fallback extension for non-PGP files")
    func testDefaultDecryptedOutputAppendsFallbackExtensionForNonPGPFile() {
        let fileURL = URL(fileURLWithPath: "/tmp/message.dat")

        #expect(PGPFileExtensions.defaultDecryptedOutputURL(for: fileURL).lastPathComponent == "message.dat.decrypted")
    }
}
