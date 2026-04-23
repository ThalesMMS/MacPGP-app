import Foundation
import RNPBridge

private func rnpPasswordCallback(
    _ ffi: OpaquePointer?,
    _ context: UnsafeMutableRawPointer?,
    _ key: OpaquePointer?,
    _ pgpContext: UnsafePointer<CChar>?,
    _ buffer: UnsafeMutablePointer<CChar>?,
    _ bufferLength: Int
) -> Bool {
    guard
        let context,
        let buffer,
        bufferLength > 1
    else {
        return false
    }

    let box = Unmanaged<RNP.PasswordProviderBox>.fromOpaque(context).takeUnretainedValue()
    guard let password = box.password(for: key) else {
        return false
    }

    let scalarCount = password.utf8.count
    guard scalarCount + 1 <= bufferLength else {
        return false
    }

    return password.withCString { cString in
        strncpy(buffer, cString, bufferLength)
        buffer[scalarCount] = 0
        return true
    }
}

enum RNP {
    private static let publicKeyFormat = "GPG"
    private static let secretKeyFormat = "GPG"
    private static let objectivePGPDomain = "ObjectivePGP"
    private static let genericErrorCode = 1
    private static let invalidPassphraseCode = 2

    final class PasswordProviderBox {
        let resolver: (Key) -> String?
        let keysByFingerprint: [String: Key]

        init(keys: [Key], resolver: @escaping (Key) -> String?) {
            self.resolver = resolver
            var keysByFingerprint: [String: Key] = [:]
            for key in keys {
                let fingerprints = (try? RNP.fingerprints(for: key)) ?? [key.fingerprint]
                for fingerprint in fingerprints {
                    if let existing = keysByFingerprint[fingerprint], existing.isSecret {
                        continue
                    }
                    keysByFingerprint[fingerprint] = key
                }
            }
            self.keysByFingerprint = keysByFingerprint
        }

        func password(for handle: OpaquePointer?) -> String? {
            if let handle, let fingerprint = try? RNP.fingerprint(of: handle), let key = keysByFingerprint[fingerprint] {
                return resolver(key)
            }

            return nil
        }
    }

    static func readKeys(from data: Data) throws -> [Key] {
        guard !data.isEmpty else {
            return []
        }

        return try withFFI { ffi in
            let importedFingerprints = try importKeys(data, into: ffi)
            var seenFingerprints = Set<String>()
            var exported: [Key] = []

            for importedFingerprint in importedFingerprints {
                let handle = try locateKey(fingerprint: importedFingerprint, in: ffi)
                defer { _ = rnp_key_handle_destroy(handle) }

                let primaryFingerprint = try primaryFingerprint(of: handle)
                guard seenFingerprints.insert(primaryFingerprint).inserted else {
                    continue
                }

                let primaryHandle = try locateKey(fingerprint: primaryFingerprint, in: ffi)
                defer { _ = rnp_key_handle_destroy(primaryHandle) }
                exported.append(try exportKey(from: primaryHandle))
            }

            return exported
        }
    }

    static func encrypt(
        _ data: Data,
        addSignature: Bool,
        using keys: [Key],
        passphraseForKey: ((Key) -> String?)?
    ) throws -> Data {
        let recipientKeys = keys.compactMap { key -> Key? in
            guard key.capabilities.canEncrypt, let publicKey = key.publicKey else {
                return nil
            }
            return Key(secretKey: nil, publicKey: publicKey)
        }
        let signingKeys = addSignature ? keys.compactMap { key -> Key? in
            guard key.isSecret, key.capabilities.canSign, let secretKey = key.secretKey else {
                return nil
            }
            return Key(secretKey: secretKey, publicKey: nil)
        } : []

        if addSignature && signingKeys.isEmpty {
            throw ObjectivePGPError.missingSigningKey
        }

        return try withFFI(keys: keys, passphraseForKey: passphraseForKey) { ffi in
            let input = try makeInput(from: data)
            defer { _ = rnp_input_destroy(input) }

            let output = try makeOutput()
            defer { _ = rnp_output_destroy(output) }

            var operation: OpaquePointer?
            try check(
                rnp_op_encrypt_create(&operation, ffi, input, output),
                context: "create encrypt operation"
            )
            defer {
                if let operation {
                    _ = rnp_op_encrypt_destroy(operation)
                }
            }

            for key in recipientKeys {
                let primaryHandle = try locateKey(fingerprint: key.fingerprint, in: ffi)
                defer { _ = rnp_key_handle_destroy(primaryHandle) }

                let handle = try defaultKey(for: "encrypt", from: primaryHandle)
                defer { _ = rnp_key_handle_destroy(handle) }
                try check(
                    rnp_op_encrypt_add_recipient(operation, handle),
                    context: "add encryption recipient"
                )
            }

            for key in signingKeys {
                let primaryHandle = try locateKey(fingerprint: key.fingerprint, in: ffi)
                defer { _ = rnp_key_handle_destroy(primaryHandle) }

                let handle = try defaultKey(for: "sign", from: primaryHandle)
                defer { _ = rnp_key_handle_destroy(handle) }
                try check(
                    rnp_op_encrypt_add_signature(operation, handle, nil),
                    context: "add encryption signature"
                )
            }

            try check(rnp_op_encrypt_set_armor(operation, false), context: "disable encryption armor")
            try check(rnp_op_encrypt_execute(operation), context: "encrypt data")
            return try outputData(output)
        }
    }

    static func decrypt(
        _ data: Data,
        using keys: [Key],
        passphraseForKey: ((Key) -> String?)?
    ) throws -> Data {
        try withFFI(keys: keys, passphraseForKey: passphraseForKey) { ffi in
            let input = try makeInput(from: data)
            defer { _ = rnp_input_destroy(input) }

            let output = try makeOutput()
            defer { _ = rnp_output_destroy(output) }

            try check(rnp_decrypt(ffi, input, output), context: "decrypt data")
            return try outputData(output)
        }
    }

    static func sign(
        _ data: Data,
        detached: Bool,
        using keys: [Key],
        passphraseForKey: ((Key) -> String?)?
    ) throws -> Data {
        guard let signingKey = keys.first(where: { $0.isSecret && $0.capabilities.canSign }) else {
            throw ObjectivePGPError.missingSigningKey
        }

        return try withFFI(keys: keys, passphraseForKey: passphraseForKey) { ffi in
            let input = try makeInput(from: data)
            defer { _ = rnp_input_destroy(input) }

            let output = try makeOutput()
            defer { _ = rnp_output_destroy(output) }

            var operation: OpaquePointer?
            let createResult: rnp_result_t = detached
                ? rnp_op_sign_detached_create(&operation, ffi, input, output)
                : rnp_op_sign_create(&operation, ffi, input, output)

            try check(createResult, context: "create sign operation")
            defer {
                if let operation {
                    _ = rnp_op_sign_destroy(operation)
                }
            }

            let primaryHandle = try locateKey(fingerprint: signingKey.fingerprint, in: ffi)
            defer { _ = rnp_key_handle_destroy(primaryHandle) }

            let handle = try defaultKey(for: "sign", from: primaryHandle)
            defer { _ = rnp_key_handle_destroy(handle) }

            try check(
                rnp_op_sign_add_signature(operation, handle, nil),
                context: "add signing key"
            )
            try check(rnp_op_sign_set_hash(operation, "SHA256"), context: "set sign hash")
            try check(rnp_op_sign_set_armor(operation, false), context: "disable sign armor")
            try check(rnp_op_sign_execute(operation), context: "sign data")
            return try outputData(output)
        }
    }

    static func verify(
        _ data: Data,
        signature: Data?,
        using keys: [Key]
    ) throws {
        _ = try inspect(data, signature: signature, using: keys, passphraseForKey: nil)
    }

    static func inspect(
        _ data: Data,
        signature: Data?,
        using keys: [Key],
        passphraseForKey: ((Key) -> String?)?
    ) throws -> MessageInspection {
        let isArmored = String(data: data.prefix(32), encoding: .utf8)?.contains("-----BEGIN PGP") == true
        let contents = (try? guessContents(for: data)) ?? "unknown"

        return try withFFI(keys: keys, passphraseForKey: passphraseForKey) { ffi in
            if let signature {
                return try inspectDetached(data, signature: signature, contents: contents, isArmored: isArmored, ffi: ffi)
            }
            return try inspectInline(data, contents: contents, isArmored: isArmored, ffi: ffi)
        }
    }

    static func exportRevocation(
        for key: Key,
        hash: String?,
        reasonCode: String,
        reason: String?,
        passphraseForKey: ((Key) -> String?)?
    ) throws -> Data {
        try withFFI(keys: [key], passphraseForKey: passphraseForKey) { ffi in
            let handle = try locateKey(fingerprint: key.fingerprint, in: ffi)
            defer { _ = rnp_key_handle_destroy(handle) }

            let output = try makeOutput()
            defer { _ = rnp_output_destroy(output) }

            try check(
                rnp_key_export_revocation(
                    handle,
                    output,
                    UInt32(RNP_KEY_EXPORT_ARMORED),
                    hash,
                    reasonCode,
                    reason
                ),
                context: "export revocation certificate"
            )
            return try outputData(output)
        }
    }

    static func applyRevocation(
        _ certificate: Data,
        to key: Key,
        passphraseForKey: ((Key) -> String?)?
    ) throws -> Key {
        try withFFI(keys: [key], passphraseForKey: passphraseForKey) { ffi in
            let input = try makeInput(from: certificate)
            defer { _ = rnp_input_destroy(input) }

            try check(
                rnp_import_signatures(ffi, input, 0, nil),
                context: "import revocation certificate"
            )

            let handle = try locateKey(fingerprint: key.fingerprint, in: ffi)
            defer { _ = rnp_key_handle_destroy(handle) }
            return try exportKey(from: handle)
        }
    }

    static func setExpiration(
        _ expirationDate: Date?,
        for key: Key,
        passphraseForKey: ((Key) -> String?)?
    ) throws -> Key {
        try withFFI(keys: [key], passphraseForKey: passphraseForKey) { ffi in
            let handle = try locateKey(fingerprint: key.fingerprint, in: ffi)
            defer { _ = rnp_key_handle_destroy(handle) }

            let seconds: UInt32
            if let expirationDate {
                let rawSeconds = expirationDate.timeIntervalSince(key.metadata.creationDate)
                if rawSeconds <= 0 {
                    seconds = 0
                } else {
                    guard rawSeconds <= Double(UInt32.max) else {
                        throw makeNSError("Expiration interval exceeds supported range")
                    }
                    seconds = UInt32(rawSeconds.rounded(.down))
                }
            } else {
                seconds = 0
            }

            try check(
                rnp_key_set_expiration(handle, seconds),
                context: "set key expiration"
            )
            return try exportKey(from: handle)
        }
    }

    static func generateKey(
        algorithm: KeyGenerator.Algorithm,
        keyBitsLength: Int32,
        userID: String,
        passphrase: String
    ) throws -> Key {
        try withFFI { ffi in
            var handle: OpaquePointer?

            switch algorithm {
            case .RSA:
                let bits = UInt32(max(2048, keyBitsLength))
                try check(
                    rnp_generate_key_rsa(
                        ffi,
                        bits,
                        bits,
                        userID,
                        passphrase,
                        &handle
                    ),
                    context: "generate RSA key"
                )
            case .ECDSA:
                let curveName = curveName(for: Int(keyBitsLength))
                try check(
                    rnp_generate_key_ec(ffi, curveName, userID, passphrase, &handle),
                    context: "generate ECDSA key"
                )
            case .edDSA:
                try check(
                    rnp_generate_key_25519(ffi, userID, passphrase, &handle),
                    context: "generate EdDSA key"
                )
            }

            guard let handle else {
                throw makeNSError("Key generation did not return a key handle")
            }
            defer { _ = rnp_key_handle_destroy(handle) }

            return try exportKey(from: handle)
        }
    }

    static func guessContents(for data: Data) throws -> String {
        let input = try makeInput(from: data)
        defer { _ = rnp_input_destroy(input) }

        var raw: UnsafeMutablePointer<CChar>?
        try check(rnp_guess_contents(input, &raw), context: "guess OpenPGP contents")
        return string(fromAllocated: raw)
    }

    static func armor(_ data: Data, type: PGPArmorType) throws -> String {
        let input = try makeInput(from: data)
        defer { _ = rnp_input_destroy(input) }

        let output = try makeOutput()
        defer { _ = rnp_output_destroy(output) }

        try check(rnp_enarmor(input, output, type.rawValue), context: "armor data")
        let armored = try outputData(output)
        guard let string = String(data: armored, encoding: .utf8) else {
            throw makeNSError("Failed to decode armored data as UTF-8")
        }
        return string
    }

    static func dearmor(_ string: String) throws -> Data {
        let input = try makeInput(from: Data(string.utf8))
        defer { _ = rnp_input_destroy(input) }

        let output = try makeOutput()
        defer { _ = rnp_output_destroy(output) }

        try check(rnp_dearmor(input, output), context: "dearmor data")
        return try outputData(output)
    }

    private static func inspectInline(
        _ data: Data,
        contents: String,
        isArmored: Bool,
        ffi: OpaquePointer?
    ) throws -> MessageInspection {
        let input = try makeInput(from: data)
        defer { _ = rnp_input_destroy(input) }

        let output = try makeOutput()
        defer { _ = rnp_output_destroy(output) }

        var operation: OpaquePointer?
        try check(
            rnp_op_verify_create(&operation, ffi, input, output),
            context: "create verify operation"
        )
        defer {
            if let operation {
                _ = rnp_op_verify_destroy(operation)
            }
        }

        _ = rnp_op_verify_set_flags(operation, UInt32(RNP_VERIFY_IGNORE_SIGS_ON_DECRYPT))
        let executeResult = rnp_op_verify_execute(operation)
        let signatures = try collectSignatures(from: operation)
        let recipients = try collectRecipients(from: operation)
        let protection = try protectionInfo(from: operation)
        let fileInfo = try literalFileInfo(from: operation)
        let outputData = try? outputData(output)

        if executeResult != RNP_SUCCESS &&
            executeResult != RNP_ERROR_NO_SIGNATURES_FOUND &&
            executeResult != RNP_ERROR_KEY_NOT_FOUND &&
            executeResult != RNP_ERROR_NO_SUITABLE_KEY &&
            executeResult != RNP_ERROR_DECRYPT_FAILED &&
            executeResult != RNP_ERROR_VERIFICATION_FAILED &&
            executeResult != RNP_ERROR_SIGNATURE_EXPIRED {
            try check(executeResult, context: "inspect OpenPGP message")
        }

        return MessageInspection(
            contents: contents,
            isArmored: isArmored,
            isEncrypted: !recipients.isEmpty || protection != nil,
            isSigned: !signatures.isEmpty,
            recipientKeyIDs: recipients,
            protection: protection,
            signatures: signatures,
            literalFilename: fileInfo.filename,
            literalMTime: fileInfo.modifiedAt,
            outputData: outputData
        )
    }

    private static func inspectDetached(
        _ data: Data,
        signature: Data,
        contents: String,
        isArmored: Bool,
        ffi: OpaquePointer?
    ) throws -> MessageInspection {
        let input = try makeInput(from: data)
        defer { _ = rnp_input_destroy(input) }

        let signatureInput = try makeInput(from: signature)
        defer { _ = rnp_input_destroy(signatureInput) }

        var operation: OpaquePointer?
        try check(
            rnp_op_verify_detached_create(&operation, ffi, input, signatureInput),
            context: "create detached verify operation"
        )
        defer {
            if let operation {
                _ = rnp_op_verify_destroy(operation)
            }
        }

        let executeResult = rnp_op_verify_execute(operation)
        let signatures = try collectSignatures(from: operation)

        if executeResult != RNP_SUCCESS &&
            executeResult != RNP_ERROR_VERIFICATION_FAILED &&
            executeResult != RNP_ERROR_SIGNATURE_EXPIRED {
            try check(executeResult, context: "inspect detached signature")
        }

        return MessageInspection(
            contents: contents,
            isArmored: isArmored,
            isEncrypted: false,
            isSigned: !signatures.isEmpty,
            recipientKeyIDs: [],
            protection: nil,
            signatures: signatures,
            literalFilename: nil,
            literalMTime: nil,
            outputData: nil
        )
    }

    private static func literalFileInfo(from operation: OpaquePointer?) throws -> (filename: String?, modifiedAt: Date?) {
        var rawFilename: UnsafeMutablePointer<CChar>?
        var mtime: UInt32 = 0
        let result = rnp_op_verify_get_file_info(operation, &rawFilename, &mtime)
        if result != RNP_SUCCESS {
            return (nil, nil)
        }

        let filename = string(fromAllocated: rawFilename)
        let date = mtime == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(mtime))
        return (filename.isEmpty ? nil : filename, date)
    }

    private static func protectionInfo(from operation: OpaquePointer?) throws -> ProtectionInfo? {
        var modePointer: UnsafeMutablePointer<CChar>?
        var cipherPointer: UnsafeMutablePointer<CChar>?
        let result = rnp_op_verify_get_protection_info(operation, &modePointer, &cipherPointer, nil)
        if result != RNP_SUCCESS {
            return nil
        }

        return ProtectionInfo(
            mode: string(fromAllocated: modePointer).nilIfEmpty,
            cipher: string(fromAllocated: cipherPointer).nilIfEmpty
        )
    }

    private static func collectRecipients(from operation: OpaquePointer?) throws -> [String] {
        var count: Int = 0
        guard rnp_op_verify_get_recipient_count(operation, &count) == RNP_SUCCESS else {
            return []
        }

        return try (0..<count).compactMap { index in
            var recipient: OpaquePointer?
            try check(
                rnp_op_verify_get_recipient_at(operation, index, &recipient),
                context: "read message recipient"
            )

            var rawKeyID: UnsafeMutablePointer<CChar>?
            try check(
                rnp_recipient_get_keyid(recipient, &rawKeyID),
                context: "read recipient key id"
            )

            return string(fromAllocated: rawKeyID).nilIfEmpty
        }
    }

    private static func collectSignatures(from operation: OpaquePointer?) throws -> [VerifiedSignature] {
        var count: Int = 0
        guard rnp_op_verify_get_signature_count(operation, &count) == RNP_SUCCESS else {
            return []
        }

        return try (0..<count).map { index in
            var signature: OpaquePointer?
            try check(
                rnp_op_verify_get_signature_at(operation, index, &signature),
                context: "read verified signature"
            )

            let status = rnp_op_verify_signature_get_status(signature)

            var keyHandle: OpaquePointer?
            let keyResult = rnp_op_verify_signature_get_key(signature, &keyHandle)
            defer {
                if let keyHandle {
                    _ = rnp_key_handle_destroy(keyHandle)
                }
            }

            var createdAt: UInt32 = 0
            var expiresAfter: UInt32 = 0
            _ = rnp_op_verify_signature_get_times(signature, &createdAt, &expiresAfter)

            var keyID: UnsafeMutablePointer<CChar>?
            var fingerprint: UnsafeMutablePointer<CChar>?
            if keyResult == RNP_SUCCESS, let keyHandle {
                _ = rnp_key_get_keyid(keyHandle, &keyID)
                _ = rnp_key_get_fprint(keyHandle, &fingerprint)
            }

            return VerifiedSignature(
                keyID: string(fromAllocated: keyID).nilIfEmpty,
                fingerprint: string(fromAllocated: fingerprint).nilIfEmpty,
                creationDate: createdAt == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(createdAt)),
                expiresAfter: expiresAfter == 0 ? nil : TimeInterval(expiresAfter),
                statusCode: status,
                isValid: status == RNP_SUCCESS || status == RNP_ERROR_SIGNATURE_EXPIRED
            )
        }
    }

    private static func exportAllPrimaryKeys(from ffi: OpaquePointer?) throws -> [Key] {
        var iterator: OpaquePointer?
        try check(
            rnp_identifier_iterator_create(ffi, &iterator, "fingerprint"),
            context: "create key iterator"
        )
        defer {
            if let iterator {
                _ = rnp_identifier_iterator_destroy(iterator)
            }
        }

        var exported: [Key] = []
        var seenFingerprints = Set<String>()

        while true {
            var identifier: UnsafePointer<CChar>?
            let result = rnp_identifier_iterator_next(iterator, &identifier)
            if result != RNP_SUCCESS {
                break
            }

            guard let identifier else {
                continue
            }

            let fingerprint = String(cString: identifier).uppercased()
            if seenFingerprints.contains(fingerprint) {
                continue
            }

            let handle = try locateKey(fingerprint: fingerprint, in: ffi)
            defer { _ = rnp_key_handle_destroy(handle) }

            var isPrimary = false
            _ = rnp_key_is_primary(handle, &isPrimary)
            guard isPrimary else {
                continue
            }

            exported.append(try exportKey(from: handle))
            seenFingerprints.insert(fingerprint)
        }

        return exported
    }

    private static func exportKey(from handle: OpaquePointer?) throws -> Key {
        let metadata = try metadata(for: handle)

        var hasPublic = false
        var hasSecret = false
        _ = rnp_key_have_public(handle, &hasPublic)
        _ = rnp_key_have_secret(handle, &hasSecret)

        let publicData = hasPublic
            ? try export(handle: handle, flags: UInt32(RNP_KEY_EXPORT_PUBLIC | RNP_KEY_EXPORT_SUBKEYS))
            : nil
        let secretData = hasSecret
            ? try export(handle: handle, flags: UInt32(RNP_KEY_EXPORT_SECRET | RNP_KEY_EXPORT_SUBKEYS))
            : nil

        return Key(publicData: publicData, secretData: secretData, metadata: metadata)
    }

    private static func metadata(for handle: OpaquePointer?) throws -> Key.Metadata {
        let fingerprint = try fingerprint(of: handle)
        let shortKeyID = try keyID(of: handle)
        let userIDs = try self.userIDs(of: handle)
        let algorithm = try self.algorithm(of: handle)
        let keySize = try self.keySize(of: handle)
        let creationDate = try self.creationDate(of: handle)
        let expirationDate = try self.expirationDate(of: handle)
        let isRevoked = try self.isRevoked(handle)
        let revokedDate = try self.revokedDate(of: handle)
        let capabilities = try self.capabilities(of: handle)

        return Key.Metadata(
            fingerprint: fingerprint,
            shortKeyID: shortKeyID,
            userIDs: userIDs,
            primaryAlgorithm: algorithm,
            primaryKeySize: keySize,
            creationDate: creationDate,
            expirationDate: expirationDate,
            isRevoked: isRevoked,
            revokedDate: revokedDate,
            capabilities: capabilities
        )
    }

    private static func export(handle: OpaquePointer?, flags: UInt32) throws -> Data {
        let output = try makeOutput()
        defer { _ = rnp_output_destroy(output) }

        try check(rnp_key_export(handle, output, flags), context: "export key")
        return try outputData(output)
    }

    private static func fingerprint(of handle: OpaquePointer?) throws -> String {
        var raw: UnsafeMutablePointer<CChar>?
        try check(rnp_key_get_fprint(handle, &raw), context: "read key fingerprint")
        return string(fromAllocated: raw)
    }

    private static func keyID(of handle: OpaquePointer?) throws -> String {
        var raw: UnsafeMutablePointer<CChar>?
        try check(rnp_key_get_keyid(handle, &raw), context: "read key id")
        return string(fromAllocated: raw)
    }

    private static func userIDs(of handle: OpaquePointer?) throws -> [String] {
        var count: Int = 0
        try check(rnp_key_get_uid_count(handle, &count), context: "read key user id count")

        return try (0..<count).compactMap { index in
            var raw: UnsafeMutablePointer<CChar>?
            try check(rnp_key_get_uid_at(handle, index, &raw), context: "read key user id")
            let value = string(fromAllocated: raw)
            return value.isEmpty ? nil : value
        }
    }

    private static func algorithm(of handle: OpaquePointer?) throws -> PublicKeyAlgorithm {
        var raw: UnsafeMutablePointer<CChar>?
        try check(rnp_key_get_alg(handle, &raw), context: "read key algorithm")
        return PublicKeyAlgorithm.from(rnp: string(fromAllocated: raw))
    }

    private static func keySize(of handle: OpaquePointer?) throws -> Int {
        var bits: UInt32 = 0
        try check(rnp_key_get_bits(handle, &bits), context: "read key size")

        let keySize = Int(bits)
        let algorithm = try self.algorithm(of: handle)
        if (algorithm == .eddsa || algorithm == .curve25519 || algorithm == .ecdh) && keySize == 255 {
            return 256
        }

        return keySize
    }

    private static func creationDate(of handle: OpaquePointer?) throws -> Date {
        var timestamp: UInt32 = 0
        try check(rnp_key_get_creation(handle, &timestamp), context: "read key creation date")
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private static func expirationDate(of handle: OpaquePointer?) throws -> Date? {
        var expiresAfter: UInt32 = 0
        try check(rnp_key_get_expiration(handle, &expiresAfter), context: "read key expiration")
        guard expiresAfter > 0 else {
            return nil
        }
        let createdAt = try creationDate(of: handle)
        return createdAt.addingTimeInterval(TimeInterval(expiresAfter))
    }

    private static func isRevoked(_ handle: OpaquePointer?) throws -> Bool {
        var revoked = false
        try check(rnp_key_is_revoked(handle, &revoked), context: "read key revocation state")
        return revoked
    }

    private static func revokedDate(of handle: OpaquePointer?) throws -> Date? {
        var signature: OpaquePointer?
        guard rnp_key_get_revocation_signature(handle, &signature) == RNP_SUCCESS else {
            return nil
        }
        defer {
            if let signature {
                _ = rnp_signature_handle_destroy(signature)
            }
        }

        var createdAt: UInt32 = 0
        guard rnp_signature_get_creation(signature, &createdAt) == RNP_SUCCESS, createdAt > 0 else {
            return nil
        }

        return Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    private static func capabilities(of handle: OpaquePointer?) throws -> KeyCapabilities {
        var signKey: OpaquePointer?
        let signResult = rnp_key_get_default_key(handle, "sign", 0, &signKey)
        if let signKey {
            _ = rnp_key_handle_destroy(signKey)
        }

        var encryptKey: OpaquePointer?
        let encryptResult = rnp_key_get_default_key(handle, "encrypt", 0, &encryptKey)
        if let encryptKey {
            _ = rnp_key_handle_destroy(encryptKey)
        }

        return KeyCapabilities(
            canEncrypt: encryptResult == RNP_SUCCESS,
            canSign: signResult == RNP_SUCCESS
        )
    }

    private static func locateKey(fingerprint: String, in ffi: OpaquePointer?) throws -> OpaquePointer? {
        var handle: OpaquePointer?
        try check(
            rnp_locate_key(ffi, "fingerprint", fingerprint, &handle),
            context: "locate key \(fingerprint)"
        )

        guard let handle else {
            throw makeNSError(
                "Key \(fingerprint) was not found",
                result: rnp_result_t(RNP_ERROR_KEY_NOT_FOUND)
            )
        }

        return handle
    }

    private static func defaultKey(for usage: String, from handle: OpaquePointer?) throws -> OpaquePointer? {
        var defaultHandle: OpaquePointer?
        try check(
            rnp_key_get_default_key(handle, usage, 0, &defaultHandle),
            context: "select default \(usage) key"
        )

        guard let defaultHandle else {
            throw makeNSError(
                "No default \(usage) key available",
                result: rnp_result_t(RNP_ERROR_NO_SUITABLE_KEY)
            )
        }

        return defaultHandle
    }

    private static func importKeys(_ data: Data, into ffi: OpaquePointer?) throws -> [String] {
        let input = try makeInput(from: data)
        defer { _ = rnp_input_destroy(input) }

        let flags = UInt32(
            RNP_LOAD_SAVE_PUBLIC_KEYS |
            RNP_LOAD_SAVE_SECRET_KEYS |
            RNP_LOAD_SAVE_PERMISSIVE
        )
        var results: UnsafeMutablePointer<CChar>?
        try check(rnp_import_keys(ffi, input, flags, &results), context: "import key material")
        return parseImportedFingerprints(from: string(fromAllocated: results))
    }

    private static func withFFI<T>(
        keys: [Key] = [],
        passphraseForKey: ((Key) -> String?)? = nil,
        body: (OpaquePointer?) throws -> T
    ) throws -> T {
        var ffi: OpaquePointer?
        try publicKeyFormat.withCString { pubFormat in
            try secretKeyFormat.withCString { secFormat in
                try check(rnp_ffi_create(&ffi, pubFormat, secFormat), context: "create RNP ffi")
            }
        }
        defer {
            if let ffi {
                _ = rnp_ffi_destroy(ffi)
            }
        }

        var passwordProvider: Unmanaged<PasswordProviderBox>?
        if let passphraseForKey {
            let box = PasswordProviderBox(keys: keys, resolver: passphraseForKey)
            passwordProvider = Unmanaged.passRetained(box)
            try check(
                rnp_ffi_set_pass_provider(ffi, rnpPasswordCallback, passwordProvider?.toOpaque()),
                context: "configure password provider"
            )
        }
        defer {
            passwordProvider?.release()
        }

        var importedPayloads = Set<String>()
        for key in keys {
            if let publicKey = key.publicKey {
                let publicIdentifier = "\(key.fingerprint):public"
                if importedPayloads.insert(publicIdentifier).inserted {
                    _ = try importKeys(publicKey.exportedData, into: ffi)
                }
            }

            if let secretKey = key.secretKey {
                let secretIdentifier = "\(key.fingerprint):secret"
                if importedPayloads.insert(secretIdentifier).inserted {
                    _ = try importKeys(secretKey.exportedData, into: ffi)
                }
            }
        }

        return try body(ffi)
    }

    private static func makeInput(from data: Data) throws -> OpaquePointer? {
        var input: OpaquePointer?
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw makeNSError("Cannot create RNP input from empty buffer")
            }

            try check(
                rnp_input_from_memory(&input, baseAddress, data.count, true),
                context: "create RNP input"
            )
        }
        return input
    }

    private static func makeOutput() throws -> OpaquePointer? {
        var output: OpaquePointer?
        try check(rnp_output_to_memory(&output, 0), context: "create RNP output")
        return output
    }

    private static func outputData(_ output: OpaquePointer?) throws -> Data {
        var rawBuffer: UnsafeMutablePointer<UInt8>?
        var length: Int = 0
        try check(
            rnp_output_memory_get_buf(output, &rawBuffer, &length, true),
            context: "read RNP output"
        )

        guard let rawBuffer else {
            return Data()
        }

        defer {
            rnp_buffer_destroy(rawBuffer)
        }

        return Data(bytes: rawBuffer, count: length)
    }

    private static func string(fromAllocated raw: UnsafeMutablePointer<CChar>?) -> String {
        guard let raw else {
            return ""
        }

        defer {
            rnp_buffer_destroy(raw)
        }

        return String(cString: raw)
    }

    private static func parseImportedFingerprints(from results: String) -> [String] {
        guard
            !results.isEmpty,
            let data = results.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let keys = json["keys"] as? [[String: Any]]
        else {
            return []
        }

        return keys.compactMap { keyInfo in
            (keyInfo["fingerprint"] as? String)?.uppercased()
        }
    }

    private static func primaryFingerprint(of handle: OpaquePointer?) throws -> String {
        var raw: UnsafeMutablePointer<CChar>?
        if rnp_key_get_primary_fprint(handle, &raw) == RNP_SUCCESS {
            let primaryFingerprint = string(fromAllocated: raw)
            if !primaryFingerprint.isEmpty {
                return primaryFingerprint.uppercased()
            }
        }

        return try fingerprint(of: handle)
    }

    private static func fingerprints(for key: Key) throws -> [String] {
        try withFFI(keys: [key]) { ffi in
            let handle = try locateKey(fingerprint: key.fingerprint, in: ffi)
            defer { _ = rnp_key_handle_destroy(handle) }

            var fingerprints = [try fingerprint(of: handle)]
            var subkeyCount = 0
            _ = rnp_key_get_subkey_count(handle, &subkeyCount)

            for index in 0..<subkeyCount {
                do {
                    var subkey: OpaquePointer?
                    try check(
                        rnp_key_get_subkey_at(handle, index, &subkey),
                        context: "read key subkey"
                    )
                    defer {
                        if let subkey {
                            _ = rnp_key_handle_destroy(subkey)
                        }
                    }

                    fingerprints.append(try fingerprint(of: subkey))
                }
            }

            return fingerprints
        }
    }

    private static func curveName(for keyBitsLength: Int) -> String {
        switch keyBitsLength {
        case 384:
            return "NIST P-384"
        case 521:
            return "NIST P-521"
        default:
            return "NIST P-256"
        }
    }

    private static func check(_ result: rnp_result_t, context: String) throws {
        guard result == RNP_SUCCESS else {
            throw makeNSError(context, result: result)
        }
    }

    private static func makeNSError(
        _ context: String,
        result: rnp_result_t = rnp_result_t(RNP_ERROR_GENERIC)
    ) -> NSError {
        let code = result == RNP_ERROR_BAD_PASSWORD ? invalidPassphraseCode : genericErrorCode
        return NSError(
            domain: objectivePGPDomain,
            code: Int(code),
            userInfo: [
                NSLocalizedDescriptionKey: "\(context) failed (\(result))",
                "RNPErrorCode": result
            ]
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
