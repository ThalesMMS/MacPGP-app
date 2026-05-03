//
//  OpenPGPPacketParser.swift
//  MacPGP
//
//  Extracted from SigningService to isolate low-level OpenPGP packet parsing utilities.
//

import Foundation
import RNPKit

internal enum OpenPGPPacketParser {

    /// Extracts the issuer (signer's) 8-byte key ID from a PGP signature if present.
    ///
    /// Accepts either an ASCII-armored PGP signature/message or raw signature packet bytes and parses OpenPGP packets to locate a signature packet and its Issuer subpacket.
    /// - Parameter signatureData: Armored or raw signature data to inspect.
    /// - Returns: A 16-character uppercase hex string representing the 8-byte issuer key ID if found, `nil` otherwise.
    static func extractIssuerKeyID(from signatureData: Data) -> String? {
        let packetData: Data
        if let armoredString = String(data: signatureData, encoding: .utf8),
           armoredString.hasPrefix("-----BEGIN PGP SIGNATURE-----") ||
           armoredString.hasPrefix("-----BEGIN PGP MESSAGE-----") ||
           armoredString.hasPrefix("-----BEGIN PGP PUBLIC KEY BLOCK-----") {
            guard let dearmoredData = try? Armor.readArmored(armoredString) else {
                return nil
            }
            packetData = dearmoredData
        } else {
            packetData = signatureData
        }

        let bytes = [UInt8](packetData)
        var offset = 0

        while offset < bytes.count {
            guard let packet = readPacket(in: bytes, offset: &offset) else {
                return nil
            }

            guard packet.bodyRange.upperBound <= bytes.count else {
                return nil
            }

            if packet.tag == 2 {
                return extractIssuerKeyID(fromSignaturePacketBody: Array(bytes[packet.bodyRange]))
            }
        }

        return nil
    }

    private static func extractIssuerKeyID(fromSignaturePacketBody packetBody: [UInt8]) -> String? {
        guard packetBody.count >= 6 else {
            return nil
        }

        guard packetBody[0] == 4 else {
            return nil
        }

        let hashedSubpacketLength = (Int(packetBody[4]) << 8) | Int(packetBody[5])
        let hashedSubpacketStart = 6
        let hashedSubpacketEnd = hashedSubpacketStart + hashedSubpacketLength

        guard hashedSubpacketEnd + 2 <= packetBody.count else {
            return nil
        }

        if let issuerKeyID = extractIssuerKeyID(
            fromSubpacketsIn: packetBody,
            range: hashedSubpacketStart..<hashedSubpacketEnd
        ) {
            return issuerKeyID
        }

        let unhashedLengthOffset = hashedSubpacketEnd
        let unhashedSubpacketLength = (Int(packetBody[unhashedLengthOffset]) << 8) | Int(packetBody[unhashedLengthOffset + 1])
        let unhashedSubpacketStart = unhashedLengthOffset + 2
        let unhashedSubpacketEnd = unhashedSubpacketStart + unhashedSubpacketLength

        guard unhashedSubpacketEnd <= packetBody.count else {
            return nil
        }

        return extractIssuerKeyID(
            fromSubpacketsIn: packetBody,
            range: unhashedSubpacketStart..<unhashedSubpacketEnd
        )
    }

    private static func extractIssuerKeyID(fromSubpacketsIn bytes: [UInt8], range: Range<Int>) -> String? {
        var offset = range.lowerBound

        while offset < range.upperBound {
            guard let (subpacketLength, lengthFieldSize) = readSubpacketLength(
                in: bytes,
                offset: offset,
                upperBound: range.upperBound
            ) else {
                return nil
            }

            offset += lengthFieldSize

            guard subpacketLength > 0, offset + subpacketLength <= range.upperBound else {
                return nil
            }

            let type = bytes[offset] & 0x7F
            let bodyStart = offset + 1
            let bodyLength = subpacketLength - 1

            if type == 16 {
                guard bodyLength == 8, bodyStart + bodyLength <= range.upperBound else {
                    return nil
                }

                return bytes[bodyStart..<bodyStart + bodyLength]
                    .map { String(format: "%02X", $0) }
                    .joined()
            }

            offset += subpacketLength
        }

        return nil
    }

    private static func readPacket(in bytes: [UInt8], offset: inout Int) -> (tag: UInt8, bodyRange: Range<Int>)? {
        guard offset < bytes.count else {
            return nil
        }

        let packetHeader = bytes[offset]
        guard (packetHeader & 0x80) != 0 else {
            return nil
        }

        let isNewFormat = (packetHeader & 0x40) != 0
        let packetTag: UInt8
        let packetLength: Int
        let bodyStart: Int

        if isNewFormat {
            packetTag = packetHeader & 0x3F
            let lengthOffset = offset + 1

            guard let (resolvedLength, headerLength) = readNewFormatPacketLength(in: bytes, offset: lengthOffset) else {
                return nil
            }

            packetLength = resolvedLength
            bodyStart = lengthOffset + headerLength
        } else {
            packetTag = (packetHeader & 0x3C) >> 2
            let lengthType = packetHeader & 0x03
            let lengthOffset = offset + 1

            guard let (resolvedLength, headerLength) = readOldFormatPacketLength(
                in: bytes,
                offset: lengthOffset,
                lengthType: lengthType
            ) else {
                return nil
            }

            packetLength = resolvedLength
            bodyStart = lengthOffset + headerLength
        }

        let bodyEnd = bodyStart + packetLength
        guard bodyStart <= bodyEnd, bodyEnd <= bytes.count else {
            return nil
        }

        offset = bodyEnd
        return (packetTag, bodyStart..<bodyEnd)
    }

    private static func readNewFormatPacketLength(in bytes: [UInt8], offset: Int) -> (length: Int, headerLength: Int)? {
        guard offset < bytes.count else {
            return nil
        }

        let firstOctet = bytes[offset]

        switch firstOctet {
        case 0..<192:
            return (Int(firstOctet), 1)
        case 192..<224:
            guard offset + 1 < bytes.count else {
                return nil
            }

            let secondOctet = bytes[offset + 1]
            let length = ((Int(firstOctet) - 192) << 8) + Int(secondOctet) + 192
            return (length, 2)
        case 255:
            guard offset + 4 < bytes.count else {
                return nil
            }

            let length = (Int(bytes[offset + 1]) << 24) |
                         (Int(bytes[offset + 2]) << 16) |
                         (Int(bytes[offset + 3]) << 8) |
                         Int(bytes[offset + 4])
            return (length, 5)
        case 224..<255:
            return nil
        default:
            return nil
        }
    }

    private static func readOldFormatPacketLength(in bytes: [UInt8], offset: Int, lengthType: UInt8) -> (length: Int, headerLength: Int)? {
        switch lengthType {
        case 0:
            guard offset < bytes.count else {
                return nil
            }
            return (Int(bytes[offset]), 1)
        case 1:
            guard offset + 1 < bytes.count else {
                return nil
            }
            let length = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
            return (length, 2)
        case 2:
            guard offset + 3 < bytes.count else {
                return nil
            }
            let length = (Int(bytes[offset]) << 24) |
                         (Int(bytes[offset + 1]) << 16) |
                         (Int(bytes[offset + 2]) << 8) |
                         Int(bytes[offset + 3])
            return (length, 4)
        case 3:
            guard offset <= bytes.count else {
                return nil
            }
            return (bytes.count - offset, 0)
        default:
            return nil
        }
    }

    private static func readSubpacketLength(in bytes: [UInt8], offset: Int, upperBound: Int) -> (length: Int, headerLength: Int)? {
        guard offset < upperBound else {
            return nil
        }

        let firstOctet = bytes[offset]

        switch firstOctet {
        case 0..<192:
            return (Int(firstOctet), 1)
        case  192..<255:
            guard offset + 1 < upperBound else {
                return nil
            }

            let secondOctet = bytes[offset + 1]
            let length = ((Int(firstOctet) - 192) << 8) + Int(secondOctet) + 192
            return (length, 2)
        case 255:
            guard offset + 4 < upperBound else {
                return nil
            }

            let length = (Int(bytes[offset + 1]) << 24) |
                         (Int(bytes[offset + 2]) << 16) |
                         (Int(bytes[offset + 3]) << 8) |
                         Int(bytes[offset + 4])
            return (length, 5)
        default:
            return nil
        }
    }
}
