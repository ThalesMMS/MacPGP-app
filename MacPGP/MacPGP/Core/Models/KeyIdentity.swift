import Foundation

struct KeyIdentity: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let email: String
    let comment: String?

    init(id: UUID = UUID(), name: String, email: String, comment: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.comment = comment
    }

    var displayString: String {
        var result = name
        if let comment = comment, !comment.isEmpty {
            result += " (\(comment))"
        }
        result += " <\(email)>"
        return result
    }

    var shortDisplayString: String {
        if !name.isEmpty {
            return name
        }
        return email
    }

    static func parse(from userID: String) -> KeyIdentity {
        var name = ""
        var email = ""
        var comment: String?

        let emailPattern = #"<([^>]+)>"#
        let commentPattern = #"\(([^)]+)\)"#

        if let emailMatch = userID.range(of: emailPattern, options: .regularExpression) {
            let match = String(userID[emailMatch])
            email = String(match.dropFirst().dropLast())
        }

        if let commentMatch = userID.range(of: commentPattern, options: .regularExpression) {
            let match = String(userID[commentMatch])
            comment = String(match.dropFirst().dropLast())
        }

        var nameString = userID
        if let emailRange = userID.range(of: emailPattern, options: .regularExpression) {
            nameString = String(nameString[..<emailRange.lowerBound])
        }
        if let commentRange = nameString.range(of: commentPattern, options: .regularExpression) {
            nameString = String(nameString[..<commentRange.lowerBound])
        }
        name = nameString.trimmingCharacters(in: .whitespaces)

        return KeyIdentity(name: name, email: email, comment: comment)
    }
}
