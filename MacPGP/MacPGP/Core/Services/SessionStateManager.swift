import Foundation
import SwiftUI

/// Manages ephemeral session state that persists between tab switches but not across app launches
@Observable
final class SessionStateManager {
    // MARK: - Encrypt State
    var encryptInputText = ""
    var encryptOutputText = ""
    var encryptSelectedRecipients: Set<PGPKeyModel> = []
    var encryptSignerKey: PGPKeyModel?
    var encryptInputMode: InputMode = .text
    var encryptSelectedFile: URL?
    var encryptArmorOutput = true

    // MARK: - Decrypt State
    var decryptInputText = ""
    var decryptOutputText = ""
    var decryptInputMode: InputMode = .text
    var decryptSelectedFile: URL?
    var decryptAutoDetectKey = true
    var decryptSelectedKey: PGPKeyModel?

    // MARK: - Sign State
    var signInputText = ""
    var signOutputText = ""
    var signSignerKey: PGPKeyModel?
    var signInputMode: InputMode = .text
    var signSelectedFile: URL?
    var signDetachedSignature = false
    var signCleartextSignature = true
    var signArmorOutput = true

    // MARK: - Verify State
    var verifyInputText = ""
    var verifySignatureText = ""
    var verifyResult: VerificationResult?
    var verifyInputMode: InputMode = .text
    var verifySignatureMode: SignatureMode = .inline
    var verifySelectedFile: URL?
    var verifySelectedSignatureFile: URL?

    // MARK: - Clear All
    func clearAll() {
        // Encrypt
        encryptInputText = ""
        encryptOutputText = ""
        encryptSelectedRecipients = []
        encryptSignerKey = nil
        encryptInputMode = .text
        encryptSelectedFile = nil
        encryptArmorOutput = true

        // Decrypt
        decryptInputText = ""
        decryptOutputText = ""
        decryptInputMode = .text
        decryptSelectedFile = nil
        decryptAutoDetectKey = true
        decryptSelectedKey = nil

        // Sign
        signInputText = ""
        signOutputText = ""
        signSignerKey = nil
        signInputMode = .text
        signSelectedFile = nil
        signDetachedSignature = false
        signCleartextSignature = true
        signArmorOutput = true

        // Verify
        verifyInputText = ""
        verifySignatureText = ""
        verifyResult = nil
        verifyInputMode = .text
        verifySignatureMode = .inline
        verifySelectedFile = nil
        verifySelectedSignatureFile = nil
    }
}
