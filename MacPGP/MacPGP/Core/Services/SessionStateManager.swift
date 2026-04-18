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
    var encryptSelectedFiles: [URL] = []
    var encryptOutputLocation: URL?
    var encryptArmorOutput = true
    var encryptOutputFiles: [URL] = []
    var encryptionProgress: Double = 0.0

    // MARK: - Decrypt State
    var decryptInputText = ""
    var decryptOutputText = ""
    var decryptInputMode: InputMode = .text
    var decryptSelectedFile: URL?
    var decryptSelectedFiles: [URL] = []
    var decryptOutputLocation: URL?
    var decryptAutoDetectKey = true
    var decryptSelectedKey: PGPKeyModel?
    var decryptOutputFiles: [URL] = []
    var decryptionProgress: Double = 0.0

    // MARK: - Sign State
    var signInputText = ""
    var signOutputText = ""
    var signSignerKey: PGPKeyModel?
    var signInputMode: InputMode = .text
    var signSelectedFile: URL?
    var signDetachedSignature = false
    var signCleartextSignature = true
    var signArmorOutput = true
    var signOutputFiles: [URL] = []

    // MARK: - Verify State
    var verifyInputText = ""
    var verifySignatureText = ""
    var verifyResult: VerificationResult?
    var verifyInputMode: InputMode = .text
    var verifySignatureMode: SignatureMode = .inline
    var verifySelectedFile: URL?
    var verifySelectedSignatureFile: URL?

    /// Resets all ephemeral encryption, decryption, signing, and verification UI state to their initial default values.
    /// 
    /// This clears input/output text, selected files/keys/recipients, output locations and file lists, modes, signature options, armor settings, and progress counters for the encrypt, decrypt, sign, and verify workflows.
    func clearAll() {
        // Encrypt
        encryptInputText = ""
        encryptOutputText = ""
        encryptSelectedRecipients = []
        encryptSignerKey = nil
        encryptInputMode = .text
        encryptSelectedFile = nil
        encryptSelectedFiles = []
        encryptOutputLocation = nil
        encryptArmorOutput = true
        encryptOutputFiles = []
        encryptionProgress = 0.0

        // Decrypt
        decryptInputText = ""
        decryptOutputText = ""
        decryptInputMode = .text
        decryptSelectedFile = nil
        decryptSelectedFiles = []
        decryptOutputLocation = nil
        decryptAutoDetectKey = true
        decryptSelectedKey = nil
        decryptOutputFiles = []
        decryptionProgress = 0.0

        // Sign
        signInputText = ""
        signOutputText = ""
        signSignerKey = nil
        signInputMode = .text
        signSelectedFile = nil
        signDetachedSignature = false
        signCleartextSignature = true
        signArmorOutput = true
        signOutputFiles = []

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
