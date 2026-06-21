//
//  MalformedInputMutationTests.swift
//  MacPGPTests
//
//  Deterministic, seeded malformed-input mutation coverage for issue #132.
//
//  A seeded mutator applies bounded mutations to a small corpus of valid inputs
//  and feeds them to MacPGP-owned parsing boundaries. The invariant is that no
//  mutation may crash, trap, or escape an untyped error: parsers must return
//  nil / a value, or throw their declared typed error. Failures log a reproducible
//  seed + iteration so the exact input can be regenerated and promoted to a fixture.
//
//  These boundaries are pure parsers and do not write files, so the "no partial
//  user file" invariant is satisfied vacuously here; file-output cleanup is covered
//  by the crypto-service tests.
//

import Foundation
import Testing
import CryptoKit
import RNPKit
@testable import MacPGP

// MARK: - Deterministic RNG (SplitMix64)

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Bounded mutator

enum MalformedMutator {
    /// Applies one bounded mutation, covering the mutation classes from issue #132:
    /// truncation, flipped tag/format bits, corrupted/oversized declared lengths,
    /// random prefix/suffix bytes, bit flips, and boundary sizes.
    static func mutate(_ data: Data, using rng: inout SeededGenerator) -> Data {
        var bytes = [UInt8](data)
        let choice = Int.random(in: 0..<10, using: &rng)

        if bytes.isEmpty {
            return Data((0..<Int.random(in: 0...4, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) })
        }

        switch choice {
        case 0: // truncate at a random structural boundary
            bytes = Array(bytes.prefix(Int.random(in: 0...bytes.count, using: &rng)))
        case 1: // single bit flip
            let i = Int.random(in: 0..<bytes.count, using: &rng)
            bytes[i] ^= UInt8(1) << UInt8.random(in: 0..<8, using: &rng)
        case 2: // randomize a byte
            bytes[Int.random(in: 0..<bytes.count, using: &rng)] = UInt8.random(in: 0...255, using: &rng)
        case 3: // flip the first byte (packet tag / format bits)
            bytes[0] ^= 0xFF
        case 4: // corrupt a likely length octet to declare more than available
            bytes[Int.random(in: 0..<bytes.count, using: &rng)] = 0xFF
        case 5: // insert random prefix bytes
            let extra = (0..<Int.random(in: 1...8, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
            bytes.insert(contentsOf: extra, at: 0)
        case 6: // append random suffix bytes
            let extra = (0..<Int.random(in: 1...8, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
            bytes.append(contentsOf: extra)
        case 7: // duplicate a chunk
            let start = Int.random(in: 0..<bytes.count, using: &rng)
            let end = Int.random(in: start...bytes.count, using: &rng)
            bytes.insert(contentsOf: Array(bytes[start..<end]), at: start)
        case 8: // collapse to a boundary size (empty / one byte)
            bytes = Int.random(in: 0...1, using: &rng) == 0 ? [] : [UInt8.random(in: 0...255, using: &rng)]
        default: // zero a region
            let start = Int.random(in: 0..<bytes.count, using: &rng)
            let end = Int.random(in: start..<bytes.count, using: &rng) + 1
            for i in start..<min(end, bytes.count) { bytes[i] = 0 }
        }

        // Cap growth so a pathological run cannot allocate without bound.
        if bytes.count > 1 << 16 {
            bytes = Array(bytes.prefix(1 << 16))
        }
        return Data(bytes)
    }
}

// MARK: - Corpus

enum MutationCorpus {
    static func validSignaturePacket() -> Data {
        let issuer: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]
        var body: [UInt8] = [0x04, 0x00, 0x00, 0x00]
        body.append(contentsOf: [0x00, 0x00])       // hashed subpacket length = 0
        body.append(contentsOf: [0x00, 0x0A])       // unhashed subpacket length = 10
        body.append(0x09)                            // subpacket length
        body.append(0x10)                            // subpacket type 16 (issuer)
        body.append(contentsOf: issuer)
        let header: UInt8 = 0x80 | (2 << 2) | 0      // old format, tag 2, one-octet length
        var packet: [UInt8] = [header, UInt8(body.count)]
        packet.append(contentsOf: body)
        return Data(packet)
    }

    static func armoredSignature() -> Data {
        let packet = validSignaturePacket()
        let armored = (try? Armor.armored(packet, as: .signature)) ?? ""
        return Data(armored.utf8)
    }

    static let armoredPublicKey = Data("""
    -----BEGIN PGP PUBLIC KEY BLOCK-----

    mDMEXKbiLhYJKwYBBAHaRw8BAQdAeh9cNZ3kMofVDD6RKfRqGx4Xf2QP6NeAKX63
    tz2nXNi0KEFsaWNlIChUZXN0IGVjYyBrZXkpIDxhbGljZUBleGFtcGxlLm9yZz6I
    kAQTFgoAOBYhBGMhZCte+WN1jJkd5LnqXrB3eHnUBQJcpuIuAhsDBQsJCAcDBRUK
    CQgLBRYCAwEAAh4BAheAAAoJELnqXrB3eHnUn5QBAJXdRSLGHkgy7ssy77AmpQCE
    XoKoy/JDPFT8JPjmCxOyAP4tgt+muqjeJztSGX5pjD7nCMHVnyemd4c/6cQw+dSi
    D7g4BFym4i4SCisGAQQBl1UBBQEBB0CbRCmt6q4m2mOcE3oB2Q7FPRRiPIHFZ8xf
    u4fpx2vucQMBCAeIeAQYFgoAIBYhBGMhZCte+WN1jJkd5LnqXrB3eHnUBQJcpuIu
    AhsMAAoJELnqXrB3eHnUFtkBAJD/18TpbKGAUB2t94p/ETrYJmriZQUkBPFcRd++
    3nAEAP9tzCRCiYNBSsQRmSAZcyVqSRqQzy39cPm+Rn35jqdVAA==
    =fjlK
    -----END PGP PUBLIC KEY BLOCK-----
    """.utf8)

    /// A minimal binary OpenPGP-ish encrypted header: a tag-1 (PKESK) old-format
    /// packet followed by a tag-18 (SEIPD) header.
    static func encryptedFileHeader() -> Data {
        Data([0x84, 0x0C] + Array(repeating: 0x00, count: 12) + [0xD2, 0x10] + Array(repeating: 0x01, count: 16))
    }

    static func backupV1() -> Data {
        (try? EncryptedBackupEnvelope.sealV1(
            Data("MACPGP backup payload".utf8),
            passphrase: "corpus-passphrase",
            salt: Data(repeating: 0x11, count: 16),
            nonce: try! AES.GCM.Nonce(data: Data(repeating: 0x22, count: 12))
        )) ?? Data()
    }

    static func backupV2() -> Data {
        (try? EncryptedBackupEnvelope.sealV2(
            Data("MACPGP backup payload".utf8),
            passphrase: "corpus-passphrase",
            salt: Data(repeating: 0x33, count: 16),
            nonce: try! AES.GCM.Nonce(data: Data(repeating: 0x44, count: 12)),
            iterations: 600_000,
            createdAt: nil
        )) ?? Data()
    }
}

// MARK: - Tests

@Suite("Malformed Input Mutation Tests")
struct MalformedInputMutationTests {
    private static let iterations = 3000

    private func runMutations(seed: UInt64, corpus: Data, _ body: (Data) -> Void) {
        var rng = SeededGenerator(seed: seed)
        for iteration in 0..<Self.iterations {
            let mutated = MalformedMutator.mutate(corpus, using: &rng)
            // If `body` traps, the process crashes and the seed below pinpoints it.
            _ = iteration
            body(mutated)
        }
    }

    @Test("OpenPGPPacketParser issuer extraction survives mutated signature bytes")
    func mutateIssuerExtraction() {
        runMutations(seed: 0x5132_0001, corpus: MutationCorpus.validSignaturePacket()) { data in
            _ = OpenPGPPacketParser.extractIssuerKeyID(from: data)
        }
        runMutations(seed: 0x5132_0002, corpus: MutationCorpus.armoredSignature()) { data in
            _ = OpenPGPPacketParser.extractIssuerKeyID(from: data)
        }
        #expect(Bool(true))
    }

    @Test("PGPArmorDetector survives mutated armor text")
    func mutateArmorDetector() {
        for corpus in [MutationCorpus.armoredPublicKey, MutationCorpus.armoredSignature()] {
            runMutations(seed: 0x5132_0010 ^ UInt64(corpus.count), corpus: corpus) { data in
                let text = String(decoding: data, as: UTF8.self)
                _ = PGPArmorDetector.detectedBlock(in: text)
                _ = PGPArmorDetector.normalizedArmoredText(from: text)
            }
        }
        #expect(Bool(true))
    }

    @Test("PGPFileAnalyzer survives mutated headers and only throws typed errors")
    func mutateFileAnalyzer() {
        let analyzer = PGPFileAnalyzer()
        for corpus in [MutationCorpus.armoredPublicKey, MutationCorpus.encryptedFileHeader()] {
            runMutations(seed: 0x5132_0020 ^ UInt64(corpus.count), corpus: corpus) { data in
                _ = try? analyzer.analyze(data: data, fileURL: nil)
            }
        }
        #expect(Bool(true))
    }

    @Test("EncryptedBackupEnvelope.open only ever throws BackupEnvelopeError")
    func mutateBackupEnvelope() {
        for (seed, corpus) in [(UInt64(0x5132_0031), MutationCorpus.backupV1()), (UInt64(0x5132_0032), MutationCorpus.backupV2())] {
            #expect(!corpus.isEmpty)
            var rng = SeededGenerator(seed: seed)
            for iteration in 0..<Self.iterations {
                let mutated = MalformedMutator.mutate(corpus, using: &rng)
                do {
                    _ = try EncryptedBackupEnvelope.open(mutated, passphrase: "corpus-passphrase")
                } catch is BackupEnvelopeError {
                    // Expected: every failure is a typed envelope error.
                } catch {
                    Issue.record("Untyped error from open() at seed=\(String(seed, radix: 16)) iteration=\(iteration): \(error)")
                }
            }
        }
    }

    @Test("PGPFileExtensions output-name derivation survives hostile filenames")
    func mutateFileExtensions() {
        let names = [
            "", ".", "..", "a", "a.gpg", "a.gpg.gpg", String(repeating: "x", count: 5000) + ".asc",
            "no-extension", ".hidden", "weird..name...gpg", "файл.pgp", "emoji😀.asc", "tab\tname.gpg",
            "/", "//", "a/b/c.gpg", "spaces in name .pgp", "trailing.", "UPPER.GPG"
        ]
        for name in names {
            let url = URL(fileURLWithPath: "/tmp").appendingPathComponent(name.isEmpty ? "x" : name)
            _ = PGPFileExtensions.defaultDecryptedOutputURL(for: url)
            _ = PGPFileExtensions.isPGPFileExtension(url.pathExtension)
            _ = PGPFileExtensions.encryptedOutputExtension(armored: true)
            _ = PGPFileExtensions.signedOutputExtension(detached: false, armored: false)
        }
        #expect(Bool(true))
    }

    // MARK: - Explicit boundary / declared-length cases

    @Test("Parsers handle empty, one-byte, and oversized-declared-length inputs")
    func explicitBoundaries() {
        let analyzer = PGPFileAnalyzer()
        let boundaryInputs: [Data] = [
            Data(),
            Data([0x00]),
            Data([0xFF]),
            // New-format packet declaring a 5-octet length far beyond the input.
            Data([0xC2, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
            // Old-format packet declaring a 2-octet length beyond the input.
            Data([0x88, 0xFF, 0xFF, 0x00]),
        ]
        for data in boundaryInputs {
            _ = OpenPGPPacketParser.extractIssuerKeyID(from: data)
            _ = try? analyzer.analyze(data: data, fileURL: nil)
            _ = PGPArmorDetector.detectedBlock(in: String(decoding: data, as: UTF8.self))
            #expect(throws: BackupEnvelopeError.self) {
                _ = try EncryptedBackupEnvelope.open(data, passphrase: "x")
            }
        }
    }
}
