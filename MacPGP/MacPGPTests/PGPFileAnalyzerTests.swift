//
//  PGPFileAnalyzerTests.swift
//  MacPGPTests
//

import Foundation
import Testing
@testable import MacPGP

@Suite("PGPFileAnalyzer Tests")
struct PGPFileAnalyzerTests {

    @Test("analyze classifies prefixed key armor headers")
    @MainActor
    func testAnalyzeClassifiesPrefixedKeyArmorHeaders() throws {
        let analyzer = PGPFileAnalyzer()

        let publicKeyResult = try analyzer.analyze(
            data: Data("-----BEGIN PGP PUBLIC KEY BLOCK-----\n".utf8)
        )
        let privateKeyResult = try analyzer.analyze(
            data: Data("-----BEGIN PGP PRIVATE KEY BLOCK-----\n".utf8)
        )

        #expect(publicKeyResult.encodingFormat == .asciiArmored)
        #expect(publicKeyResult.fileType == .publicKey)
        #expect(privateKeyResult.encodingFormat == .asciiArmored)
        #expect(privateKeyResult.fileType == .privateKey)
    }

    @Test("analyze classifies signed armor after leading whitespace")
    @MainActor
    func testAnalyzeClassifiesSignedArmorAfterLeadingWhitespace() throws {
        let analyzer = PGPFileAnalyzer()
        let content = "\n-----BEGIN PGP SIGNED MESSAGE-----\n"

        let result = try analyzer.analyze(data: Data(content.utf8))

        #expect(result.encodingFormat == .asciiArmored)
        #expect(result.fileType == .signed)
    }

    @Test("analyze does not classify embedded armor text")
    @MainActor
    func testAnalyzeDoesNotClassifyEmbeddedArmorText() {
        let analyzer = PGPFileAnalyzer()
        let content = "not pgp\n-----BEGIN PGP SIGNATURE-----\n"

        #expect(throws: Error.self) {
            try analyzer.analyze(data: Data(content.utf8))
        }
    }

    @Test("header analysis classifies a large binary encrypted file from a bounded prefix")
    func testAnalyzeHeaderClassifiesLargeBinaryEncryptedFileFromBoundedPrefix() throws {
        let analyzer = PGPFileAnalyzer()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("large-\(UUID().uuidString).gpg")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var data = Data([0xC1, 0x00])
        data.append(Data(repeating: 0x41, count: 1024 * 1024))
        try data.write(to: fileURL)

        let result = try analyzer.analyzeHeader(fileAt: fileURL, maxBytes: 16)

        #expect(result.encodingFormat == .binary)
        #expect(result.fileType == .encrypted)
        #expect(result.isEncrypted)
        #expect(result.fileSize == Int64(data.count))
    }

    @Test("FinderSync and Thumbnail extensions use bounded header analysis")
    func testExtensionsUseBoundedHeaderAnalysis() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectDirectory = testsDirectory.deletingLastPathComponent()
        let finderSyncSource = try String(
            contentsOf: projectDirectory.appendingPathComponent("FinderSyncExtension/FinderSync.swift"),
            encoding: .utf8
        )
        let thumbnailSource = try String(
            contentsOf: projectDirectory.appendingPathComponent("ThumbnailExtension/ThumbnailProvider.swift"),
            encoding: .utf8
        )

        #expect(finderSyncSource.contains("fileAnalyzer.isEncryptedHeader(fileAt:"))
        #expect(!finderSyncSource.contains("fileAnalyzer.isEncrypted(fileAt:"))
        #expect(thumbnailSource.contains("fileAnalyzer.analyzeHeader(fileAt:"))
        #expect(!thumbnailSource.contains("fileAnalyzer.analyze(fileAt:"))
    }
}
