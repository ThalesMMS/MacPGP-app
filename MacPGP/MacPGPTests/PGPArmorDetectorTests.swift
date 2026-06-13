//
//  PGPArmorDetectorTests.swift
//  MacPGPTests
//

import Testing
@testable import MacPGP

@Suite("PGPArmorDetector Tests")
struct PGPArmorDetectorTests {

    @Test("detects known armor headers at the logical start")
    func testDetectsKnownArmorHeadersAtStart() {
        #expect(PGPArmorDetector.detectedBlock(in: "-----BEGIN PGP MESSAGE-----\n") == .message)
        #expect(PGPArmorDetector.detectedBlock(in: "-----BEGIN PGP SIGNATURE-----\n") == .signature)
        #expect(PGPArmorDetector.detectedBlock(in: "-----BEGIN PGP SIGNED MESSAGE-----\n") == .signedMessage)
        #expect(PGPArmorDetector.detectedBlock(in: "-----BEGIN PGP PUBLIC KEY BLOCK-----\n") == .publicKey)
        #expect(PGPArmorDetector.detectedBlock(in: "-----BEGIN PGP PRIVATE KEY BLOCK-----\n") == .privateKey)
    }

    @Test("allows leading whitespace before an armor header")
    func testAllowsLeadingWhitespaceBeforeArmorHeader() {
        let content = "\n\t -----BEGIN PGP SIGNATURE-----\n"

        #expect(PGPArmorDetector.detectedBlock(in: content) == .signature)
        #expect(PGPArmorDetector.normalizedArmoredText(from: content) == "-----BEGIN PGP SIGNATURE-----")
    }

    @Test("does not match embedded armor text")
    func testDoesNotMatchEmbeddedArmorText() {
        let content = "not armored\n-----BEGIN PGP MESSAGE-----\n"

        #expect(PGPArmorDetector.detectedBlock(in: content) == nil)
        #expect(PGPArmorDetector.normalizedArmoredText(from: content) == nil)
    }
}
