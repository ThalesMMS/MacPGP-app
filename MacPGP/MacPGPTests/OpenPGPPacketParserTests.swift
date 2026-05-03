//
//  OpenPGPPacketParserTests.swift
//  MacPGPTests
//

import Testing
import Foundation
@testable import MacPGP

@Suite("OpenPGPPacketParser Tests")
struct OpenPGPPacketParserTests {

    @Test("extractIssuerKeyID returns nil for empty data")
    func testExtractIssuerKeyIDEmpty() {
        let result = OpenPGPPacketParser.extractIssuerKeyID(from: Data())
        #expect(result == nil)
    }

    @Test("extractIssuerKeyID returns nil for non-PGP data")
    func testExtractIssuerKeyIDGarbage() {
        let data = Data("not a pgp packet".utf8)
        let result = OpenPGPPacketParser.extractIssuerKeyID(from: data)
        #expect(result == nil)
    }

    @Test("extractIssuerKeyID reads key ID from a minimal signature packet with issuer subpacket")
    func testExtractIssuerKeyIDMinimalSignaturePacket() {
        // Builds a single old-format packet (tag=2 signature) with a v4 signature body.
        // The body includes an unhashed subpacket area containing an Issuer subpacket (type 16) with 8 bytes.

        let issuer: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]

        // Signature body fields (version=4, sig type, pk alg, hash alg)
        var body: [UInt8] = [
            0x04, // version
            0x00, // signature type (arbitrary)
            0x00, // public-key algorithm (arbitrary)
            0x00  // hash algorithm (arbitrary)
        ]

        // Hashed subpacket length = 0
        body.append(contentsOf: [0x00, 0x00])

        // Unhashed subpacket length = 10 (1 byte type + 8 bytes issuer, plus 1 length octet)
        // Our subpacket encoding uses: [len=9][type=16][8 issuer bytes]
        body.append(contentsOf: [0x00, 0x0A])
        body.append(0x09) // subpacket length
        body.append(0x10) // subpacket type 16 (issuer)
        body.append(contentsOf: issuer)

        // Packet header: old format, tag=2, length type=0 (one-octet length)
        let header: UInt8 = 0x80 | (2 << 2) | 0
        var packet: [UInt8] = [header, UInt8(body.count)]
        packet.append(contentsOf: body)

        let result = OpenPGPPacketParser.extractIssuerKeyID(from: Data(packet))
        #expect(result == "0123456789ABCDEF")
    }

    @Test("extractIssuerKeyID reads key ID from new-format signature packet header")
    func testExtractIssuerKeyIDNewFormatSignaturePacket() {
        let issuer: [UInt8] = [0xFE, 0xDC, 0xBA, 0x98, 0x76, 0x54, 0x32, 0x10]
        let body = makeV4SignatureBody(issuer: issuer)

        // New-format packet header: bit 6 set, tag=2 signature, one-octet length.
        var packet: [UInt8] = [0xC0 | 0x02, UInt8(body.count)]
        packet.append(contentsOf: body)

        let result = OpenPGPPacketParser.extractIssuerKeyID(from: Data(packet))
        #expect(result == "FEDCBA9876543210")
    }

    @Test("extractIssuerKeyID returns nil for v3 signature packet")
    func testExtractIssuerKeyIDVersion3SignaturePacket() {
        let body: [UInt8] = [
            0x03, // version
            0x05, // hashed material length
            0x00, // signature type
            0x00, 0x00, 0x00, 0x00, // creation time
            0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF
        ]

        let header: UInt8 = 0x80 | (2 << 2) | 0
        var packet: [UInt8] = [header, UInt8(body.count)]
        packet.append(contentsOf: body)

        let result = OpenPGPPacketParser.extractIssuerKeyID(from: Data(packet))
        #expect(result == nil)
    }

    @Test("extractIssuerKeyID returns nil for truncated or malformed signature packets")
    func testExtractIssuerKeyIDMalformedSignaturePackets() {
        let validIssuer: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]
        let validBody = makeV4SignatureBody(issuer: validIssuer)
        let oldFormatHeader: UInt8 = 0x80 | (2 << 2) | 0

        let cases: [[UInt8]] = [
            [0xC0 | 0x02],
            [oldFormatHeader, UInt8(validBody.count + 1)] + validBody,
            [oldFormatHeader, 0x06, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00],
            [oldFormatHeader, 0x0B, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0A, 0x09, 0x10, 0x01]
        ]

        for packet in cases {
            let result = OpenPGPPacketParser.extractIssuerKeyID(from: Data(packet))
            #expect(result == nil)
        }
    }

    private func makeV4SignatureBody(issuer: [UInt8]) -> [UInt8] {
        var body: [UInt8] = [
            0x04, // version
            0x00, // signature type
            0x00, // public-key algorithm
            0x00  // hash algorithm
        ]

        body.append(contentsOf: [0x00, 0x00])
        body.append(contentsOf: [0x00, 0x0A])
        body.append(0x09)
        body.append(0x10)
        body.append(contentsOf: issuer)
        return body
    }
}
