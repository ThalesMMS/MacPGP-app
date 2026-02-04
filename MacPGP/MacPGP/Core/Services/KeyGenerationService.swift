import Foundation
import ObjectivePGP

struct KeyGenerationParameters {
    var name: String
    var email: String
    var comment: String?
    var passphrase: String
    var algorithm: KeyAlgorithm
    var keySize: Int
    var expirationMonths: Int?

    var userID: String {
        var result = name
        if let comment = comment, !comment.isEmpty {
            result += " (\(comment))"
        }
        result += " <\(email)>"
        return result
    }

    init(
        name: String,
        email: String,
        comment: String? = nil,
        passphrase: String,
        algorithm: KeyAlgorithm = .rsa,
        keySize: Int = 4096,
        expirationMonths: Int? = 24
    ) {
        self.name = name
        self.email = email
        self.comment = comment
        self.passphrase = passphrase
        self.algorithm = algorithm
        self.keySize = keySize
        self.expirationMonths = expirationMonths
    }
}

final class KeyGenerationService {
    static let shared = KeyGenerationService()

    private init() {}

    func generateKey(with parameters: KeyGenerationParameters) throws -> Key {
        let keyGenerator = KeyGenerator()

        keyGenerator.keyBitsLength = Int32(parameters.keySize)

        switch parameters.algorithm {
        case .rsa:
            keyGenerator.keyAlgorithm = .RSA
        case .ecdsa:
            keyGenerator.keyAlgorithm = .ECDSA
        case .eddsa:
            keyGenerator.keyAlgorithm = .edDSA
        default:
            keyGenerator.keyAlgorithm = .RSA
        }

        let key = keyGenerator.generate(
            for: parameters.userID,
            passphrase: parameters.passphrase
        )

        return key
    }

    func generateKeyAsync(
        with parameters: KeyGenerationParameters,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Key, OperationError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            progress(0.1)

            do {
                let key = try self.generateKey(with: parameters)
                progress(1.0)

                DispatchQueue.main.async {
                    completion(.success(key))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.keyGenerationFailed(underlying: error)))
                }
            }
        }
    }

    func validatePassphrase(_ passphrase: String) -> [PassphraseValidationIssue] {
        var issues: [PassphraseValidationIssue] = []

        if passphrase.count < 8 {
            issues.append(.tooShort(minimum: 8))
        }

        if passphrase.count > 0 && passphrase.rangeOfCharacter(from: .uppercaseLetters) == nil {
            issues.append(.noUppercase)
        }

        if passphrase.count > 0 && passphrase.rangeOfCharacter(from: .lowercaseLetters) == nil {
            issues.append(.noLowercase)
        }

        if passphrase.count > 0 && passphrase.rangeOfCharacter(from: .decimalDigits) == nil {
            issues.append(.noDigit)
        }

        let specialCharacters = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;':\",./<>?")
        if passphrase.count > 0 && passphrase.rangeOfCharacter(from: specialCharacters) == nil {
            issues.append(.noSpecialCharacter)
        }

        return issues
    }

    func passphraseStrength(_ passphrase: String) -> PassphraseStrength {
        let issues = validatePassphrase(passphrase)

        if passphrase.isEmpty {
            return .none
        }

        let score = 5 - issues.count

        switch score {
        case 5:
            return passphrase.count >= 12 ? .strong : .good
        case 4:
            return .good
        case 3:
            return .fair
        case 2:
            return .weak
        default:
            return .veryWeak
        }
    }
}

enum PassphraseValidationIssue {
    case tooShort(minimum: Int)
    case noUppercase
    case noLowercase
    case noDigit
    case noSpecialCharacter

    var description: String {
        switch self {
        case .tooShort(let minimum):
            return "Must be at least \(minimum) characters"
        case .noUppercase:
            return "Should contain uppercase letters"
        case .noLowercase:
            return "Should contain lowercase letters"
        case .noDigit:
            return "Should contain numbers"
        case .noSpecialCharacter:
            return "Should contain special characters"
        }
    }
}

enum PassphraseStrength: Int, CaseIterable {
    case none = 0
    case veryWeak = 1
    case weak = 2
    case fair = 3
    case good = 4
    case strong = 5

    var description: String {
        switch self {
        case .none: return "No passphrase"
        case .veryWeak: return "Very Weak"
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .good: return "Good"
        case .strong: return "Strong"
        }
    }

    var color: String {
        switch self {
        case .none: return "gray"
        case .veryWeak: return "red"
        case .weak: return "orange"
        case .fair: return "yellow"
        case .good: return "green"
        case .strong: return "blue"
        }
    }
}
