//
//  FingerprintFormattingTests.swift
//  MacPGPTests
//

import Testing
@testable import MacPGP

@Suite("Fingerprint Formatting Tests")
struct FingerprintFormattingTests {

    @Test("Empty fingerprint formats as empty")
    func testEmptyFingerprintFormatsAsEmpty() {
        #expect("".formattedAsFingerprint() == "")
    }

    @Test("Short fingerprint formats without trailing space")
    func testShortFingerprintFormatsWithoutTrailingSpace() {
        #expect("abc".formattedAsFingerprint() == "ABC")
    }

    @Test("Fingerprint formats in uppercase four-character groups")
    func testFingerprintFormatsInUppercaseFourCharacterGroups() {
        #expect("abcd1234EF567890".formattedAsFingerprint() == "ABCD 1234 EF56 7890")
    }

    @Test("Already spaced fingerprint is cleaned before formatting")
    func testAlreadySpacedFingerprintIsCleanedBeforeFormatting() {
        #expect("abcd 1234-ef56:7890".formattedAsFingerprint() == "ABCD 1234 EF56 7890")
    }

    @Test("Normalized fingerprint keeps lowercase hex only")
    func testNormalizedFingerprintKeepsLowercaseHexOnly() {
        #expect("ABCD 1234-ef56:7890".normalizedFingerprint == "abcd1234ef567890")
    }
}
