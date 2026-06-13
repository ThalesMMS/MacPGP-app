import Foundation

extension String {
    var isValidEmail: Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return range(of: emailRegex, options: .regularExpression) != nil
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isPGPArmored: Bool {
        contains("-----BEGIN PGP")
    }

    func extractPGPBlock() -> String? {
        let pattern = #"-----BEGIN PGP[^-]+-----[\s\S]*?-----END PGP[^-]+-----"#
        guard let range = range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(self[range])
    }

}
