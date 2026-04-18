enum AccessibilityIdentifiers {
    enum KeyGeneration {
        static let fullNameField = "keyGeneration.fullNameField"
        static let emailField = "keyGeneration.emailField"
        static let commentField = "keyGeneration.commentField"
        static let algorithmLabel = "keyGeneration.algorithmLabel"
        static let algorithmValue = "keyGeneration.algorithmValue"
        static let keySizePicker = "keyGeneration.keySizePicker"
        static let neverExpiresToggle = "keyGeneration.neverExpiresToggle"
        static let expirationPicker = "keyGeneration.expirationPicker"
        static let passphraseField = "keyGeneration.passphraseField"
        static let confirmPassphraseField = "keyGeneration.confirmPassphraseField"
        static let storePassphraseToggle = "keyGeneration.storePassphraseToggle"
    }

    enum TrustLevelPicker {
        static let ultimateTrustWarningDescription = "Ultimate Trust Warning Description"
        static let trustLevelUpdatedMessage = "Trust Level Updated Message"

        static func description(token: String) -> String {
            "TrustDescription_\(token)"
        }

        static func canCertifyDescription(token: String) -> String {
            "TrustDescription_\(token)_CanCertify"
        }
    }
}
