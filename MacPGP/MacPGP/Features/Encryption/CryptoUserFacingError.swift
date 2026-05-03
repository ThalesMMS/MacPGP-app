import Foundation

struct CryptoUserFacingError: Equatable {
    var title: String
    var message: String

    static func from(_ error: Error, title: String = NSLocalizedString("error.generic.title", comment: "Generic error alert title")) -> CryptoUserFacingError {
        CryptoUserFacingError(title: title, message: error.userFacingMessage)
    }
}
